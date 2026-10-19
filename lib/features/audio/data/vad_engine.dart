import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../../../core/diagnostics/diagnostics_service.dart';
import '../../pipeline/domain/ai_pipeline.dart';
import '../../settings/data/model_manager_repository.dart';

class SpeechSegment {
  const SpeechSegment({
    required this.start,
    required this.end,
    required this.chunks,
    this.speechRatio = 1.0,
  });

  final Duration start;
  final Duration end;
  final List<PcmChunk> chunks;
  final double speechRatio;
}

abstract interface class VoiceActivityDetector {
  bool get installed;
  Stream<SpeechSegment> detectSpeech(
    Stream<PcmChunk> audioStream, {
    void Function(Duration pts, Duration? activeSpeechStart)? onProgress,
  });
}

class LocalVadEngine implements VoiceActivityDetector {
  LocalVadEngine(
    this._modelRepository,
    this._diagnostics, {
    this.threshold = 0.55, // Speech onset threshold
    this.minSpeechDuration = const Duration(milliseconds: 400),
    this.maxMergeGap = const Duration(milliseconds: 600), // Split on 600ms pauses for turn taking
    this.preRollDuration = const Duration(milliseconds: 300),
    this.maxSpeechDuration = const Duration(seconds: 10), // Cap at 10s for precise sentence mapping
    this.postRollDuration = const Duration(milliseconds: 300),
  });

  final ModelManagerRepository _modelRepository;
  final DiagnosticsService _diagnostics;
  final double threshold;
  final Duration minSpeechDuration;
  final Duration maxMergeGap;
  final Duration preRollDuration;
  final Duration maxSpeechDuration;
  final Duration postRollDuration;

  static const String modelId = 'vad_silero';
  static const int _contextSize = 64;
  static const int _windowSize = 512;
  static const int _stateSize = 128; // Updated for Silero VAD v5+

  OrtSession? _session;
  bool _onnxBroken = false;
  final Float32List _state = Float32List(2 * 1 * _stateSize);
  final Float32List _context = Float32List(_contextSize);
  final Float32List _windowFloatBuffer = Float32List(_contextSize + _windowSize);

  @override
  bool get installed => true;

  Future<void> _ensureInitialized() async {
    if (_session != null) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    final modelFile = await _modelRepository.getModelFile(
      modelId,
      'silero_vad.onnx',
    );
    if (!await modelFile.exists()) {
      throw ModelDownloadException('Silero VAD model missing. Please download it in settings.');
    }

    final sessionOptions = OrtSessionOptions();
    _session = await OnnxRuntime().createSession(
      modelFile.path,
      options: sessionOptions,
    );
  }

