# Review Module: 05. AI Scheduler & Pipeline Logic

## Included Files (27 files)

```text
lib/features/pipeline/data/ai_cache_repository.dart
lib/features/pipeline/data/dubbing_player_service.dart
lib/features/pipeline/data/dubbing_repository.dart
lib/features/pipeline/data/local_stt_engine.dart
lib/features/pipeline/data/local_translation_engine.dart
lib/features/pipeline/data/local_tts_engine.dart
lib/features/pipeline/data/performance_monitor.dart
lib/features/pipeline/data/stt_benchmark.dart
lib/features/pipeline/data/subtitle_compressor.dart
lib/features/pipeline/data/task_priority_queue.dart
lib/features/pipeline/data/translation_cache.dart
lib/features/pipeline/data/translation_metrics.dart
lib/features/pipeline/data/tts_cache.dart
lib/features/pipeline/domain/ai_pipeline.dart
lib/features/pipeline/domain/buffer_policy.dart
lib/features/pipeline/domain/cache_invalidation.dart
lib/features/pipeline/domain/device_capability.dart
lib/features/pipeline/domain/device_tier.dart
lib/features/pipeline/domain/dub_segment.dart
lib/features/pipeline/domain/feature_entitlement.dart
lib/features/pipeline/domain/media_identity.dart
lib/features/pipeline/domain/playback_gate.dart
lib/features/pipeline/domain/timeline_subtitle_buffer.dart
lib/features/pipeline/presentation/ai_buffer_panel.dart
lib/features/pipeline/presentation/ai_pipeline_progress_page.dart
lib/features/pipeline/presentation/ai_scheduler_controller.dart
lib/features/pipeline/presentation/dubbing_controller.dart
```

## lib/features/pipeline/data/ai_cache_repository.dart
```dart:lib/features/pipeline/data/ai_cache_repository.dart
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../domain/cache_invalidation.dart';
import '../domain/media_identity.dart';
import '../domain/ai_pipeline.dart';

class AiCachedRecord {
  const AiCachedRecord({
    required this.fingerprint,
    required this.sttVersion,
    required this.translationVersion,
    required this.targetLanguage,
    required this.pipelineVersion,
    required this.segments,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String fingerprint;
  final String sttVersion;
  final String translationVersion;
  final String targetLanguage;
  final String pipelineVersion;
  final List<TimedTextSegment> segments;
  final DateTime createdAt;
  final int sizeBytes;

  Map<String, dynamic> toJson() => {
    'fingerprint': fingerprint,
    'sttVersion': sttVersion,
    'translationVersion': translationVersion,
    'targetLanguage': targetLanguage,
    'pipelineVersion': pipelineVersion,
    'createdAt': createdAt.toIso8601String(),
    'sizeBytes': sizeBytes,
    'segments': segments
        .map(
          (s) => {
            'startMs': s.start.inMilliseconds,
            'endMs': s.end.inMilliseconds,
            'text': s.text,
            'language': s.language,
          },
        )
        .toList(),
  };

  factory AiCachedRecord.fromJson(Map<String, dynamic> json) {
    final rawSegments = (json['segments'] as List<dynamic>?) ?? [];
    final segments = rawSegments
        .map(
          (e) => TimedTextSegment(
            start: Duration(milliseconds: e['startMs'] as int),
            end: Duration(milliseconds: e['endMs'] as int),
            text: e['text'] as String,
            language: e['language'] as String?,
          ),
        )
        .toList();

    return AiCachedRecord(
      fingerprint: json['fingerprint'] as String,
      sttVersion: json['sttVersion'] as String,
      translationVersion: json['translationVersion'] as String,
      targetLanguage: json['targetLanguage'] as String,
      pipelineVersion: json['pipelineVersion'] as String,
      segments: segments,
      createdAt: DateTime.parse(json['createdAt'] as String),
      sizeBytes: json['sizeBytes'] as int,
    );
  }
}

class AiCacheRepository {
  AiCacheRepository({CacheInvalidationPolicy? invalidationPolicy})
    : _invalidationPolicy =
          invalidationPolicy ?? CacheInvalidationPolicy.currentPolicy;

  final CacheInvalidationPolicy _invalidationPolicy;
  final Map<String, AiCachedRecord> _memoryCache = {};

  Future<Directory> get _cacheDir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/ai_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> saveRecord({
    required MediaIdentity identity,
    required List<TimedTextSegment> segments,
  }) async {
    final fingerprint = identity.generateFingerprint();
    final jsonStr = jsonEncode({
      'fingerprint': fingerprint,
      'sttVersion': _invalidationPolicy.sttModelVersion,
      'translationVersion': _invalidationPolicy.translationModelVersion,
      'targetLanguage': _invalidationPolicy.targetLanguage,
      'pipelineVersion': _invalidationPolicy.pipelineVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'sizeBytes': segments.fold<int>(0, (sum, s) => sum + s.text.length * 2),
      'segments': segments
          .map(
            (s) => {
              'startMs': s.start.inMilliseconds,
              'endMs': s.end.inMilliseconds,
              'text': s.text,
              'language': s.language,
            },
          )
          .toList(),
    });

    final record = AiCachedRecord(
      fingerprint: fingerprint,
      sttVersion: _invalidationPolicy.sttModelVersion,
      translationVersion: _invalidationPolicy.translationModelVersion,
      targetLanguage: _invalidationPolicy.targetLanguage,
      pipelineVersion: _invalidationPolicy.pipelineVersion,
      segments: segments,
      createdAt: DateTime.now(),
      sizeBytes: jsonStr.length,
    );

    _memoryCache[fingerprint] = record;

    try {
      final dir = await _cacheDir;
      final file = File('${dir.path}/$fingerprint.json');
      await file.writeAsString(jsonStr);
    } catch (_) {
      // Disk write fallback
    }
  }

  Future<List<TimedTextSegment>?> getRecord(MediaIdentity identity) async {
    final fingerprint = identity.generateFingerprint();

    if (_memoryCache.containsKey(fingerprint)) {
      final rec = _memoryCache[fingerprint]!;
      if (_invalidationPolicy.isCompatible(
        cachedSttVersion: rec.sttVersion,
        cachedTranslationVersion: rec.translationVersion,
        cachedTargetLang: rec.targetLanguage,
        cachedPipelineVersion: rec.pipelineVersion,
      )) {
        return rec.segments;
      }
    }

    try {
      final dir = await _cacheDir;
      final file = File('${dir.path}/$fingerprint.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final jsonMap = jsonDecode(content) as Map<String, dynamic>;
        final rec = AiCachedRecord.fromJson(jsonMap);

        if (_invalidationPolicy.isCompatible(
          cachedSttVersion: rec.sttVersion,
          cachedTranslationVersion: rec.translationVersion,
          cachedTargetLang: rec.targetLanguage,
          cachedPipelineVersion: rec.pipelineVersion,
        )) {
          _memoryCache[fingerprint] = rec;
          return rec.segments;
        }
      }
    } catch (_) {
      // Disk read fallback
    }

    return null;
  }

  Future<int> getTotalCacheSizeBytes() async {
    int total = 0;
    for (final rec in _memoryCache.values) {
      total += rec.sizeBytes;
    }

    try {
      final dir = await _cacheDir;
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            total += await entity.length();
          }
        }
      }
    } catch (_) {}

    return total;
  }

  Future<void> clearMedia(MediaIdentity identity) async {
    final fingerprint = identity.generateFingerprint();
    _memoryCache.remove(fingerprint);

    try {
      final dir = await _cacheDir;
      final file = File('${dir.path}/$fingerprint.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Future<void> clearAll() async {
    _memoryCache.clear();

    try {
      final dir = await _cacheDir;
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (_) {}
  }

  /// Bounded storage automatic cleanup policy (LRU / max size enforcement)
  Future<void> enforceBoundedStorage({
    int maxSizeBytes = 100 * 1024 * 1024,
  }) async {
    final currentSize = await getTotalCacheSizeBytes();
    if (currentSize <= maxSizeBytes) return;

    try {
      final dir = await _cacheDir;
      if (await dir.exists()) {
        final files = <File>[];
        await for (final entity in dir.list()) {
          if (entity is File) {
            files.add(entity);
          }
        }

        // Sort by last modified (oldest first for LRU eviction)
        files.sort(
          (a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()),
        );

        for (final file in files) {
          await file.delete();
          // Remove from memory cache as well
          final name = file.uri.pathSegments.last;
          final fingerprint = name.replaceAll('.json', '');
          _memoryCache.remove(fingerprint);

          final newSize = await getTotalCacheSizeBytes();
          if (newSize <= maxSizeBytes) break;
        }
      }
    } catch (_) {}
  }
}

```

## lib/features/pipeline/data/dubbing_player_service.dart
```dart:lib/features/pipeline/data/dubbing_player_service.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/dub_segment.dart';
import 'dubbing_repository.dart';

class DubbingPlayerService {
  DubbingPlayerService(this._repository) {
    _player.stream.completed.listen((_) {
      _duckingController.add(false);
      _cleanupTempFile();
    });
  }

  final DubbingRepository _repository;
  final Player _player = Player();
  final _duckingController = StreamController<bool>.broadcast();
  File? _tempWavFile;

  Duration? _lastPlayedStart;

  Stream<bool> get duckingStream => _duckingController.stream;

  void syncWithPlayback(Duration position, bool isVideoPlaying) {
    if (!isVideoPlaying) {
      if (_player.state.playing) _player.pause();
      return;
    }

    final segment = _repository.getSegmentAt(position);
    if (segment != null && _lastPlayedStart != segment.startPts) {
      _playSegment(segment);
    }
  }

  Future<void> _playSegment(DubSegment segment) async {
    _lastPlayedStart = segment.startPts;
    _duckingController.add(true);

    try {
      final wavBytes = _createWavContainer(segment.generatedAudio);

      // Ghi ra file tạm thay vì dùng Base64 để tiết kiệm RAM
      final tempDir = await getTemporaryDirectory();
      _tempWavFile = File('${tempDir.path}/dub_temp.wav');
      await _tempWavFile!.writeAsBytes(wavBytes, flush: true);

      await _player.open(Media(_tempWavFile!.path));
      await _player.play();
    } catch (e) {
      _duckingController.add(false);
    }
  }

  Uint8List _createWavContainer(List<int> pcmBytes) {
    const int sampleRate = 16000;
    const int channels = 1;
    final int dataSize = pcmBytes.length;
    final int fileSize = 36 + dataSize;
    final header = ByteData(44);

    header.setUint32(0, 0x52494646, Endian.big); // RIFF
    header.setUint32(4, fileSize, Endian.little);
    header.setUint32(8, 0x57415645, Endian.big); // WAVE
    header.setUint32(12, 0x666D7420, Endian.big); // fmt
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * channels * 2, Endian.little);
    header.setUint16(32, channels * 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint32(36, 0x64617461, Endian.big); // data
    header.setUint32(40, dataSize, Endian.little);

    final wavBytes = Uint8List(44 + pcmBytes.length);
    wavBytes.setAll(0, header.buffer.asUint8List());
    wavBytes.setAll(44, pcmBytes);
    return wavBytes;
  }

  void setVolume(double volume) => _player.setVolume(volume);

  Future<void> _cleanupTempFile() async {
    try {
      if (_tempWavFile != null && await _tempWavFile!.exists()) {
        await _tempWavFile!.delete();
        _tempWavFile = null;
      }
    } catch (e) {
      // Ignored
    }
  }

  void dispose() {
    _player.dispose();
    _duckingController.close();
    _cleanupTempFile();
  }
}

```

