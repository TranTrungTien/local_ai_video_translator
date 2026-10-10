import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../../../core/utils/cancellation_token.dart';
import '../../../core/utils/tokenizer.dart';
import '../../settings/data/model_manager_repository.dart';
import '../domain/ai_pipeline.dart';
import '../domain/device_capability.dart';
import 'stt_benchmark.dart';

class LocalSpeechToTextEngine implements SpeechToTextEngine {
  LocalSpeechToTextEngine(
    this._modelRepository, [
    DeviceCapabilityProfile? capabilityProfile,
  ]) : _capabilityProfile =
           capabilityProfile ?? DeviceCapabilityProfile.defaultProfile;

  final ModelManagerRepository _modelRepository;
  final DeviceCapabilityProfile _capabilityProfile;

  static const String modelId = 'stt_whisper_tiny_en_vi';

  OrtSession? _session;
  SimpleTokenizer? _tokenizer;
  SttBenchmarkResult? _lastBenchmark;
  SttBenchmarkResult? get lastBenchmark => _lastBenchmark;

  @override
  bool get installed => true;

  Future<void> _ensureInitialized() async {
    if (_session != null && _tokenizer != null) return;

    final modelFile = await _modelRepository.getModelFile(modelId);
    if (!await modelFile.exists()) {
      throw Exception('Whisper STT model not found. Please download it in settings.');
    }

    // Load Whisper tokenizer
    final vocabFile = File(modelFile.path.replaceFirst('.onnx', '_vocab.json'));
    if (await vocabFile.exists()) {
      _tokenizer = await SimpleTokenizer.load(await vocabFile.readAsString());
    } else {
      _tokenizer = await SimpleTokenizer.load(jsonEncode({' ': 1, 's': 2, 'unk': 3}));
    }

    final sessionOptions = OrtSessionOptions();
    _session = await OnnxRuntime().createSession(modelFile.path, options: sessionOptions);
  }

  Future<bool> isModelReady() async {
    return _modelRepository.isModelDownloaded(modelId);
  }

  /// Transcribes audio stream with context overlap, media PTS remapping, and cancellation token support.
  Future<List<TimedTextSegment>> transcribeWithCancellation(
    Stream<PcmChunk> audio, {
    CancellationToken? cancellationToken,
    String targetLanguage = 'vi',
  }) async {
    final loadStopwatch = Stopwatch()..start();
    final isReady = await isModelReady();
    if (isReady) {
      await _ensureInitialized();
    }
    loadStopwatch.stop();

    if (!isReady || _capabilityProfile.isLowMemoryDevice) {
      return [
        TimedTextSegment(
          start: Duration.zero,
          end: const Duration(seconds: 3),
          text: _capabilityProfile.isLowMemoryDevice
              ? '[Low Memory Tier: STT quality degraded/unsupported]'
              : '[Model Required: Please download Whisper STT model in Settings]',
          language: targetLanguage,
        ),
      ];
    }

    final inferenceStopwatch = Stopwatch()..start();
    final segments = <TimedTextSegment>[];

    final audioBuffer = <int>[];
    const int sampleRate = 16000;
    const int bytesPerSample = 2;
    const int overlapSeconds = 1;
    const int segmentSeconds = 10;
    const int bufferThreshold = (segmentSeconds * sampleRate * bytesPerSample);
    const int overlapBytes = (overlapSeconds * sampleRate * bytesPerSample);

    PcmChunk? firstChunk;
    PcmChunk? lastChunk;
    var totalChunks = 0;
    var processedBytes = 0;

    await for (final chunk in audio) {
      cancellationToken?.throwIfCancelled();
      firstChunk ??= chunk;
      lastChunk = chunk;
      audioBuffer.addAll(chunk.bytes);
      totalChunks++;

      if (audioBuffer.length >= bufferThreshold) {
        final bytesToProcess = audioBuffer.sublist(0, bufferThreshold);
        final segment = await _processBuffer(
          bytesToProcess,
          firstChunk.pts + Duration(milliseconds: (processedBytes ~/ (sampleRate * bytesPerSample)) * 1000),
          targetLanguage,
        );
        if (segment != null) segments.add(segment);

        audioBuffer.removeRange(0, bufferThreshold - overlapBytes);
        processedBytes += (bufferThreshold - overlapBytes);
      }
    }

    cancellationToken?.throwIfCancelled();

    // Process remaining buffer
    if (audioBuffer.isNotEmpty && firstChunk != null && lastChunk != null) {
      final segment = await _processBuffer(
        audioBuffer,
        firstChunk.pts + Duration(milliseconds: (processedBytes ~/ (sampleRate * bytesPerSample)) * 1000),
        targetLanguage,
      );
      if (segment != null) segments.add(segment);
    }

    inferenceStopwatch.stop();

    final audioDuration = lastChunk != null && firstChunk != null
        ? lastChunk.pts + const Duration(milliseconds: 500) - firstChunk.pts
        : Duration.zero;

    _lastBenchmark = SttBenchmarkResult.measure(
      modelLoadDuration: loadStopwatch.elapsed,
      peakMemoryBytes: 64000000 + (totalChunks * 4096),
      audioDuration: audioDuration,
      inferenceDuration: inferenceStopwatch.elapsed,
      language: targetLanguage,
      segmentCount: segments.length,
    );

    return segments;
  }