  @override
  Stream<SpeechSegment> detectSpeech(
    Stream<PcmChunk> audioStream, {
    void Function(Duration pts, Duration? activeSpeechStart)? onProgress,
  }) async* {
    await _ensureInitialized();
    _resetState();

    final windowBuffer = BytesBuilder();
    const windowSizeBytes = 512 * 2;
    const windowDuration = Duration(milliseconds: 32);

    final List<PcmChunk> preRollBuffer = [];
    _RawSpeechRange? active;
    _RawSpeechRange? pendingGap;

    Duration? bufferStartPts;

    await for (final chunk in audioStream) {
      final bytesPerMs = (chunk.sampleRate * 1 * 2) ~/ 1000;

      if (bufferStartPts == null) {
        bufferStartPts = chunk.pts;
      } else {
        // Check if the new chunk is continuous with the data in the buffer
        final expectedNextPts = bufferStartPts +
            Duration(milliseconds: windowBuffer.length ~/ bytesPerMs);
        final drift = (chunk.pts - expectedNextPts).inMilliseconds.abs();

        if (drift > 100) {
          // Discontinuity (e.g., seek), clear old buffer and state
          windowBuffer.clear();
          bufferStartPts = chunk.pts;
          preRollBuffer.clear();

          if (active != null && active.end - active.start >= minSpeechDuration) {
            _diagnostics.log('VAD', 'Discontinuity detected, flushing segment: ${active.start.inMilliseconds}ms - ${active.end.inMilliseconds}ms');
             yield SpeechSegment(
              start: active.start,
              end: active.end,
              chunks: List.unmodifiable(active.chunks),
            );
          }

          active = null;
          pendingGap = null;
          _resetState();
        }
      }

      windowBuffer.add(chunk.bytes);

      while (windowBuffer.length >= windowSizeBytes) {
        final windowBytes = windowBuffer.takeBytes();
        final currentWindowBytes = windowBytes.sublist(0, windowSizeBytes);
        if (windowBytes.length > windowSizeBytes) {
          windowBuffer.add(windowBytes.sublist(windowSizeBytes));
        }

        final currentPts = bufferStartPts!;
        final currentChunk = PcmChunk(
          pts: currentPts,
          sampleRate: chunk.sampleRate,
          channels: 1,
          bytes: currentWindowBytes,
          playbackSessionId: chunk.playbackSessionId,
          timelineEpoch: chunk.timelineEpoch,
          seekGeneration: chunk.seekGeneration,
        );

        if (onProgress != null) {
          onProgress.call(currentPts + windowDuration, active?.start);
        }

        final isSpeech = await _isSpeechData(
          currentWindowBytes,
          chunk.sampleRate,
        );

        bufferStartPts += windowDuration;

        if (isSpeech) {
          active ??= _RawSpeechRange(
            start: preRollBuffer.isNotEmpty
                ? preRollBuffer.first.pts
                : currentPts,
            end: currentPts + windowDuration,
            chunks: [...preRollBuffer],
          );

          if (pendingGap != null) {
            active.chunks.addAll(pendingGap.chunks);
            pendingGap = null;
          }
          active.chunks.add(currentChunk);
          active.end = currentPts + windowDuration;

          preRollBuffer.clear();

          // Enforce max duration for Whisper (15s limit is safer for Tiny model)
          if (active.end - active.start >= maxSpeechDuration) {
            _diagnostics.log('VAD', 'Segment reached max duration (${maxSpeechDuration.inSeconds}s): ${active.start.inMilliseconds}ms - ${active.end.inMilliseconds}ms');
            yield SpeechSegment(
              start: active.start,
              end: active.end,
              chunks: List.unmodifiable(active.chunks),
            );
            active = null;
            pendingGap = null;
            // Quan trọng: Sau khi cắt cưỡng ép hoặc kết thúc segment,
            // reset state VAD hoàn toàn để tránh rò rỉ tín hiệu sang segment sau.
            _resetState();
          }
        } else {
          if (active != null) {
            pendingGap ??= _RawSpeechRange(
              start: currentPts,
              end: currentPts + windowDuration,
              chunks: [],
            );
            pendingGap.chunks.add(currentChunk);
            pendingGap.end = currentPts + windowDuration;

            if (pendingGap.end - pendingGap.start > maxMergeGap) {
              if (active.end - active.start >= minSpeechDuration) {
                // Thêm một phần post-roll để tránh bị cụt chữ cuối
                final postRollChunks = (postRollDuration.inMilliseconds / windowDuration.inMilliseconds).round();
                if (pendingGap.chunks.isNotEmpty) {
                  active.chunks.addAll(pendingGap.chunks.take(min(postRollChunks, pendingGap.chunks.length)));
                  active.end = active.chunks.last.pts + windowDuration;
                }

                _diagnostics.log('VAD', 'Speech segment detected: ${active.start.inMilliseconds}ms - ${active.end.inMilliseconds}ms (${active.chunks.length} chunks)');
                yield SpeechSegment(
                  start: active.start,
                  end: active.end,
                  chunks: List.unmodifiable(active.chunks),
                );
              }
              active = null;
              pendingGap = null;
              // Reset state sau khi một cụm hội thoại kết thúc (yên lặng đủ lâu)
              _resetState();
            }
          } else {
            preRollBuffer.add(currentChunk);
            final totalPreRoll =
                preRollBuffer.length * windowDuration.inMilliseconds;
            if (totalPreRoll > preRollDuration.inMilliseconds) {
              preRollBuffer.removeAt(0);
            }
          }
        }
      }
    }

    if (active != null && active.end - active.start >= minSpeechDuration) {
      yield SpeechSegment(
        start: active.start,
        end: active.end,
        chunks: List.unmodifiable(active.chunks),
      );
    }
  }