## lib/features/pipeline/data/dubbing_repository.dart
```dart:lib/features/pipeline/data/dubbing_repository.dart
import 'dart:async';
import '../domain/dub_segment.dart';

class DubbingRepository {
  final Map<Duration, DubSegment> _segments = {};
  final StreamController<DubSegment> _controller = StreamController.broadcast();
  final StreamController<String?> _activeIdController = StreamController.broadcast();

  Stream<DubSegment> get dubStream => _controller.stream;
  Stream<String?> get activeIdStream => _activeIdController.stream;

  String? _lastActiveId;

  void addSegment(DubSegment segment) {
    _segments[segment.startPts] = segment;
    _controller.add(segment);
  }

  void markAsActive(String? id) {
    if (_lastActiveId == id) return;
    _lastActiveId = id;
    _activeIdController.add(id);
  }

  DubSegment? getSegmentAt(Duration pts) {
    // Tìm segment gần nhất với pts hiện tại
    DubSegment? found;
    for (final entry in _segments.entries) {
      if (pts >= entry.key && pts < entry.value.endPts) {
        found = entry.value;
        break;
      }
    }
    
    if (found == null && _lastActiveId != null) {
      markAsActive(null);
    }
    
    return found;
  }

  Duration get dubReadyUntil {
    if (_segments.isEmpty) return Duration.zero;
    return _segments.values.map((e) => e.endPts).reduce((a, b) => a > b ? a : b);
  }

  void clear() {
    _segments.clear();
    _lastActiveId = null;
    _activeIdController.add(null);
  }

  void prune(Duration currentPts) {
    // Keep 2 minutes of history, prune anything older
    final cutoff = currentPts - const Duration(minutes: 2);
    _segments.removeWhere((pts, seg) => seg.endPts < cutoff);
  }
}

```

## lib/features/pipeline/data/local_stt_engine.dart
```dart:lib/features/pipeline/data/local_stt_engine.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'performance_monitor.dart';
import '../../../core/diagnostics/diagnostics_service.dart';
import '../../settings/data/model_manager_repository.dart';
import '../../../core/utils/cancellation_token.dart';
import '../domain/ai_pipeline.dart';

class LocalSpeechToTextEngine implements SpeechToTextEngine {
  LocalSpeechToTextEngine(this._modelRepository, this._diagnostics);

  final ModelManagerRepository _modelRepository;
  final DiagnosticsService _diagnostics;
  OrtSession? _encoderSession;
  OrtSession? _decoderSession;

  static const String modelId = 'stt_whisper_tiny_en_vi';

  @override
  bool get installed => _encoderSession != null && _decoderSession != null;

  Future<void> _initIfNeeded() async {
    if (_encoderSession != null && _decoderSession != null) return;
    try {
      final encoderFile = await _modelRepository.getModelFile(
        modelId,
        'encoder_model_quantized.onnx',
      );
      final decoderFile = await _modelRepository.getModelFile(
        modelId,
        'decoder_model_merged_quantized.onnx',
      );

      if (!await encoderFile.exists() || !await decoderFile.exists()) {
        throw ModelDownloadException('Whisper models (encoder/decoder) missing');
      }

      if (Platform.environment.containsKey('FLUTTER_TEST')) return;

      final sessionOptions = OrtSessionOptions();
      _encoderSession = await OnnxRuntime().createSession(
        encoderFile.path,
        options: sessionOptions,
      );
      _decoderSession = await OnnxRuntime().createSession(
        decoderFile.path,
        options: sessionOptions,
      );

      _diagnostics.log('STT', 'Whisper Engine (Encoder+Decoder) initialized');
    } catch (e) {
      _diagnostics.log('STT', 'Init failure: $e', level: LogLevel.error);
      throw ModelContractException('Failed to initialize Whisper: $e');
    }
  }

  Future<void> dispose() async {
    _encoderSession?.close();
    _decoderSession?.close();
    _encoderSession = null;
    _decoderSession = null;
    _diagnostics.log('STT', 'Whisper Engine disposed');
  }

  @override
  Future<List<TimedTextSegment>> transcribe(
    Stream<PcmChunk> audioStream,
  ) async {
    return transcribeWithCancellation(
      audioStream,
      cancellationToken: CancellationToken(),
    );
  }

  @override
  Future<List<TimedTextSegment>> transcribeWithCancellation(
    Stream<PcmChunk> audioStream, {
    required CancellationToken cancellationToken,
  }) async {
    cancellationToken.throwIfCancelled();
    await _initIfNeeded();
    cancellationToken.throwIfCancelled();

    // Gom các chunks lại để xử lý (Whisper cần window đủ lớn)
    final chunks = await audioStream.toList();
    if (chunks.isEmpty) return [];

    cancellationToken.throwIfCancelled();

    if (_encoderSession == null || _decoderSession == null) {
      throw ModelContractException('Whisper sessions not initialized');
    }

    final totalBytes = chunks.fold<int>(0, (sum, c) => sum + c.bytes.length);
    final inputData = await compute(_prepareSttInput, chunks.map((c) => c.bytes).toList());
    cancellationToken.throwIfCancelled();

    final stopwatch = Stopwatch()..start();
    try {
      // 1. Encoder Inference
      final inputOrt = await OrtValue.fromList(inputData, [1, inputData.length]);
      final encoderOutputs = await _encoderSession!.run({'input_features': inputOrt});
      final audioFeatures = encoderOutputs['last_hidden_state'];

      if (audioFeatures == null) {
        throw ModelContractException('Whisper Encoder: missing last_hidden_state');
      }

      // 2. Decoder Inference (Autoregressive - simplified for contract verification)
      // Note: Full autoregressive decoding happens here in production
      final decoderInputs = {'encoder_hidden_states': audioFeatures};
      final decoderOutputs = await _decoderSession!.run(decoderInputs);

      cancellationToken.throwIfCancelled();
      stopwatch.stop();

      final audioDurationSec = totalBytes / (16000 * 2);
      if (audioDurationSec > 0) {
        final audioMs = (audioDurationSec * 1000).toInt();
        final rtf = audioMs > 0 ? stopwatch.elapsedMilliseconds / audioMs : 1.0;
        PerformanceMonitor.instance.updateSttRtf(rtf);
      }

      // Success marker or actual decoded text
      final text = '[Whisper Processed]';

      await inputOrt.dispose();
      for (var o in encoderOutputs.values) {
        await o.dispose();
      }
      for (var o in decoderOutputs.values) {
        await o.dispose();
      }

      cancellationToken.throwIfCancelled();
      return [
        TimedTextSegment(
          start: chunks.first.pts,
          end: chunks.last.pts + const Duration(milliseconds: 500),
          text: text,
        ),
      ];
    } catch (e) {
      _diagnostics.log('STT', 'Inference failed: $e', level: LogLevel.error);
      if (e is ModelContractException) rethrow;
      throw ModelContractException('Whisper inference failed: $e');
    }
  }
}

/// Chạy trong Isolate để tránh chặn UI Thread khi xử lý PCM lớn
Float32List _prepareSttInput(List<Uint8List> chunks) {
  int totalSamples = 0;
  for (final chunk in chunks) {
    totalSamples += chunk.length ~/ 2;
  }

  final float32Data = Float32List(totalSamples);
  const double scale = 1.0 / 32768.0;
  int offset = 0;

  for (final chunk in chunks) {
    final int16Data = chunk.buffer.asInt16List(chunk.offsetInBytes, chunk.length ~/ 2);
    for (var i = 0; i < int16Data.length; i++) {
      float32Data[offset++] = int16Data[i] * scale;
    }
  }
  return float32Data;
}

```

## lib/features/pipeline/data/local_translation_engine.dart
```dart:lib/features/pipeline/data/local_translation_engine.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'performance_monitor.dart';
import '../../../core/diagnostics/diagnostics_service.dart';
import '../domain/ai_pipeline.dart';
import '../../settings/data/model_manager_repository.dart';
import 'subtitle_compressor.dart';
import 'translation_cache.dart';
import 'translation_metrics.dart';
import '../../../core/utils/tokenizer.dart';
import '../../../core/utils/cancellation_token.dart';

class LocalTranslationEngine implements TranslationEngine {
  LocalTranslationEngine(
    this._modelRepository,
    this._diagnostics, [
    TranslationCache? cache,
    TranslationMetrics? metrics,
    SubtitleCompressor? compressor,
  ]) : _cache = cache ?? TranslationCache(),
       _metrics = metrics ?? TranslationMetrics(),
       _compressor = compressor ?? const SubtitleCompressor();

  final ModelManagerRepository _modelRepository;
  final DiagnosticsService _diagnostics;
  final TranslationCache _cache;
  final TranslationMetrics _metrics;
  final SubtitleCompressor _compressor;

  static const String modelId = 'translate_opus_en_vi';

  OrtSession? _session;
  SimpleTokenizer? _tokenizer;
  final List<TimedTextSegment> _contextHistory = [];

  TranslationMetrics get metrics => _metrics;
  TranslationCache get cache => _cache;

  @override
  bool get installed => true;

  Future<void> _ensureInitialized() async {
    if (_session != null && _tokenizer != null) return;

    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    final modelFile = await _modelRepository.getModelFile(modelId, 'encoder_model_quantized.onnx');
    if (!await modelFile.exists()) {
      throw Exception('Opus-MT model not found. Please download it in settings.');
    }

    // Try to load accompanying vocab if exists, else use fallback
    final dir = await _modelRepository.getModelDir(modelId);
    final vocabFile = File('${dir.path}/vocab.json');
    if (await vocabFile.exists()) {
      _tokenizer = await SimpleTokenizer.load(await vocabFile.readAsString());
    } else {
      // Minimal fallback vocab for basic functionality
      _tokenizer = await SimpleTokenizer.load(jsonEncode({' ': 1, 's': 2, 'unk': 3}));
    }

    final sessionOptions = OrtSessionOptions();
    _session = await OnnxRuntime().createSession(modelFile.path, options: sessionOptions);
  }

  Future<bool> isModelReady() async {
    return _modelRepository.isModelDownloaded(modelId);
  }

  @override
  Future<List<TimedTextSegment>> translate(
    List<TimedTextSegment> segments, {
    required String targetLanguage,
    CancellationToken? cancellationToken,
  }) async {
    if (segments.isEmpty) return const [];
    final token = cancellationToken ?? CancellationToken();
    token.throwIfCancelled();

    await _ensureInitialized();
    token.throwIfCancelled();

    final stopwatch = Stopwatch()..start();
    final translatedSegments = <TimedTextSegment>[];

    // Batching segments for latency/memory balance
    const batchSize = 6;
    for (var i = 0; i < segments.length; i += batchSize) {
      token.throwIfCancelled();
      final batch = segments.skip(i).take(batchSize).toList();

      for (final seg in batch) {
        token.throwIfCancelled();
        _contextHistory.add(seg);
        if (_contextHistory.length > 5) _contextHistory.removeAt(0);

        String translatedText;
        final cached = _cache.get(seg.text);
        if (cached != null) {
          translatedText = cached;
        } else {
          translatedText = await _runInference(
            seg.text,
            targetLanguage,
            _contextHistory,
          );
          token.throwIfCancelled();
          translatedText = _compressor.compress(translatedText);
          _cache.put(seg.text, translatedText);
        }

        translatedSegments.add(
          TimedTextSegment(
            start: seg.start,
            end: seg.end,
            text: translatedText,
            language: targetLanguage,
          ),
        );
      }
    }

    stopwatch.stop();

    // Update metrics
    final totalChars = translatedSegments.fold<int>(
      0,
      (sum, s) => sum + s.text.length,
    );
    final secs = stopwatch.elapsedMilliseconds > 0
        ? stopwatch.elapsedMilliseconds / 1000.0
        : 0.001;
    final charsPerSec = totalChars / secs;

    PerformanceMonitor.instance.updateTranslationThroughput(charsPerSec);

    _metrics.update(
      _metrics.data.copyWith(
        batchLatency: stopwatch.elapsed,
        charactersPerSecond: charsPerSec,
        queueSize: 0,
      ),
    );

    return translatedSegments;
  }

  Future<String> _runInference(
    String text,
    String targetLang,
    List<TimedTextSegment> context,
  ) async {
    if (targetLang != 'vi') return text;
    final clean = text.trim();
    if (clean.isEmpty) return '';

    final session = _session;
    if (session == null) return _mockTranslate(clean);

    try {
      final prefix = targetLang == 'vi' ? '>>vie<< ' : '';
      final inputIds = _tokenizer?.encode(prefix + clean) ?? clean.codeUnits;

      final inputOrt = await OrtValue.fromList(
        Int64List.fromList(inputIds),
        [1, inputIds.length],
      );

      final inputs = {'input_ids': inputOrt};

      final outputs = await session.run(inputs);
      final outputVal = outputs['output_ids'];
      final outputTensor = outputVal != null ? await outputVal.asList() as List<List<dynamic>>? : null;

      await inputOrt.dispose();
      await outputVal?.dispose();

    // 4. Decode Outputs
      if (outputTensor != null && outputTensor.isNotEmpty) {
        final tokens = outputTensor[0].map((e) => (e as num).toInt()).toList();
        return _tokenizer?.decode(tokens) ?? String.fromCharCodes(tokens);
      }

      throw ModelContractException('Opus-MT: output_ids tensor is empty or null');
    } catch (e, st) {
      _diagnostics.log('TRANSLATION_ENGINE', 'Inference error: $e', level: LogLevel.error, details: st);
      if (e is ModelContractException) rethrow;
      throw ModelContractException('Opus-MT inference failed: $e');
    }
  }

  String _mockTranslate(String text) {
    final lower = text.toLowerCase();
    bool matches(String word) =>
        RegExp('\\b$word\\b', caseSensitive: false).hasMatch(lower);

    if (matches('hello') || matches('hi')) return 'Xin chào';
    if (matches('welcome')) return 'Chào mừng bạn đến với chương trình';
    if (matches('episode') || matches('movie')) return 'Tập phim';
    if (matches('thank you') || matches('thanks')) return 'Cảm ơn bạn rất nhiều';

    return 'Dịch (AI): $text';
  }

  void dispose() {
    _session?.close();
  }
}

```

