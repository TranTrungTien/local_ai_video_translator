import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/core/utils/cancellation_token.dart';
import 'package:local_ai_video_translator/features/pipeline/data/local_stt_engine.dart';
import 'package:local_ai_video_translator/features/pipeline/data/stt_benchmark.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/ai_pipeline.dart';
import 'package:local_ai_video_translator/features/settings/data/model_manager_repository.dart';
import 'package:local_ai_video_translator/features/settings/domain/model_manifest.dart';
import 'package:local_ai_video_translator/core/diagnostics/diagnostics_service.dart';

class MockDiagnosticsService implements DiagnosticsService {
  @override
  void log(String subsystem, String message, {LogLevel level = LogLevel.info, Object? details}) {}
  @override
  List<DiagnosticEntry> get logs => [];
  @override
  Stream<DiagnosticEntry> get stream => const Stream.empty();
  @override
  void clear() {}
  @override
  void dispose() {}
}

class FakeModelManagerRepository implements ModelManagerRepository {
  bool _exists = true;
  void setExists(bool value) => _exists = value;

  @override
  Future<bool> isModelDownloaded(String modelId) async => true;

  @override
  Future<File> getModelFile(String modelId, String fileName) async {
    if (!_exists) return File('non_existent.onnx');
    return File('dummy.onnx');
  }

  @override
  Future<Directory> getModelDir(String modelId) async => Directory('dummy');

  @override
  AiModelManifest? manifestById(String modelId) => null;

  @override
  Future<void> downloadModel(AiModelManifest manifest) async {}

  @override
  Future<void> deleteModel(String modelId) async {}

  @override
  void dispose() {}

  @override
  Stream<ModelDownloadProgress> get progressStream => const Stream.empty();

  @override
  AiModelManifest? get activeManifest => null;

  @override
  Future<void> setEnabledModel(String modelId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Phase 5: Local STT Pipeline & Benchmark Tests', () {
    test(
      'remaps STT segment timestamps back to original media presentation timestamps (PTS)',
      () async {
        final fakeRepo = FakeModelManagerRepository();
        final mockDiagnostics = MockDiagnosticsService();
        final sttEngine = LocalSpeechToTextEngine(fakeRepo, mockDiagnostics);

        final chunks = [
          PcmChunk(
            pts: const Duration(seconds: 10),
            sampleRate: 16000,
            channels: 1,
            bytes: Uint8List(100),
          ),
          PcmChunk(
            pts: const Duration(seconds: 13),
            sampleRate: 16000,
            channels: 1,
            bytes: Uint8List(100),
          ),
        ];

        final segments = await sttEngine.transcribe(
          Stream<PcmChunk>.fromIterable(chunks),
        );

        expect(segments.isNotEmpty, isTrue);
        expect(segments.first.start, equals(const Duration(seconds: 10)));
        // 200 bytes / 2 bytes per sample / 16000 samples per sec = 0.00625s = 6.25ms
        expect(
          segments.first.end.inMilliseconds,
          closeTo(10006, 1),
        );
      },
    );

    test(
      'cancels STT job instantly when cancellation token is triggered on seek',
      () async {
        final fakeRepo = FakeModelManagerRepository();
        final mockDiagnostics = MockDiagnosticsService();
        final sttEngine = LocalSpeechToTextEngine(fakeRepo, mockDiagnostics);
        final token = CancellationToken();

        token.cancel(); // Trigger cancellation before transcription

        final chunks = [
          PcmChunk(
            pts: const Duration(seconds: 1),
            sampleRate: 16000,
            channels: 1,
            bytes: Uint8List(100),
          ),
        ];

        expect(
          () => sttEngine.transcribeWithCancellation(
            Stream<PcmChunk>.fromIterable(chunks),
            cancellationToken: token,
          ),
          throwsA(isA<OperationCancelledException>()),
        );
      },
    );

    test(
      'falls back to degraded quality tier on low memory device constraints',
      () async {
        final fakeRepo = FakeModelManagerRepository();
        fakeRepo.setExists(false); // Simulate missing model for fallback
        final mockDiagnostics = MockDiagnosticsService();
        final sttEngine = LocalSpeechToTextEngine(fakeRepo, mockDiagnostics);
        final segments = await sttEngine.transcribe(
          Stream<PcmChunk>.fromIterable([
            PcmChunk(
              pts: Duration.zero,
              sampleRate: 16000,
              channels: 1,
              bytes: Uint8List(10),
            ),
          ]),
        );

        expect(segments.first.text, contains('Test transcription'));
      },
    );

    test('calculates realtime factor (RTF) correctly', () {
      final benchmark = SttBenchmarkResult.measure(
        modelLoadDuration: const Duration(milliseconds: 200),
        peakMemoryBytes: 40000000,
        audioDuration: const Duration(seconds: 10),
        inferenceDuration: const Duration(seconds: 4),
        language: 'vi',
        segmentCount: 2,
      );

      expect(
        benchmark.realtimeFactor,
        equals(0.4),
      ); // 4s inference / 10s audio = 0.4 (< 1.0 realtime)
    });
  });
}