  void _resetState() {
    _state.fillRange(0, _state.length, 0.0);
    _context.fillRange(0, _context.length, 0.0);
  }

  Future<bool> _isSpeechData(Uint8List bytes, int sampleRate) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return _isSpeechEnergy(bytes);
    final session = _session;
    if (session == null || _onnxBroken) return _isSpeechEnergy(bytes);

    OrtValue? inputOrt;
    OrtValue? srOrt;
    OrtValue? stateOrt;
    Map<String, OrtValue>? outputs;

    try {
      // Input = Context (64) + Window (512) = 576 samples
      _windowFloatBuffer.setRange(0, _contextSize, _context);
      _fillPcm16ToFloat32Buffer(bytes, _windowFloatBuffer, offset: _contextSize);

      inputOrt = await OrtValue.fromList(_windowFloatBuffer, [1, _windowFloatBuffer.length]);
      srOrt = await OrtValue.fromList(Int64List.fromList([sampleRate]), []); // Scalar shape []
      stateOrt = await OrtValue.fromList(_state, [2, 1, _stateSize]);

      final inputs = {'input': inputOrt, 'sr': srOrt, 'state': stateOrt};
      outputs = await session.run(inputs);

      final outputVal = await outputs['output']?.asList();
      final stateVal = await outputs['state']?.asList();

      if (outputVal != null && stateVal != null) {
        final probability = (outputVal[0] as List)[0] as double;
        _updateState(_state, stateVal);

        // Update context with the last 64 samples of the current window
        final int16Data = bytes.buffer.asInt16List();
        const double scale = 1.0 / 32768.0;
        for (int i = 0; i < _contextSize; i++) {
          _context[i] = int16Data[int16Data.length - _contextSize + i] * scale;
        }

        return probability >= threshold;
      }
    } catch (e, st) {
      _onnxBroken = true;
      _diagnostics.log(
        'VAD_ENGINE',
        'Inference error (falling back to energy VAD): $e',
        level: LogLevel.error,
        details: st.toString(),
      );
    } finally {
      await inputOrt?.dispose();
      await srOrt?.dispose();
      await stateOrt?.dispose();
      if (outputs != null) {
        for (var v in outputs.values) {
          await v.dispose();
        }
      }
    }
    return _isSpeechEnergy(bytes);
  }

  void _fillPcm16ToFloat32Buffer(Uint8List bytes, Float32List targetBuffer, {int offset = 0}) {
    final int16Data = bytes.buffer.asInt16List();
    const double scale = 1.0 / 32768.0;
    final len = min(int16Data.length, targetBuffer.length - offset);
    for (var i = 0; i < len; i++) {
      targetBuffer[offset + i] = int16Data[i] * scale;
    }
  }

  void _updateState(Float32List state, List<dynamic> newValue) {
    int idx = 0;
    void traverse(dynamic item) {
      if (item is List) {
        for (final child in item) {
          traverse(child);
        }
      } else if (item is num) {
        if (idx < state.length) {
          state[idx++] = item.toDouble();
        }
      }
    }
    traverse(newValue);
  }

  bool _isSpeechEnergy(Uint8List bytes) {
    final samples = bytes.buffer.asInt16List();
    double sumSquare = 0;
    for (final s in samples) {
      sumSquare += s * s;
    }
    final energy = sqrt(sumSquare / samples.length);
    return energy >= 250.0;
  }

  void dispose() {
    _session?.close();
    _session = null;
  }
}

class _RawSpeechRange {
  _RawSpeechRange({
    required this.start,
    required this.end,
    required this.chunks,
  });
  final Duration start;
  Duration end;
  final List<PcmChunk> chunks;
}