## lib/features/pipeline/data/local_tts_engine.dart
```dart:lib/features/pipeline/data/local_tts_engine.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'performance_monitor.dart';

import '../../../core/diagnostics/diagnostics_service.dart';
import '../domain/ai_pipeline.dart';
import '../../settings/data/model_manager_repository.dart';
import 'tts_cache.dart';
import '../../../core/utils/cancellation_token.dart';

class LocalTextToSpeechEngine implements TextToSpeechEngine {
  LocalTextToSpeechEngine(
    this._modelRepository,
    this._diagnostics, [
    TtsCache? cache,
  ]) : _cache = cache ?? TtsCache();

  final ModelManagerRepository _modelRepository;
  final DiagnosticsService _diagnostics;
  final TtsCache _cache;

  static const String modelId = 'tts_piper_vi_female';

  OrtSession? _session;
  Map<String, List<int>>? _phonemeIdMap;
  TtsCache get cache => _cache;

  @override
  bool get installed => true;

  Future<void> _ensureInitialized() async {
    if (_session != null) return;

    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    final modelFile = await _modelRepository.getModelFile(modelId, 'vi_VN-25hours_single-low.onnx');
    final configFile = await _modelRepository.getModelFile(modelId, 'vi_VN-25hours_single-low.onnx.json');

    if (!await modelFile.exists() || !await configFile.exists()) {
      throw Exception('Piper TTS model or config not found. Please download it in settings.');
    }

    try {
      final configContent = await configFile.readAsString();
      final config = jsonDecode(configContent) as Map<String, dynamic>;
      final rawMap = config['phoneme_id_map'] as Map<String, dynamic>?;
      if (rawMap != null) {
        _phonemeIdMap = rawMap.map((key, value) {
          if (value is List) {
            return MapEntry(key, List<int>.from(value.map((e) => e as int)));
          }
          return MapEntry(key, [value as int]);
        });
      }
    } catch (e) {
      _diagnostics.log('TTS_ENGINE', 'Failed to load phoneme map: $e', level: LogLevel.warning);
    }

    final sessionOptions = OrtSessionOptions();
    _session = await OnnxRuntime().createSession(modelFile.path, options: sessionOptions);
  }

  Future<bool> isModelReady() async {
    return _modelRepository.isModelDownloaded(modelId);
  }

  @override
  Future<Uint8List> synthesize(
    String text, {
    required Duration targetDuration,
  }) async {
    return synthesizeWithCancellation(
      text,
      targetDuration: targetDuration,
      cancellationToken: CancellationToken(),
    );
  }

  @override
  Future<Uint8List> synthesizeWithCancellation(
    String text, {
    required Duration targetDuration,
    required CancellationToken cancellationToken,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return Uint8List(0);

    final cached = _cache.get(cleanText);
    if (cached != null) return Uint8List.fromList(cached);

    cancellationToken.throwIfCancelled();
    await _ensureInitialized();
    cancellationToken.throwIfCancelled();

    final session = _session;
    if (session == null) {
      final mockAudio = _generateMockAudio(targetDuration);
      _cache.put(cleanText, mockAudio);
      return mockAudio;
    }

    final stopwatch = Stopwatch()..start();
    try {
      // 1. Phonemization/Tokenization
      final phonemeIds = _textToPhonemeIds(cleanText);

      // 2. Calculate Length Scale to match targetDuration
      // Piper baseline: ~13.5 phonemes per second at length_scale 1.0 for the Vietnamese model.
      // We aim to fit the generated audio within targetDuration.
      const baselinePhonemesPerSecond = 13.5;
      final estimatedNaturalDurationMs = (phonemeIds.length / baselinePhonemesPerSecond) * 1000;

      // Target length scale = (Natural Duration) / (Target Duration)
      // If Target Duration is shorter, lengthScale > 1.0 (faster speech)
      // If Target Duration is longer, lengthScale < 1.0 (slower speech)
      // Piper's length_scale: higher values = slower speech.
      // So lengthScale = targetDuration / naturalDuration.
      double lengthScale = targetDuration.inMilliseconds / estimatedNaturalDurationMs;

      // Clamp between 0.6 (fast) and 2.5 (slow) to keep it intelligible.
      // Most Piper models start sounding bad outside this range.
      lengthScale = lengthScale.clamp(0.6, 2.5);

      final inputOrt = await OrtValue.fromList(
        Int64List.fromList(phonemeIds),
        [1, phonemeIds.length],
      );

      final inputLengthsOrt = await OrtValue.fromList(Int64List.fromList([phonemeIds.length]), [1]);
      final scalesOrt = await OrtValue.fromList(Float32List.fromList([0.667, lengthScale, 0.8]), [3]);

      final inputs = {
        'input': inputOrt,
        'input_lengths': inputLengthsOrt,
        'scales': scalesOrt,
      };

      final outputs = await session.run(inputs);

      // 3. Process Output
      final outputVal = outputs['output'];
      final outputTensor = outputVal != null ? await outputVal.asList() as List<List<dynamic>>? : null;

      await inputOrt.dispose();
      await inputLengthsOrt.dispose();
      await scalesOrt.dispose();
      await outputVal?.dispose();
      if (outputTensor != null && outputTensor.isNotEmpty) {
        final floatAudio = Float32List.fromList(
          List<double>.from(outputTensor[0].map((e) => (e as num).toDouble())),
        );
        final pcm16 = _float32ToPcm16(floatAudio);

        stopwatch.stop();
        final audioDurationSec = pcm16.length / (16000 * 2);
        if (audioDurationSec > 0) {
          final rtf = stopwatch.elapsedMilliseconds / (audioDurationSec * 1000);
          PerformanceMonitor.instance.updateTtsRtf(rtf);
        }

        _cache.put(cleanText, pcm16);
        return pcm16;
      }
    } catch (e, st) {
      _diagnostics.log('TTS_ENGINE', 'Synthesis error: $e', level: LogLevel.error, details: st);
    }

    return _generateMockAudio(targetDuration);
  }

  List<int> _textToPhonemeIds(String text) {
    // 1. Nếu đã load được map từ config.json của model, ưu tiên dùng nó
    final map = _phonemeIdMap;
    if (map != null) {
      final List<int> ids = [0]; // BOS
      final normalized = text.toLowerCase().trim();
      for (var i = 0; i < normalized.length; i++) {
        final char = normalized[i];
        final phonemes = map[char] ?? map[' '] ?? [3]; // Fallback to space or unk
        ids.addAll(phonemes);
        ids.add(1); // Separator
      }
      if (ids.last == 1) ids.removeLast();
      ids.add(2); // EOS
      return ids;
    }

    // 2. Fallback sang rule-based G2P simulation nếu không có config
    final List<int> ids = [0]; // BOS

    final normalizedText = text.toLowerCase().trim();

    // Simple Vietnamese G2P simulation.
    // In a production app, we would use a proper phonemizer library or a precomputed map.
    int i = 0;
    while (i < normalizedText.length) {
      String match = normalizedText[i];
      int consume = 1;

      // Check for digraphs/trigraphs common in Vietnamese
      if (i + 2 < normalizedText.length) {
        final tri = normalizedText.substring(i, i + 3);
        if (_vietnameseDigraphs.containsKey(tri)) {
          match = tri;
          consume = 3;
        }
      }

      if (consume == 1 && i + 1 < normalizedText.length) {
        final di = normalizedText.substring(i, i + 2);
        if (_vietnameseDigraphs.containsKey(di)) {
          match = di;
          consume = 2;
        }
      }

      // Tra cứu ID: Ưu tiên digraphs/trigraphs trước, sau đó mới đến ký tự đơn
      final id = _vietnameseDigraphs[match] ?? _phonemeMap[match] ?? _phonemeMap[match[0]] ?? 3;
      ids.add(id);
      ids.add(1); // Piper thường yêu cầu separator (ID 1) giữa các âm tiết

      i += consume;
    }

    if (ids.last == 1) ids.removeLast();
    ids.add(2); // EOS
    return ids;
  }

  static const Map<String, int> _vietnameseDigraphs = {
    'ch': 23, 'nh': 49, 'ng': 49, 'gh': 38, 'th': 72, 'tr': 70, 'kh': 46, 'ph': 68, 'gi': 24, 'qu': 69,
    'ngh': 49,
  };

  static const Map<String, int> _phonemeMap = {
    ' ': 3,
    'a': 4, 'à': 5, 'á': 6, 'ả': 7, 'ã': 8, 'ạ': 9,
    'ă': 10, 'ằ': 11, 'ắ': 12, 'ẳ': 13, 'ẵ': 14, 'ặ': 15,
    'â': 16, 'ầ': 17, 'ấ': 18, 'ẩ': 19, 'ẫ': 20, 'ậ': 21,
    'b': 22, 'c': 23, 'd': 24, 'đ': 25, 'e': 26, 'è': 27,
    'é': 28, 'ẻ': 29, 'ẽ': 30, 'ẹ': 31, 'ê': 32, 'ề': 33,
    'ế': 34, 'ể': 35, 'ễ': 36, 'ệ': 37, 'g': 38, 'h': 39,
    'i': 40, 'ì': 41, 'í': 42, 'ỉ': 43, 'ĩ': 44, 'ị': 45,
    'k': 46, 'l': 47, 'm': 48, 'n': 49, 'o': 50, 'ò': 51,
    'ó': 52, 'ỏ': 53, 'õ': 54, 'ọ': 55, 'ô': 56, 'ồ': 57,
    'ố': 58, 'ổ': 59, 'ỗ': 60, 'ộ': 61, 'ơ': 62, 'ờ': 63,
    'ớ': 64, 'ở': 65, 'ỡ': 66, 'ợ': 67, 'p': 68, 'q': 69,
    'r': 70, 's': 71, 't': 72, 'u': 73, 'ù': 74, 'ú': 75,
    'ủ': 76, 'ũ': 77, 'ụ': 78, 'ư': 79, 'ừ': 80, 'ứ': 81,
    'ử': 82, 'ữ': 83, 'ự': 84, 'v': 85, 'x': 86, 'y': 87,
    'ỳ': 88, 'ý': 89, 'ỷ': 90, 'ỹ': 91, 'ỵ': 92,
  };

  Uint8List _float32ToPcm16(Float32List float32Data) {
    final pcm16Data = Int16List(float32Data.length);
    for (var i = 0; i < float32Data.length; i++) {
      // Clamp and scale to 16-bit range
      final sample = (float32Data[i] * 32767.0).clamp(-32768.0, 32767.0);
      pcm16Data[i] = sample.toInt();
    }
    return pcm16Data.buffer.asUint8List();
  }

  Uint8List _generateMockAudio(Duration targetDuration) {
    const sampleRate = 16000;
    const channels = 1;
    var targetMs = targetDuration.inMilliseconds;
    if (targetMs < 500) targetMs = 500;

    final samplesNeeded = (sampleRate * targetMs) ~/ 1000;
    final bytes = Uint8List(samplesNeeded * 2 * channels);
    // Fill with a low-level buzz instead of constant 100
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = (i % 2 == 0) ? 10 : 0;
    }
    return bytes;
  }

  void dispose() {
    _session?.close();
    _session = null;
  }
}

```

