import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

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
  Stream<SpeechSegment> detectSpeech(Stream<PcmChunk> audioStream);
}

class LocalVadEngine implements VoiceActivityDetector {
  LocalVadEngine(
    this._modelRepository, {
    this.threshold = 0.5,
    this.minSpeechDuration = const Duration(milliseconds: 250),
    this.maxMergeGap = const Duration(milliseconds: 300),
    this.preRollDuration = const Duration(milliseconds: 200),
  });

  final ModelManagerRepository _modelRepository;
  final double threshold;
  final Duration minSpeechDuration;
  final Duration maxMergeGap;
  final Duration preRollDuration;

  static const String modelId = 'vad_silero';

  OrtSession? _session;
  final Float32List _h = Float32List(2 * 1 * 64);
  final Float32List _c = Float32List(2 * 1 * 64);

  @override
  bool get installed => true;

  Future<void> _ensureInitialized() async {
    if (_session != null) return;

    final modelFile = await _modelRepository.getModelFile(modelId);
    if (!await modelFile.exists()) {
      return;
    }

    final sessionOptions = OrtSessionOptions();
    _session = await OnnxRuntime().createSession(modelFile.path, options: sessionOptions);
  }

  @override
  Stream<SpeechSegment> detectSpeech(Stream<PcmChunk> audioStream) async* {
    await _ensureInitialized();
    _resetState();

    final windowBuffer = BytesBuilder();
    const windowSizeSamples = 512;
    const windowSizeBytes = windowSizeSamples * 2;
    const windowDuration = Duration(milliseconds: 32);

    final List<PcmChunk> preRollBuffer = [];
    _RawSpeechRange? active;
    _RawSpeechRange? pendingGap;

    var windowOffset = Duration.zero;
    var lastBasePts = Duration.zero;

    await for (final chunk in audioStream) {
      if (chunk.pts != lastBasePts) {
        windowOffset = Duration.zero;
        lastBasePts = chunk.pts;
      }

      windowBuffer.add(chunk.bytes);

      while (windowBuffer.length >= windowSizeBytes) {
        final windowBytes = windowBuffer.takeBytes();
        final currentWindowBytes = windowBytes.sublist(0, windowSizeBytes);
        if (windowBytes.length > windowSizeBytes) {
          windowBuffer.add(windowBytes.sublist(windowSizeBytes));
        }

        final currentPts = chunk.pts + windowOffset;
        final currentChunk = PcmChunk(
          pts: currentPts,
          sampleRate: chunk.sampleRate,
          channels: 1,
          bytes: currentWindowBytes,
        );

        final isSpeech = await _isSpeechData(currentWindowBytes, chunk.sampleRate);
        windowOffset += windowDuration;

        if (isSpeech) {
          active ??= _RawSpeechRange(
            start: preRollBuffer.isNotEmpty ? preRollBuffer.first.pts : currentPts,
            end: currentPts + windowDuration,
            chunks: [...preRollBuffer, currentChunk],
          );

          if (pendingGap != null) {
            active.chunks.addAll(pendingGap.chunks);
            pendingGap = null;
          }
          active.chunks.add(currentChunk);
          active.end = currentPts + windowDuration;

          preRollBuffer.clear();
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
                yield SpeechSegment(
                  start: active.start,
                  end: active.end,
                  chunks: List.unmodifiable(active.chunks),
                );
              }
              active = null;
              pendingGap = null;
            }
          } else {
            // Lưu vào pre-roll khi đang im lặng
            preRollBuffer.add(currentChunk);
            final totalPreRoll = preRollBuffer.length * windowDuration.inMilliseconds;
            if (totalPreRoll > preRollDuration.inMilliseconds) {
              preRollBuffer.removeAt(0);
            }
          }
        }
      }
    }

    // Yield final segment if active
    if (active != null && active.end - active.start >= minSpeechDuration) {
      yield SpeechSegment(
        start: active.start,
        end: active.end,
        chunks: List.unmodifiable(active.chunks),
      );
    }
  }

  void _resetState() {
    _h.fillRange(0, _h.length, 0.0);
    _c.fillRange(0, _c.length, 0.0);
  }

  Future<bool> _isSpeechData(Uint8List bytes, int sampleRate) async {
    final session = _session;
    if (session == null) return _isSpeechEnergy(bytes);

    try {
      final float32Audio = _pcm16ToFloat32(bytes);
      final inputOrt = await OrtValue.fromList(float32Audio, [1, float32Audio.length]);
      final srOrt = await OrtValue.fromList(Int64List.fromList([sampleRate]), [1]);
      final hOrt = await OrtValue.fromList(_h, [2, 1, 64]);
      final cOrt = await OrtValue.fromList(_c, [2, 1, 64]);

      final inputs = {
        'input': inputOrt,
        'sr': srOrt,
        'h': hOrt,
        'c': cOrt,
      };

      final outputs = await session.run(inputs);

      final outputVal = await outputs['output']?.asList();
      final hVal = await outputs['h']?.asList();
      final cVal = await outputs['c']?.asList();

      if (outputVal != null && hVal != null && cVal != null) {
        final probability = outputVal[0][0] as double;
        _updateState(_h, hVal as List<List<List<double>>>);
        _updateState(_c, cVal as List<List<List<double>>>);

        await inputOrt.dispose();
        await srOrt.dispose();
        await hOrt.dispose();
        await cOrt.dispose();

        // Also dispose output tensors
        await outputs['output']?.dispose();
        await outputs['h']?.dispose();
        await outputs['c']?.dispose();

        return probability >= threshold;
      }
    } catch (e) { /* ignore */ }
    return _isSpeechEnergy(bytes);
  }

  void _updateState(Float32List state, List<List<List<double>>> newValue) {
    int idx = 0;
    for (var i = 0; i < newValue.length; i++) {
      for (var j = 0; j < newValue[i].length; j++) {
        for (var k = 0; k < newValue[i][j].length; k++) {
          state[idx++] = newValue[i][j][k].toDouble();
        }
      }
    }
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

  Float32List _pcm16ToFloat32(Uint8List bytes) {
    final int16Data = bytes.buffer.asInt16List();
    final float32Data = Float32List(int16Data.length);
    for (var i = 0; i < int16Data.length; i++) {
      float32Data[i] = int16Data[i] / 32768.0;
    }
    return float32Data;
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