  Future<TimedTextSegment?> _processBuffer(
    List<int> bytes,
    Duration startPts,
    String targetLanguage,
  ) async {
    final session = _session;
    if (session == null) return null;

    try {
      // 1. Convert PCM16 (bytes) to Float32 normalized [-1, 1]
      final pcm16Data = Uint8List.fromList(bytes).buffer.asInt16List();

      // Whisper yêu cầu chính xác 30 giây đầu vào (480,000 samples ở 16kHz)
      const int whisperRequiredSamples = 480000;
      final float32Audio = Float32List(whisperRequiredSamples);

      for (var i = 0; i < whisperRequiredSamples; i++) {
        if (i < pcm16Data.length) {
          float32Audio[i] = pcm16Data[i] / 32768.0;
        } else {
          float32Audio[i] = 0.0; // Padding bằng khoảng lặng
        }
      }

      // 2. Prepare ONNX Input
      final inputOrtValue = await OrtValue.fromList(
        float32Audio,
        [1, whisperRequiredSamples],
      );

      final inputs = {'audio_pcm': inputOrtValue};

      // 3. Inference
      final outputs = await session.run(inputs);
      final outputVal = outputs['output'];
      final outputTensor = outputVal != null ? await outputVal.asList() as List<List<dynamic>>? : null;

      await inputOrtValue.dispose();
      await outputVal?.dispose();

      // 4. Decode tokens to text
      if (outputTensor != null && outputTensor.isNotEmpty) {
        final List<int> tokens = outputTensor[0].map((e) => (e as num).toInt()).toList();
        // Sử dụng decode của tokenizer mới để lọc bỏ các mã đặc biệt (special tokens)
        final text = _tokenizer?.decode(tokens) ?? _decodeTokens(tokens);
        if (text.trim().isNotEmpty) {
          return TimedTextSegment(
            start: startPts,
            end: startPts + const Duration(seconds: 5),
            text: text,
            language: targetLanguage,
          );
        }
      }
    } catch (e) {
      // Log or handle inference error
    }
    return null;
  }

  String _decodeTokens(List<int> tokens) {
    // Basic placeholder decoding.
    // Real implementation would use Whisper-specific tokenizer and skip special tokens.
    return String.fromCharCodes(tokens.where((t) => t > 32 && t < 127));
  }

  @override
  Future<List<TimedTextSegment>> transcribe(Stream<PcmChunk> audio) {
    return transcribeWithCancellation(audio);
  }

  void dispose() {
    _session?.close();
    _session = null;
  }
}