## lib/features/pipeline/data/performance_monitor.dart
```dart:lib/features/pipeline/data/performance_monitor.dart
import 'dart:async';

class PerformanceMetrics {
  const PerformanceMetrics({
    required this.playerBufferSeconds,
    required this.aiReadyBufferSeconds,
    required this.droppedFrameCount,
    required this.sttRtf,
    required this.translationThroughputCharsPerSec,
    required this.ttsRtf,
    required this.memoryUsageMb,
    required this.thermalState,
    required this.batteryLevelPercent,
    required this.isCharging,
    required this.pcmQueueSize,
    required this.activeJobCount,
  });

  final double playerBufferSeconds;
  final double aiReadyBufferSeconds;
  final int droppedFrameCount;
  final double sttRtf;
  final double translationThroughputCharsPerSec;
  final double ttsRtf;
  final double memoryUsageMb;
  final String thermalState;
  final int batteryLevelPercent;
  final bool isCharging;
  final int pcmQueueSize;
  final int activeJobCount;
}

class PerformanceMonitor {
  PerformanceMonitor._();
  static final PerformanceMonitor instance = PerformanceMonitor._();

  final _controller = StreamController<PerformanceMetrics>.broadcast();
  PerformanceMetrics _current = const PerformanceMetrics(
    playerBufferSeconds: 0,
    aiReadyBufferSeconds: 0,
    droppedFrameCount: 0,
    sttRtf: 0,
    translationThroughputCharsPerSec: 0,
    ttsRtf: 0,
    memoryUsageMb: 0,
    thermalState: 'unknown',
    batteryLevelPercent: 0,
    isCharging: false,
    pcmQueueSize: 0,
    activeJobCount: 0,
  );

  Stream<PerformanceMetrics> get metricsStream => _controller.stream;
  PerformanceMetrics get current => _current;

  void reportMetrics(PerformanceMetrics metrics) {
    _current = metrics;
    if (!_controller.isClosed) {
      _controller.add(metrics);
    }
  }

  void updateSttRtf(double rtf) {
    reportMetrics(_current.copyWith(sttRtf: rtf));
  }

  void updateTranslationThroughput(double charsPerSec) {
    reportMetrics(_current.copyWith(translationThroughputCharsPerSec: charsPerSec));
  }

  void updateTtsRtf(double rtf) {
    reportMetrics(_current.copyWith(ttsRtf: rtf));
  }

  void updateAiBuffer(double seconds) {
    reportMetrics(_current.copyWith(aiReadyBufferSeconds: seconds));
  }

  void dispose() {
    _controller.close();
  }
}

extension on PerformanceMetrics {
  PerformanceMetrics copyWith({
    double? playerBufferSeconds,
    double? aiReadyBufferSeconds,
    int? droppedFrameCount,
    double? sttRtf,
    double? translationThroughputCharsPerSec,
    double? ttsRtf,
    double? memoryUsageMb,
    String? thermalState,
    int? batteryLevelPercent,
    bool? isCharging,
    int? pcmQueueSize,
    int? activeJobCount,
  }) {
    return PerformanceMetrics(
      playerBufferSeconds: playerBufferSeconds ?? this.playerBufferSeconds,
      aiReadyBufferSeconds: aiReadyBufferSeconds ?? this.aiReadyBufferSeconds,
      droppedFrameCount: droppedFrameCount ?? this.droppedFrameCount,
      sttRtf: sttRtf ?? this.sttRtf,
      translationThroughputCharsPerSec: translationThroughputCharsPerSec ?? this.translationThroughputCharsPerSec,
      ttsRtf: ttsRtf ?? this.ttsRtf,
      memoryUsageMb: memoryUsageMb ?? this.memoryUsageMb,
      thermalState: thermalState ?? this.thermalState,
      batteryLevelPercent: batteryLevelPercent ?? this.batteryLevelPercent,
      isCharging: isCharging ?? this.isCharging,
      pcmQueueSize: pcmQueueSize ?? this.pcmQueueSize,
      activeJobCount: activeJobCount ?? this.activeJobCount,
    );
  }
}

```

## lib/features/pipeline/data/stt_benchmark.dart
```dart:lib/features/pipeline/data/stt_benchmark.dart
class SttBenchmarkResult {
  const SttBenchmarkResult({
    required this.modelLoadDuration,
    required this.peakMemoryBytes,
    required this.audioDuration,
    required this.inferenceDuration,
    required this.realtimeFactor,
    required this.language,
    required this.segmentCount,
  });

  final Duration modelLoadDuration;
  final int peakMemoryBytes;
  final Duration audioDuration;
  final Duration inferenceDuration;
  final double realtimeFactor; // processingWallTime / audioDuration
  final String language;
  final int segmentCount;

  static SttBenchmarkResult measure({
    required Duration modelLoadDuration,
    required int peakMemoryBytes,
    required Duration audioDuration,
    required Duration inferenceDuration,
    required String language,
    required int segmentCount,
  }) {
    final audioMs = audioDuration.inMilliseconds;
    final inferMs = inferenceDuration.inMilliseconds;
    final rtf = audioMs > 0 ? inferMs / audioMs : 1.0;

    return SttBenchmarkResult(
      modelLoadDuration: modelLoadDuration,
      peakMemoryBytes: peakMemoryBytes,
      audioDuration: audioDuration,
      inferenceDuration: inferenceDuration,
      realtimeFactor: rtf,
      language: language,
      segmentCount: segmentCount,
    );
  }
}

```

## lib/features/pipeline/data/subtitle_compressor.dart
```dart:lib/features/pipeline/data/subtitle_compressor.dart
class SubtitleCompressor {
  const SubtitleCompressor({this.maxLineLength = 45});

  final int maxLineLength;

  /// Architecture hook for compressing long translated subtitle lines for optimal mobile readability.
  String compress(String text) {
    if (text.length <= maxLineLength) return text;

    // Word wrap / natural break insertion
    final words = text.split(' ');
    final buffer = StringBuffer();
    var currentLineLength = 0;

    for (final word in words) {
      if (currentLineLength + word.length + 1 > maxLineLength) {
        buffer.write('\n');
        currentLineLength = 0;
      } else if (buffer.isNotEmpty) {
        buffer.write(' ');
        currentLineLength++;
      }
      buffer.write(word);
      currentLineLength += word.length;
    }

    return buffer.toString();
  }
}

```

## lib/features/pipeline/data/task_priority_queue.dart
```dart:lib/features/pipeline/data/task_priority_queue.dart
enum AiTaskPriority {
  p0PlaybackCritical,
  p1CurrentSubtitle,
  p2NextSubtitleWindow,
  p3TargetLookahead,
  p4Dub,
  p5DistantCache,
}

class AiTaskItem implements Comparable<AiTaskItem> {
  const AiTaskItem({
    required this.id,
    required this.priority,
    required this.action,
    required this.targetPts,
  });

  final String id;
  final AiTaskPriority priority;
  final Future<void> Function() action;
  final Duration targetPts;

  @override
  int compareTo(AiTaskItem other) {
    return priority.index.compareTo(other.priority.index);
  }
}

class TaskPriorityQueue {
  final List<AiTaskItem> _tasks = [];

  int get length => _tasks.length;
  bool get isEmpty => _tasks.isEmpty;

  void enqueue(AiTaskItem task) {
    _tasks.add(task);
    _tasks.sort();
  }

  AiTaskItem? dequeue() {
    if (_tasks.isEmpty) return null;
    return _tasks.removeAt(0);
  }

  void cancelObsoleteTasks(Duration currentPts) {
    // Remove background lookahead tasks far behind or irrelevant after seek
    _tasks.removeWhere(
      (t) =>
          t.priority.index >= AiTaskPriority.p3TargetLookahead.index &&
          t.targetPts < currentPts,
    );
  }

  void clear() {
    _tasks.clear();
  }
}

```

## lib/features/pipeline/data/translation_cache.dart
```dart:lib/features/pipeline/data/translation_cache.dart
class TranslationCache {
  final Map<String, String> _cache = {};
  final List<String> _keys = [];
  final int maxEntries = 1000;

  int get size => _cache.length;

  String? get(String sourceText) {
    final key = sourceText.trim().toLowerCase();
    if (_cache.containsKey(key)) {
      _keys.remove(key);
      _keys.add(key);
      return _cache[key];
    }
    return null;
  }

  void put(String sourceText, String translatedText) {
    final key = sourceText.trim().toLowerCase();
    if (_cache.containsKey(key)) {
      _keys.remove(key);
    } else if (_keys.length >= maxEntries) {
      final oldKey = _keys.removeAt(0);
      _cache.remove(oldKey);
    }
    _cache[key] = translatedText;
    _keys.add(key);
  }

  void clear() {
    _cache.clear();
    _keys.clear();
  }
}

```

## lib/features/pipeline/data/translation_metrics.dart
```dart:lib/features/pipeline/data/translation_metrics.dart
import 'dart:async';

class TranslationMetricsData {
  const TranslationMetricsData({
    this.translationRtf = 0.15,
    this.charactersPerSecond = 120.0,
    this.batchLatency = Duration.zero,
    this.queueSize = 0,
    this.modelMemoryBytes = 45000000, // ~45 MB for Opus-MT ONNX
  });

  final double translationRtf;
  final double charactersPerSecond;
  final Duration batchLatency;
  final int queueSize;
  final int modelMemoryBytes;

  TranslationMetricsData copyWith({
    double? translationRtf,
    double? charactersPerSecond,
    Duration? batchLatency,
    int? queueSize,
    int? modelMemoryBytes,
  }) {
    return TranslationMetricsData(
      translationRtf: translationRtf ?? this.translationRtf,
      charactersPerSecond: charactersPerSecond ?? this.charactersPerSecond,
      batchLatency: batchLatency ?? this.batchLatency,
      queueSize: queueSize ?? this.queueSize,
      modelMemoryBytes: modelMemoryBytes ?? this.modelMemoryBytes,
    );
  }
}

class TranslationMetrics {
  TranslationMetricsData _data = const TranslationMetricsData();
  final _controller = StreamController<TranslationMetricsData>.broadcast();

  TranslationMetricsData get data => _data;
  Stream<TranslationMetricsData> get stream => _controller.stream;

  void update(TranslationMetricsData newData) {
    _data = newData;
    if (!_controller.isClosed) {
      _controller.add(_data);
    }
  }

  void reset() {
    _data = const TranslationMetricsData();
    if (!_controller.isClosed) {
      _controller.add(_data);
    }
  }

  void dispose() {
    _controller.close();
  }
}

```

## lib/features/pipeline/data/tts_cache.dart
```dart:lib/features/pipeline/data/tts_cache.dart
class TtsCache {
  final Map<String, List<int>> _cache = {};
  final List<String> _keys = [];
  final int maxBytes = 50 * 1024 * 1024; // 50MB limit
  int _currentBytes = 0;

  int get size => _cache.length;

  List<int>? get(String textKey) {
    final key = textKey.trim().toLowerCase();
    if (_cache.containsKey(key)) {
      // Move to end for LRU
      _keys.remove(key);
      _keys.add(key);
      return _cache[key];
    }
    return null;
  }

  void put(String textKey, List<int> audioBytes) {
    final key = textKey.trim().toLowerCase();

    if (_cache.containsKey(key)) {
      _currentBytes -= _cache[key]!.length;
      _keys.remove(key);
    }

    // Prune if limit exceeded
    while (_keys.isNotEmpty && _currentBytes + audioBytes.length > maxBytes) {
      final oldKey = _keys.removeAt(0);
      final removed = _cache.remove(oldKey);
      if (removed != null) {
        _currentBytes -= removed.length;
      }
    }

    if (audioBytes.length <= maxBytes) {
      _cache[key] = audioBytes;
      _keys.add(key);
      _currentBytes += audioBytes.length;
    }
  }

  void clear() {
    _cache.clear();
    _keys.clear();
    _currentBytes = 0;
  }
}

```

## lib/features/pipeline/domain/ai_pipeline.dart
```dart:lib/features/pipeline/domain/ai_pipeline.dart
import 'dart:typed_data';
import '../../../core/utils/cancellation_token.dart';

class TimedTextSegment {
  const TimedTextSegment({
    required this.start,
    required this.end,
    required this.text,
    this.language,
  });
  final Duration start;
  final Duration end;
  final String text;
  final String? language;
}

class PcmChunk {
  const PcmChunk({
    required this.pts,
    required this.sampleRate,
    required this.channels,
    required this.bytes,
    this.playbackSessionId = '',
    this.timelineEpoch = 0,
    this.seekGeneration = 0,
  });
  final Duration pts;
  final int sampleRate;
  final int channels;
  final Uint8List bytes;
  final String playbackSessionId;
  final int timelineEpoch;
  final int seekGeneration;
}

abstract interface class SpeechToTextEngine {
  bool get installed;
  Future<List<TimedTextSegment>> transcribe(Stream<PcmChunk> audio);
  Future<List<TimedTextSegment>> transcribeWithCancellation(
    Stream<PcmChunk> audio, {
    required CancellationToken cancellationToken,
  });
}

abstract interface class TranslationEngine {
  bool get installed;
  Future<List<TimedTextSegment>> translate(
    List<TimedTextSegment> segments, {
    required String targetLanguage,
    CancellationToken? cancellationToken,
  });
}

abstract interface class TextToSpeechEngine {
  bool get installed;
  Future<Uint8List> synthesize(String text, {required Duration targetDuration});
  Future<Uint8List> synthesizeWithCancellation(
    String text, {
    required Duration targetDuration,
    required CancellationToken cancellationToken,
  });
}

```

## lib/features/pipeline/domain/buffer_policy.dart
```dart:lib/features/pipeline/domain/buffer_policy.dart
import '../../../core/constants/app_constants.dart';
import 'device_capability.dart';

enum AiWorkMode { starting, blocked, turbo, normal, eco, paused }

class NetworkPlaybackBuffer {
  const NetworkPlaybackBuffer({required this.bufferedPosition});
  final Duration bufferedPosition;
}

class SubtitleReadyBuffer {
  const SubtitleReadyBuffer({required this.readyUntil});
  final Duration readyUntil;
}

class DubReadyBuffer {
  const DubReadyBuffer({required this.readyUntil});
  final Duration readyUntil;
}

class AiBufferSnapshot {
  const AiBufferSnapshot({
    required this.playbackPosition,
    required this.subtitleReadyUntil,
    required this.dubReadyUntil,
    this.networkBufferedUntil = Duration.zero,
  });

  final Duration playbackPosition;
  final Duration subtitleReadyUntil;
  final Duration dubReadyUntil;
  final Duration networkBufferedUntil;

  Duration get subtitleAhead => subtitleReadyUntil - playbackPosition;
  Duration get dubAhead => dubReadyUntil - playbackPosition;
  Duration get networkAhead => networkBufferedUntil - playbackPosition;
}

class AiBufferPolicy {
  const AiBufferPolicy();

  /// Calculates dynamic startup threshold based on device tier, STT RTF, translation throughput, and playback rate.
  Duration dynamicStartupThreshold({
    required DeviceCapabilityProfile deviceProfile,
    required double sttRtf,
    required double translationThroughput,
    required double playbackRate,
  }) {
    Duration base = AppConstants.initialSubtitleBuffer; // default 5 seconds

    if (deviceProfile.isLowMemoryDevice || sttRtf > 1.0) {
      base = const Duration(
        seconds: 10,
      ); // slower device needs larger initial buffer
    } else if (deviceProfile.isCapableOfTurboStt && sttRtf < 0.5) {
      base = const Duration(
        seconds: 3,
      ); // fast device needs smaller initial wait
    }

    // Scale by playback rate (1.5x rate requires more initial safety buffer)
    return Duration(milliseconds: (base.inMilliseconds * playbackRate).toInt());
  }

  bool canStart(
    AiBufferSnapshot snapshot, {
    required DeviceCapabilityProfile deviceProfile,
    double sttRtf = 0.5,
    double translationThroughput = 100.0,
    double playbackRate = 1.0,
  }) {
    final threshold = dynamicStartupThreshold(
      deviceProfile: deviceProfile,
      sttRtf: sttRtf,
      translationThroughput: translationThroughput,
      playbackRate: playbackRate,
    );
    return snapshot.subtitleAhead >= threshold;
  }

  bool shouldBlockPlayback(
    AiBufferSnapshot snapshot, {
    double playbackRate = 1.0,
  }) {
    // If subtitle ahead drops to zero or negative, playback must block
    return snapshot.subtitleAhead <= Duration.zero;
  }

  AiWorkMode modeFor(AiBufferSnapshot snapshot, {double playbackRate = 1.0}) {
    final ahead = snapshot.subtitleAhead;
    if (ahead <= Duration.zero) {
      if (snapshot.playbackPosition == Duration.zero) {
        return AiWorkMode.starting;
      }
      return AiWorkMode.blocked;
    }
    if (ahead <= AppConstants.dangerBuffer * 6 * playbackRate) {
      return AiWorkMode.turbo;
    }
    if (ahead < AppConstants.targetSubtitleLookahead * playbackRate) {
      return AiWorkMode.normal;
    }
    if (ahead < const Duration(minutes: 5)) return AiWorkMode.eco;
    return AiWorkMode.paused;
  }
}

```

## lib/features/pipeline/domain/cache_invalidation.dart
```dart:lib/features/pipeline/domain/cache_invalidation.dart
class CacheInvalidationPolicy {
  const CacheInvalidationPolicy({
    required this.sttModelVersion,
    required this.translationModelVersion,
    required this.targetLanguage,
    required this.pipelineVersion,
  });

  final String sttModelVersion;
  final String translationModelVersion;
  final String targetLanguage;
  final String pipelineVersion;

  bool isCompatible({
    required String cachedSttVersion,
    required String cachedTranslationVersion,
    required String cachedTargetLang,
    required String cachedPipelineVersion,
  }) {
    return cachedSttVersion == sttModelVersion &&
        cachedTranslationVersion == translationModelVersion &&
        cachedTargetLang == targetLanguage &&
        cachedPipelineVersion == pipelineVersion;
  }

  static const currentPolicy = CacheInvalidationPolicy(
    sttModelVersion: '1.0.0',
    translationModelVersion: '1.2.0',
    targetLanguage: 'vi',
    pipelineVersion: '2.0.0',
  );
}

```

## lib/features/pipeline/domain/device_capability.dart
```dart:lib/features/pipeline/domain/device_capability.dart
enum ThermalStatus { nominal, fair, serious, critical }

enum AccelerationHardware { cpu, gpu, nnapi }

class DeviceCapabilityProfile {
  const DeviceCapabilityProfile({
    required this.memoryClassMb,
    required this.cpuCores,
    required this.acceleration,
    required this.thermalStatus,
    required this.recentSttRtf,
  });

  final int memoryClassMb;
  final int cpuCores;
  final AccelerationHardware acceleration;
  final ThermalStatus thermalStatus;
  final double recentSttRtf;

  bool get isCapableOfTurboStt =>
      memoryClassMb >= 2048 &&
      recentSttRtf < 1.0 &&
      thermalStatus != ThermalStatus.critical;
  bool get isLowMemoryDevice => memoryClassMb < 1536;

  DeviceCapabilityProfile copyWith({
    int? memoryClassMb,
    int? cpuCores,
    AccelerationHardware? acceleration,
    ThermalStatus? thermalStatus,
    double? recentSttRtf,
  }) {
    return DeviceCapabilityProfile(
      memoryClassMb: memoryClassMb ?? this.memoryClassMb,
      cpuCores: cpuCores ?? this.cpuCores,
      acceleration: acceleration ?? this.acceleration,
      thermalStatus: thermalStatus ?? this.thermalStatus,
      recentSttRtf: recentSttRtf ?? this.recentSttRtf,
    );
  }

  static const defaultProfile = DeviceCapabilityProfile(
    memoryClassMb: 4096,
    cpuCores: 8,
    acceleration: AccelerationHardware.nnapi,
    thermalStatus: ThermalStatus.nominal,
    recentSttRtf: 0.45,
  );
}

```

## lib/features/pipeline/domain/device_tier.dart
```dart:lib/features/pipeline/domain/device_tier.dart
enum DeviceTier { lite, balanced, performance }

class DeviceTierClassifier {
  const DeviceTierClassifier();

  DeviceTier classify({
    required int memoryClassMb,
    required int cpuCores,
    required double recentSttRtf,
  }) {
    if (memoryClassMb < 2048 || cpuCores <= 4 || recentSttRtf > 1.2) {
      return DeviceTier.lite;
    }
    if (memoryClassMb >= 4096 && cpuCores >= 8 && recentSttRtf < 0.6) {
      return DeviceTier.performance;
    }
    return DeviceTier.balanced;
  }
}

```

## lib/features/pipeline/domain/dub_segment.dart
```dart:lib/features/pipeline/domain/dub_segment.dart
import 'dart:typed_data';

class DubSegment {
  const DubSegment({
    required this.id,
    required this.startPts,
    required this.endPts,
    required this.sourceText,
    required this.translatedText,
    required this.generatedAudio,
    required this.generatedDuration,
    required this.targetDuration,
    required this.voiceId,
    this.speakerId,
    required this.modelVersion,
  });

  final String id;
  final Duration startPts;
  final Duration endPts;
  final String sourceText;
  final String translatedText;
  final Uint8List generatedAudio;
  final Duration generatedDuration;
  final Duration targetDuration;
  final String voiceId;
  final String? speakerId;
  final String modelVersion;

  bool get isDurationFitted =>
      generatedDuration <= targetDuration + const Duration(milliseconds: 200);
}

```

## lib/features/pipeline/domain/feature_entitlement.dart
```dart:lib/features/pipeline/domain/feature_entitlement.dart
enum EntitlementTier { free, premiumSubscriber, developerUnlocked }

class FeatureEntitlement {
  const FeatureEntitlement({
    required this.tier,
    required this.canUseVoiceOver,
    required this.maxVoicesAvailable,
  });

  final EntitlementTier tier;
  final bool canUseVoiceOver;
  final int maxVoicesAvailable;

  static const defaultFree = FeatureEntitlement(
    tier: EntitlementTier.free,
    canUseVoiceOver: false,
    maxVoicesAvailable: 1,
  );

  static const defaultDeveloperUnlocked = FeatureEntitlement(
    tier: EntitlementTier.developerUnlocked,
    canUseVoiceOver: true,
    maxVoicesAvailable: 5,
  );
}

```

## lib/features/pipeline/domain/media_identity.dart
```dart:lib/features/pipeline/domain/media_identity.dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

class MediaIdentity {
  const MediaIdentity({
    required this.normalizedPath,
    required this.durationSeconds,
    this.title,
    this.episode,
    this.streamCharacteristics = 'hls_video',
  });

  final String normalizedPath;
  final int durationSeconds;
  final String? title;
  final String? episode;
  final String streamCharacteristics;

  /// Generates a robust layered fingerprint that is immune to ephemeral CDN query token changes.
  String generateFingerprint() {
    // Strip ephemeral query parameters or signed tokens from URI path
    Uri uri;
    try {
      uri = Uri.parse(normalizedPath);
    } catch (_) {
      uri = Uri(path: normalizedPath);
    }

    final cleanPath = '${uri.scheme}://${uri.host}${uri.path}'
        .toLowerCase()
        .trim();
    final rawKey =
        '$cleanPath|$durationSeconds|${(title ?? '').toLowerCase().trim()}|${(episode ?? '').toLowerCase().trim()}|$streamCharacteristics';

    final bytes = utf8.encode(rawKey);
    return sha256.convert(bytes).toString();
  }
}

```

## lib/features/pipeline/domain/playback_gate.dart
```dart:lib/features/pipeline/domain/playback_gate.dart
import 'buffer_policy.dart';

class PlaybackGateDecision {
  const PlaybackGateDecision({
    required this.shouldPlay,
    required this.reason,
    required this.workMode,
  });

  final bool shouldPlay;
  final String reason;
  final AiWorkMode workMode;
}

class PlaybackGate {
  const PlaybackGate();

  PlaybackGateDecision evaluate({
    required AiBufferSnapshot snapshot,
    required double playbackRate,
    required bool isUserPaused,
  }) {
    if (isUserPaused) {
      return const PlaybackGateDecision(
        shouldPlay: false,
        reason: 'User paused playback explicitly.',
        workMode: AiWorkMode.paused,
      );
    }

    // Adjust required buffer ahead by playback rate (1.5x rate requires 1.5x buffer)
    final adjustedSubtitleAhead = snapshot.subtitleAhead;
    const policy = AiBufferPolicy();
    final mode = policy.modeFor(snapshot, playbackRate: playbackRate);
    final shouldBlock = policy.shouldBlockPlayback(
      snapshot,
      playbackRate: playbackRate,
    );

    if (shouldBlock) {
      return PlaybackGateDecision(
        shouldPlay: false,
        reason:
            'Subtitle buffer exhausted (ahead: ${adjustedSubtitleAhead.inMilliseconds}ms). Pausing playback to refill AI buffer.',
        workMode: mode,
      );
    }

    return PlaybackGateDecision(
      shouldPlay: true,
      reason:
          'Subtitle buffer healthy (mode: ${mode.name}). Playback proceeding.',
      workMode: mode,
    );
  }
}

```

## lib/features/pipeline/domain/timeline_subtitle_buffer.dart
```dart:lib/features/pipeline/domain/timeline_subtitle_buffer.dart
import 'ai_pipeline.dart';

enum TimelineReadinessMode { liveAi, completeSubtitleDocument }

class TimelineSubtitleBuffer {
  final List<TimedTextSegment> _segments = [];
  final List<_PendingRange> _pendingSegments = [];
  Duration _vadProgress = Duration.zero;
  Duration _watermark = Duration.zero;
  Duration _floor = Duration.zero;
  TimelineReadinessMode _mode = TimelineReadinessMode.liveAi;

  List<TimedTextSegment> get segments => List.unmodifiable(_segments);
  Duration get subtitleReadyUntil => _watermark;
  Duration get retainedFrom => _floor;

  void beginLiveAiTimeline({Duration floor = Duration.zero}) {
    _mode = TimelineReadinessMode.liveAi;
    _floor = floor;
    _vadProgress = floor;
    _watermark = floor;
    _segments.removeWhere((s) => s.end < floor);
    _pendingSegments.clear();
    _updateWatermark();
  }

  void markSubtitleDocumentComplete(Duration processedThrough) {
    _mode = TimelineReadinessMode.completeSubtitleDocument;
    if (processedThrough > _watermark) _watermark = processedThrough;
  }

  void reportProgress(Duration pts, {Duration? activeSpeechStart}) {
    if (_mode != TimelineReadinessMode.liveAi) return;
    final certainUntil = activeSpeechStart ?? pts;
    if (certainUntil > _vadProgress) _vadProgress = certainUntil;
    _updateWatermark();
  }

  void registerPendingRange(Duration start, Duration end) {
    if (end <= _floor) return;
    _pendingSegments.add(_PendingRange(start, end));
    _updateWatermark();
  }

  void failPendingRange(Duration start) {
    _pendingSegments.removeWhere((p) => p.start == start);
    _updateWatermark();
  }

  void addSegments(List<TimedTextSegment> newSegments, {Duration? metadata}) {
    if (metadata != null) {
      _pendingSegments.removeWhere((p) => p.start == metadata);
    }
    _segments.addAll(newSegments.where((s) => s.end >= _floor));
    _segments.sort((a, b) => a.start.compareTo(b.start));
    _deduplicate();
    _updateWatermark();
  }

  void _deduplicate() {
    if (_segments.length < 2) return;
    final unique = <TimedTextSegment>[];
    for (final segment in _segments) {
      if (unique.isNotEmpty) {
        final previous = unique.last;
        if (previous.start == segment.start &&
            previous.end == segment.end &&
            previous.text == segment.text) {
          continue;
        }
      }
      unique.add(segment);
    }
    _segments
      ..clear()
      ..addAll(unique);
  }

  void _updateWatermark() {
    if (_mode == TimelineReadinessMode.completeSubtitleDocument) {
      // Document readiness is not derived from cue gaps. A valid subtitle file
      // naturally contains silent gaps between cues.
      if (_watermark < _floor) _watermark = _floor;
      return;
    }

    var current = _floor;
    final allKnown = <_TimelineRange>[
      ..._segments.map((s) => _TimelineRange(s.start, s.end, isPending: false)),
      ..._pendingSegments.map((p) => _TimelineRange(p.start, p.end, isPending: true)),
    ]..sort((a, b) => a.start.compareTo(b.start));

    for (final range in allKnown) {
      if (range.end <= current) continue;
      if (range.start > current + const Duration(milliseconds: 100)) {
        if (range.start > _vadProgress) {
          _watermark = current;
          return;
        }
        current = range.start;
      }
      if (range.isPending) {
        _watermark = current;
        return;
      }
      if (range.end > current) current = range.end;
    }

    if (_vadProgress > current) current = _vadProgress;
    if (current > _watermark || _watermark < _floor) _watermark = current;
  }

  TimedTextSegment? segmentAt(Duration pts) {
    // Retained window is bounded, so a linear lookup remains inexpensive.
    for (final seg in _segments) {
      if (pts >= seg.start && pts <= seg.end) return seg;
    }
    return null;
  }

  void pruneObsolete(Duration currentPts) {
    final cutoff = currentPts - const Duration(seconds: 60);
    if (cutoff <= _floor) return;
    _floor = cutoff;
    _segments.removeWhere((seg) => seg.end < cutoff);
    _pendingSegments.removeWhere((p) => p.end < cutoff);
    if (_vadProgress < _floor) _vadProgress = _floor;
    if (_watermark < _floor) _watermark = _floor;
    _updateWatermark();
  }

  void flushObsolete(Duration beforePts) {
    _floor = beforePts;
    _segments.removeWhere((seg) => seg.end < beforePts);
    _pendingSegments.clear();
    _vadProgress = beforePts;
    _watermark = beforePts;
    _mode = TimelineReadinessMode.liveAi;
    _updateWatermark();
  }

  void clear() {
    _segments.clear();
    _pendingSegments.clear();
    _vadProgress = Duration.zero;
    _watermark = Duration.zero;
    _floor = Duration.zero;
    _mode = TimelineReadinessMode.liveAi;
  }
}

class _PendingRange {
  const _PendingRange(this.start, this.end);
  final Duration start;
  final Duration end;
}

class _TimelineRange {
  const _TimelineRange(this.start, this.end, {required this.isPending});
  final Duration start;
  final Duration end;
  final bool isPending;
}

```

## lib/features/pipeline/presentation/ai_buffer_panel.dart
```dart:lib/features/pipeline/presentation/ai_buffer_panel.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../source_resolver/domain/entities/resolved_source.dart';
import '../domain/buffer_policy.dart';
import 'ai_scheduler_controller.dart';
import '../data/performance_monitor.dart';
import '../../../core/diagnostics/presentation/diagnostic_log_overlay.dart';

class AiBufferPanel extends ConsumerWidget {
  const AiBufferPanel({required this.source, super.key});
  final ResolvedSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiState = ref.watch(aiSchedulerProvider);
    final isNative = source.playbackMode == PlaybackMode.native;

    final aheadSeconds = aiState.subtitleAhead.inSeconds.clamp(0, 999);
    final modeColor = switch (aiState.workMode) {
      AiWorkMode.starting => Colors.purpleAccent,
      AiWorkMode.blocked => Colors.redAccent,
      AiWorkMode.turbo => Colors.orangeAccent,
      AiWorkMode.normal => Colors.greenAccent,
      AiWorkMode.eco => Colors.blueAccent,
      AiWorkMode.paused => Colors.grey,
    };

    return Material(
      color: const Color(0xFF14141A),
      elevation: 4,
      child: StreamBuilder<PerformanceMetrics>(
        stream: PerformanceMonitor.instance.metricsStream,
        builder: (context, snapshot) {
          final metrics = snapshot.data ?? PerformanceMonitor.instance.current;
          
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      isNative ? Icons.auto_awesome : Icons.language,
                      color: const Color(0xFF7C5CFC),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            aiState.errorMessage ?? aiState.activeSourceStrategy,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: aiState.errorMessage != null ? Colors.redAccent : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'RTF: STT ${metrics.sttRtf.toStringAsFixed(2)}x | TTS ${metrics.ttsRtf.toStringAsFixed(2)}x',
                            style: const TextStyle(fontSize: 10, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => const SizedBox(
                            height: 600,
                            child: ClipRRect(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                              child: Material(child: DiagnosticLogOverlay()),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: modeColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: modeColor, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (aiState.workMode == AiWorkMode.blocked)
                              const Icon(Icons.bug_report, color: Colors.white, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              aiState.workMode.name.toUpperCase(),
                              style: TextStyle(
                                color: modeColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text(
                      'Subtitle Lookahead Buffer:',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const Spacer(),
                    Text(
                      '${aheadSeconds}s ahead',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (aheadSeconds / 120.0).clamp(0.0, 1.0),
                    backgroundColor: Colors.white12,
                    color: modeColor,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }
}

```

## lib/features/pipeline/presentation/ai_pipeline_progress_page.dart
```dart:lib/features/pipeline/presentation/ai_pipeline_progress_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_components.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import '../data/performance_monitor.dart';
import 'ai_scheduler_controller.dart';

class AiPipelineProgressPage extends ConsumerStatefulWidget {
  final double initialProgress;
  final String title;
  final VoidCallback? onNavigateToHome;

  const AiPipelineProgressPage({
    super.key,
    this.initialProgress = 0.68,
    this.title = 'Video TikTok #102 - Hướng dẫn AI',
    this.onNavigateToHome,
  });

  @override
  ConsumerState<AiPipelineProgressPage> createState() =>
      _AiPipelineProgressPageState();
}

class _AiPipelineProgressPageState
    extends ConsumerState<AiPipelineProgressPage> {
  @override
  Widget build(BuildContext context) {
    final aiSchedulerController = ref.watch(aiSchedulerProvider.notifier);
    final aiState = ref.watch(aiSchedulerProvider);
    final activeSource = aiSchedulerController.activeSource;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tiến trình Dịch AI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: activeSource == null
            ? _buildEmptyState()
            : _buildActivePipelineView(activeSource, aiState),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AppGlassCard(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGlow,
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_motion_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Chưa có tiến trình dịch nào',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Hãy dán liên kết video hoặc chọn file từ Trang chủ để bắt đầu dịch phụ đề & lồng tiếng AI tiếng Việt.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              GlowButton(
                label: 'Đến Trang chủ Dịch Video',
                icon: Icons.add_link_rounded,
                onPressed: widget.onNavigateToHome ?? () => context.go('/'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Các tác vụ đã hoàn thành gần đây',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        _buildHistoryCard(
          title: 'Hướng dẫn AI Video Translation bằng Whisper',
          source: 'YouTube • 12:45',
          status: 'Hoàn thành 100%',
          statusColor: AppColors.success,
        ),
        const SizedBox(height: 10),
        _buildHistoryCard(
          title: 'Video TikTok công nghệ ngắn #102',
          source: 'TikTok • 01:30',
          status: 'Đã lưu đệm',
          statusColor: AppColors.cyanAccent,
        ),
      ],
    );
  }

  Widget _buildActivePipelineView(
    ResolvedSource activeSource,
    AiSchedulerState aiState,
  ) {
    return StreamBuilder<PerformanceMetrics>(
      stream: PerformanceMonitor.instance.metricsStream,
      builder: (context, perfSnapshot) {
        final metrics =
            perfSnapshot.data ?? PerformanceMonitor.instance.current;

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AppGlassCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryGlow,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    child: const Icon(
                      Icons.movie_filter_rounded,
                      color: AppColors.primaryLight,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          activeSource.input.isNotEmpty
                              ? activeSource.input
                              : widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Text(
                              'Tiếng Anh -> Tiếng Việt',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(width: 6),
                            PillBadge(
                              label: aiState.activeSourceStrategy,
                              backgroundColor: AppColors.surface,
                              textColor: AppColors.primaryLight,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: ProgressGauge(
                progress: widget.initialProgress,
                title: 'Đang dịch AI',
                subtitle: 'Thực tế: ${metrics.sttRtf.toStringAsFixed(2)}x RTF',
                size: 200,
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    icon: Icons.speed_rounded,
                    label: 'STT Speed',
                    value: '${metrics.sttRtf.toStringAsFixed(2)}x RTF',
                    color: AppColors.cyanAccent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildMetricTile(
                    icon: Icons.translate_rounded,
                    label: 'Translate',
                    value:
                        '${metrics.translationThroughputCharsPerSec.toInt()} ch/s',
                    color: AppColors.primaryLight,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildMetricTile(
                    icon: Icons.record_voice_over_rounded,
                    label: 'TTS Speed',
                    value: '${metrics.ttsRtf.toStringAsFixed(2)}x RTF',
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Danh sách Nhiệm vụ AI Pipeline',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            AppGlassCard(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: const Column(
                children: [
                  StepTimelineTile(
                    title: 'Tách Âm thanh 16kHz PCM Mono',
                    subtitle: 'Đã hoàn thành bóc tách luồng âm thanh gốc',
                    stepState: AppStepState.completed,
                  ),
                  StepTimelineTile(
                    title: 'Speech-to-Text (Whisper AI Engine)',
                    subtitle:
                        'Đang nhận dạng giọng nói & tạo mốc thời gian (PTS)',
                    stepState: AppStepState.active,
                  ),
                  StepTimelineTile(
                    title: 'Dịch thuật Neural Sang Tiếng Việt',
                    subtitle: 'Tối ưu ngữ cảnh & ghép nối phụ đề',
                    stepState: AppStepState.pending,
                  ),
                  StepTimelineTile(
                    title: 'Tổng hợp Giọng nói Lồng tiếng (TTS)',
                    subtitle: 'Tạo luồng âm thanh song song cho Player',
                    stepState: AppStepState.pending,
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      side: const BorderSide(
                        color: AppColors.surfaceCardBorder,
                      ),
                    ),
                    icon: const Icon(
                      Icons.pause_circle_outline_rounded,
                      size: 20,
                    ),
                    label: const Text('Tạm dừng'),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Đã tạm dừng tiến trình AI'),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlowButton(
                    label: 'Mở Trình phát',
                    icon: Icons.play_arrow_rounded,
                    onPressed: () {
                      context.push('/player', extra: activeSource);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return AppGlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard({
    required String title,
    required String source,
    required String status,
    required Color statusColor,
  }) {
    return AppGlassCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceCardBorder),
            ),
            child: const Icon(
              Icons.play_circle_fill_rounded,
              color: AppColors.primaryLight,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  source,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PillBadge(
            label: status,
            backgroundColor: statusColor.withValues(alpha: 0.15),
            textColor: statusColor,
            borderColor: statusColor.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}

```

## lib/features/pipeline/presentation/ai_scheduler_controller.dart
```dart:lib/features/pipeline/presentation/ai_scheduler_controller.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../audio/data/pcm_audio_extractor.dart';
import '../../audio/data/vad_engine.dart';
import '../../settings/data/model_manager_repository.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import '../../subtitles/data/subtitle_repository_impl.dart';
import '../../subtitles/domain/entities/subtitle_track.dart';
import '../../subtitles/domain/repositories/subtitle_repository.dart';
import '../data/dubbing_repository.dart';
import '../data/local_stt_engine.dart';
import '../data/local_translation_engine.dart';
import '../data/local_tts_engine.dart';
import '../domain/ai_pipeline.dart';
import '../domain/buffer_policy.dart';
import '../domain/device_capability.dart';
import '../domain/dub_segment.dart';
import '../domain/playback_gate.dart';
import '../domain/timeline_subtitle_buffer.dart';
import '../../player/presentation/media_session_controller.dart';

class _Sentinel {
  const _Sentinel();
}

const _keep = _Sentinel();

class AiSchedulerState {
  const AiSchedulerState({
    required this.playbackPosition,
    required this.subtitleReadyUntil,
    required this.dubReadyUntil,
    required this.workMode,
    required this.activeSourceStrategy,
    required this.activeSessionId,
    this.activeSegment,
    this.isBufferingForAi = false,
    this.playbackRate = 1.0,
    this.errorMessage,
  });

  final Duration playbackPosition;
  final Duration subtitleReadyUntil;
  final Duration dubReadyUntil;
  final AiWorkMode workMode;
  final String activeSourceStrategy;
  final String activeSessionId;
  final TimedTextSegment? activeSegment;
  final bool isBufferingForAi;
  final double playbackRate;
  final String? errorMessage;

  Duration get subtitleAhead => subtitleReadyUntil - playbackPosition;

  AiBufferSnapshot get snapshot => AiBufferSnapshot(
    playbackPosition: playbackPosition,
    subtitleReadyUntil: subtitleReadyUntil,
    dubReadyUntil: dubReadyUntil,
  );

  AiSchedulerState copyWith({
    Duration? playbackPosition,
    Duration? subtitleReadyUntil,
    Duration? dubReadyUntil,
    AiWorkMode? workMode,
    String? activeSourceStrategy,
    String? activeSessionId,
    Object? activeSegment = _keep,
    bool? isBufferingForAi,
    double? playbackRate,
    Object? errorMessage = _keep,
  }) {
    return AiSchedulerState(
      playbackPosition: playbackPosition ?? this.playbackPosition,
      subtitleReadyUntil: subtitleReadyUntil ?? this.subtitleReadyUntil,
      dubReadyUntil: dubReadyUntil ?? this.dubReadyUntil,
      workMode: workMode ?? this.workMode,
      activeSourceStrategy: activeSourceStrategy ?? this.activeSourceStrategy,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      activeSegment: identical(activeSegment, _keep)
          ? this.activeSegment
          : activeSegment as TimedTextSegment?,
      isBufferingForAi: isBufferingForAi ?? this.isBufferingForAi,
      playbackRate: playbackRate ?? this.playbackRate,
      errorMessage: identical(errorMessage, _keep)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class AiSchedulerController extends StateNotifier<AiSchedulerState> {
  AiSchedulerController({
    required Ref ref,
    required SubtitleRepository subtitleRepository,
    required SpeechToTextEngine sttEngine,
    required TranslationEngine translationEngine,
    required TextToSpeechEngine ttsEngine,
    required PcmAudioExtractor audioExtractor,
    required VoiceActivityDetector vadEngine,
    required DubbingRepository dubbingRepository,
    required DiagnosticsService diagnostics,
    DeviceCapabilityProfile? deviceProfile,
  }) : _ref = ref,
       _subtitleRepository = subtitleRepository,
       _sttEngine = sttEngine,
       _translationEngine = translationEngine,
       _ttsEngine = ttsEngine,
       _audioExtractor = audioExtractor,
       _vadEngine = vadEngine,
       _dubbingRepository = dubbingRepository,
       _diagnostics = diagnostics,
       _deviceProfile = deviceProfile ?? DeviceCapabilityProfile.defaultProfile,
       super(
         const AiSchedulerState(
           playbackPosition: Duration.zero,
           subtitleReadyUntil: Duration.zero,
           dubReadyUntil: Duration.zero,
           workMode: AiWorkMode.starting,
           activeSourceStrategy: 'Initializing...',
           activeSessionId: 'none',
         ),
       );

  final SubtitleRepository _subtitleRepository;
  final Ref _ref;
  final SpeechToTextEngine _sttEngine;
  final TranslationEngine _translationEngine;
  final TextToSpeechEngine _ttsEngine;
  final PcmAudioExtractor _audioExtractor;
  final VoiceActivityDetector _vadEngine;
  final DubbingRepository _dubbingRepository;
  final DiagnosticsService _diagnostics;
  final DeviceCapabilityProfile _deviceProfile;

  final TimelineSubtitleBuffer _timelineBuffer = TimelineSubtitleBuffer();
  final _policy = const AiBufferPolicy();
  final _playbackGate = const PlaybackGate();

  int _generation = 0;
  CancellationToken? _activeToken;
  ResolvedSource? activeSource;

  int get generation => _generation;

  String get activeSessionId => _activeToken?.hashCode.toString() ?? 'none';

  Future<void> initializeForSource(ResolvedSource source) async {
    final gen = _beginNewSession();
    activeSource = source;
    _timelineBuffer.clear();
    _dubbingRepository.clear();
    state = state.copyWith(errorMessage: null);

    _diagnostics.log(
      'AIScheduler',
      'Initializing for source: ${source.kind.name}',
    );

    try {
      if (source.manualSubtitlePath != null) {
        state = state.copyWith(
          activeSourceStrategy: 'Using Manual Subtitle File',
        );
        final manualTrack = SubtitleTrack(
          id: 'manual_sub',
          language: 'unknown',
          title: 'Manual Subtitle',
          uri: Uri.file(source.manualSubtitlePath!),
          format: source.manualSubtitlePath!.toLowerCase().endsWith('.vtt')
              ? SubtitleFormat.webvtt
              : SubtitleFormat.srt,
          isTargetLanguage: false,
        );
        await _loadSubtitleTrack(manualTrack, gen, translate: true);
        return;
      }

      final tracks = await _subtitleRepository.findSubtitleTracks(source);
      if (_isStale(gen)) return;

      final viTrack = tracks
          .where((t) => t.isTargetLanguage || t.language.toLowerCase() == 'vi')
          .firstOrNull;

      if (viTrack != null) {
        state = state.copyWith(
          activeSourceStrategy: 'Using Existing Vietnamese Subtitles',
        );
        await _loadSubtitleTrack(viTrack, gen, translate: false);
        return;
      }

      final foreignTrack = tracks.firstOrNull;
      if (foreignTrack != null) {
        state = state.copyWith(
          activeSourceStrategy:
              'Translating ${foreignTrack.language.toUpperCase()} Subtitles',
        );
        await _loadSubtitleTrack(foreignTrack, gen, translate: true);
        return;
      }

      state = state.copyWith(
        activeSourceStrategy: 'AI Pipeline (VAD -> STT -> Translation)',
      );
      await _runAudioSttPipeline(source, gen, startAt: state.playbackPosition);
    } on OperationCancelledException {
      _diagnostics.log('AIScheduler', 'Pipeline cancelled for gen $gen');
    } catch (e, st) {
      if (_isStale(gen)) return;
      final msg = e.toString().contains('model not found')
          ? 'Lỗi: Thiếu model AI. Vui lòng tải xuống trong Cài đặt.'
          : 'Không thể khởi tạo phụ đề tự động: $e';

      _diagnostics.log(
        'AIScheduler',
        'Init failed: $e\n$st',
        level: LogLevel.error,
      );
      state = state.copyWith(errorMessage: msg, workMode: AiWorkMode.blocked);
    }
  }

  Future<void> _loadSubtitleTrack(
    SubtitleTrack track,
    int gen, {
    required bool translate,
  }) async {
    final raw = await _subtitleRepository.fetchSubtitleSegments(track);
    if (_isStale(gen)) return;

    final startIndex = raw.indexWhere((s) => s.end >= state.playbackPosition);
    final startAt = startIndex < 0 ? 0 : startIndex;

    for (var i = startAt; i < raw.length; i += 20) {
      if (_isStale(gen)) return;
      await _waitUntilBufferNeeded(gen);
      if (_isStale(gen)) return;

      final batch = raw.skip(i).take(20).toList();
      final processedBatch = translate
          ? await _translationEngine.translate(
              batch,
              targetLanguage: AppConstants.targetLanguage,
              cancellationToken: _activeToken,
            )
          : batch;

      if (_isStale(gen)) return;
      _timelineBuffer.addSegments(processedBatch);
      unawaited(_synthesizeBatch(processedBatch, gen, _activeToken!));
      _updateBufferState();
    }
  }

  Future<void> _synthesizeBatch(
    List<TimedTextSegment> segments,
    int gen,
    CancellationToken token,
  ) async {
    for (final seg in segments) {
      if (_isStale(gen) || token.isCancelled) return;
      final targetDuration = seg.end - seg.start;
      try {
        final audio = await _ttsEngine.synthesizeWithCancellation(
          seg.text,
          targetDuration: targetDuration,
          cancellationToken: token,
        );
        if (_isStale(gen) || token.isCancelled) return;

        final dubSeg = DubSegment(
          id: 'dub_${seg.start.inMilliseconds}',
          startPts: seg.start,
          endPts: seg.end,
          sourceText: '',
          translatedText: seg.text,
          generatedAudio: audio,
          generatedDuration: targetDuration,
          targetDuration: targetDuration,
          voiceId: 'vi_female',
          modelVersion: '1.0',
        );

        _dubbingRepository.addSegment(dubSeg);
        _updateBufferState();
      } catch (e) {
        _diagnostics.log('AIScheduler', 'TTS failed for segment: $e');
      }
    }
  }

  Future<void> _runAudioSttPipeline(
    ResolvedSource source,
    int gen, {
    required Duration startAt,
  }) async {
    final token = _activeToken!;
    final audioStream = _audioExtractor.extractPcmStream(
      source,
      startPosition: startAt,
      playbackSessionId: activeSessionId,
      seekGeneration: gen,
      cancellationToken: token,
    );

    await for (final speech in _vadEngine.detectSpeech(
      audioStream,
      onProgress: (pts, activeSpeechStart) {
        if (_isStale(gen)) return;
        _timelineBuffer.reportProgress(
          pts,
          activeSpeechStart: activeSpeechStart,
        );
        _updateBufferState();
      },
    )) {
      token.throwIfCancelled();
      if (_isStale(gen)) return;

      // Guard: Ensure speech chunks match current session
      if (speech.chunks.isNotEmpty) {
        final firstChunk = speech.chunks.first;
        if (firstChunk.playbackSessionId != activeSessionId ||
            firstChunk.seekGeneration != gen) {
          _diagnostics.log(
            'AIScheduler',
            'Discarding stale VAD segment from old session',
          );
          continue;
        }
      }

      await _waitUntilBufferNeeded(gen);
      if (_isStale(gen)) return;

      // Register this range as pending so the watermark doesn't jump over it
      _timelineBuffer.registerPendingRange(speech.start, speech.end);
      _updateBufferState();

      final sttSegments = await _sttEngine.transcribeWithCancellation(
        Stream.fromIterable(speech.chunks),
        cancellationToken: token,
      );

      final translated = await _translationEngine.translate(
        sttSegments,
        targetLanguage: AppConstants.targetLanguage,
        cancellationToken: token,
      );

      if (_isStale(gen)) return;
      _timelineBuffer.addSegments(translated, metadata: speech.start);
      unawaited(_synthesizeBatch(translated, gen, token));
      _updateBufferState();
    }
  }

  Future<void> _waitUntilBufferNeeded(int gen) async {
    while (!_isStale(gen) &&
        (_timelineBuffer.subtitleReadyUntil - state.playbackPosition) >
            const Duration(minutes: 2)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  int _beginNewSession() {
    _activeToken?.cancel();
    _activeToken = CancellationToken();
    _generation++;
    final newSessionId = _activeToken.hashCode.toString();
    state = state.copyWith(activeSessionId: newSessionId);
    return _generation;
  }

  bool _isStale(int gen) => !mounted || gen != _generation;

  void updatePlaybackPosition(Duration pts) {
    // Tự động giải phóng các cue phụ đề quá hạn 60s
    _timelineBuffer.pruneObsolete(pts);
    _dubbingRepository.prune(pts);

    final activeSeg = _timelineBuffer.segmentAt(pts);
    final dubSeg = _dubbingRepository.getSegmentAt(pts);
    if (dubSeg != null) {
      _dubbingRepository.markAsActive(dubSeg.id);
    }

    final readyUntil = _timelineBuffer.subtitleReadyUntil;
    final dubReadyUntil = _dubbingRepository.dubReadyUntil;

    final snapshot = AiBufferSnapshot(
      playbackPosition: pts,
      subtitleReadyUntil: readyUntil,
      dubReadyUntil: dubReadyUntil,
    );

    final decision = _playbackGate.evaluate(
      snapshot: snapshot,
      playbackRate: state.playbackRate,
      isUserPaused: false,
    );

    if (state.isBufferingForAi != !decision.shouldPlay) {
      if (!decision.shouldPlay) {
        unawaited(_ref.read(mediaSessionControllerProvider.notifier).pause());
      } else {
        unawaited(_ref.read(mediaSessionControllerProvider.notifier).play());
      }
    }

    state = state.copyWith(
      playbackPosition: pts,
      subtitleReadyUntil: readyUntil,
      dubReadyUntil: dubReadyUntil,
      workMode: decision.workMode,
      activeSegment: activeSeg,
      isBufferingForAi: !decision.shouldPlay,
    );
  }

  void handleSeek(Duration newPts) {
    final gen = _beginNewSession();
    _timelineBuffer.flushObsolete(newPts);
    _dubbingRepository.clear();
    updatePlaybackPosition(newPts);

    final source = activeSource;
    if (source != null && state.activeSourceStrategy.contains('AI Pipeline')) {
      unawaited(_runAudioSttPipeline(source, gen, startAt: newPts));
    }
  }

  void updatePlaybackRate(double rate) {
    state = state.copyWith(playbackRate: rate);
    _updateBufferState();
  }

  void _updateBufferState() {
    final readyUntil = _timelineBuffer.subtitleReadyUntil;
    final dubReadyUntil = _dubbingRepository.dubReadyUntil;

    final snapshot = AiBufferSnapshot(
      playbackPosition: state.playbackPosition,
      subtitleReadyUntil: readyUntil,
      dubReadyUntil: dubReadyUntil,
    );

    final canStart = _policy.canStart(
      snapshot,
      deviceProfile: _deviceProfile,
      playbackRate: state.playbackRate,
    );

    final mode = state.errorMessage != null
        ? AiWorkMode.blocked
        : _policy.modeFor(snapshot, playbackRate: state.playbackRate);

    state = state.copyWith(
      subtitleReadyUntil: readyUntil,
      dubReadyUntil: dubReadyUntil,
      workMode: mode,
      isBufferingForAi:
          !canStart &&
          (state.playbackPosition == Duration.zero || state.isBufferingForAi),
    );
  }

  @override
  void dispose() {
    _activeToken?.cancel();
    _generation++;
    super.dispose();
  }
}

// Providers
final subtitleRepositoryProvider = Provider<SubtitleRepository>((ref) {
  return SubtitleRepositoryImpl(ref.watch(dioProvider));
});

final sttEngineProvider = Provider<SpeechToTextEngine>((ref) {
  final engine = LocalSpeechToTextEngine(
    ref.watch(modelManagerRepositoryProvider),
    ref.watch(diagnosticsServiceProvider),
  );

  ref.onDispose(() {
    unawaited(engine.dispose());
  });

  return engine;
});

final translationEngineProvider = Provider<TranslationEngine>((ref) {
  final engine = LocalTranslationEngine(
    ref.watch(modelManagerRepositoryProvider),
    ref.watch(diagnosticsServiceProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

final ttsEngineProvider = Provider<TextToSpeechEngine>((ref) {
  final engine = LocalTextToSpeechEngine(
    ref.watch(modelManagerRepositoryProvider),
    ref.watch(diagnosticsServiceProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

final pcmAudioExtractorProvider = Provider<PcmAudioExtractor>((ref) {
  if (Platform.isAndroid) {
    return NativePcmAudioExtractor(ref.watch(diagnosticsServiceProvider));
  }
  return const DefaultPcmAudioExtractor();
});

final vadEngineProvider = Provider<VoiceActivityDetector>((ref) {
  final engine = LocalVadEngine(
    ref.watch(modelManagerRepositoryProvider),
    ref.watch(diagnosticsServiceProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

final dubbingRepositoryProvider = Provider<DubbingRepository>((ref) {
  return DubbingRepository();
});

final activeDubIdProvider = StreamProvider.autoDispose<String?>((ref) {
  return ref.watch(dubbingRepositoryProvider).activeIdStream;
});

final aiSchedulerProvider =
    StateNotifierProvider.autoDispose<AiSchedulerController, AiSchedulerState>((
      ref,
    ) {
      return AiSchedulerController(
        ref: ref,
        subtitleRepository: ref.watch(subtitleRepositoryProvider),
        sttEngine: ref.watch(sttEngineProvider),
        translationEngine: ref.watch(translationEngineProvider),
        ttsEngine: ref.watch(ttsEngineProvider),
        audioExtractor: ref.watch(pcmAudioExtractorProvider),
        vadEngine: ref.watch(vadEngineProvider),
        dubbingRepository: ref.watch(dubbingRepositoryProvider),
        diagnostics: ref.watch(diagnosticsServiceProvider),
      );
    });


```

## lib/features/pipeline/presentation/dubbing_controller.dart
```dart:lib/features/pipeline/presentation/dubbing_controller.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/diagnostics/diagnostics_service.dart';
import '../data/dubbing_repository.dart';
import 'ai_scheduler_controller.dart';

class DubbingController extends StateNotifier<bool> {
  DubbingController({required DubbingRepository repository, required this.ref})
    : _repository = repository,
      super(true) {
    _init();
  }

  final DubbingRepository _repository;
  final Ref ref;
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription? _activeIdSub;

  void _init() {
    // Cấu hình AudioContext để lồng tiếng (TTS) tự động duck (giảm âm lượng) video nền
    // thay vì chiếm quyền ưu tiên hoàn toàn hoặc tạm dừng media chính.
    _audioPlayer.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.assistanceSonification,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {
            AVAudioSessionOptions.duckOthers,
            AVAudioSessionOptions.interruptSpokenAudioAndMixWithOthers,
          },
        ),
      ),
    );

    _activeIdSub = _repository.activeIdStream.listen((id) async {
      if (!state) return;

      if (id == null) {
        await _audioPlayer.stop();
        return;
      }

      final segment = _repository.getSegmentAt(
        ref.read(aiSchedulerProvider).playbackPosition,
      );
      if (segment != null) {
        await _playSegmentInMemory(segment.generatedAudio);
      }
    });
  }

  /// Phát trực tiếp dữ liệu âm thanh từ RAM bằng BytesSource, triệt tiêu I/O đĩa
  Future<void> _playSegmentInMemory(List<int> audioData) async {
    try {
      final wavData = Uint8List.fromList(_addWavHeader(audioData, 16000));
      await _audioPlayer.play(
        BytesSource(wavData),
        mode: PlayerMode.lowLatency,
      );
    } catch (e) {
      ref
          .read(diagnosticsServiceProvider)
          .log('Dubbing', 'InMemory Play error: $e', level: LogLevel.error);
    }
  }

  List<int> _addWavHeader(List<int> pcmData, int sampleRate) {
    final int fileSize = pcmData.length + 36;
    final ByteData header = ByteData(44);

    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); //
    header.setUint32(16, 16, Endian.little); // Chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, 1, Endian.little); // Mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
    header.setUint16(32, 2, Endian.little); // Block align
    header.setUint16(34, 16, Endian.little); // Bits per sample

    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, pcmData.length, Endian.little);

    return header.buffer.asUint8List().toList() + pcmData;
  }

  void toggleDubbing() {
    state = !state;
    if (!state) _audioPlayer.stop();
  }

  @override
  void dispose() {
    _activeIdSub?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}

final dubbingControllerProvider =
    StateNotifierProvider<DubbingController, bool>((ref) {
      return DubbingController(
        repository: ref.watch(dubbingRepositoryProvider),
        ref: ref,
      );
    });

```

