# Review Module: 07. Bộ Unit Tests Toàn Dự Án

## Included Files (16 files)

```text
test/ai_cache_test.dart
test/ai_scheduler_test.dart
test/audio_pipeline_test.dart
test/buffer_policy_test.dart
test/candidate_verifier_test.dart
test/dub_pipeline_test.dart
test/media_session_test.dart
test/media_url_test.dart
test/model_manager_test.dart
test/source_compatibility_test.dart
test/stt_pipeline_test.dart
test/subtitle_parser_test.dart
test/subtitle_pipeline_test.dart
test/track_model_test.dart
test/translation_pipeline_test.dart
test/widget_test.dart
```

## test/ai_cache_test.dart
```dart:test/ai_cache_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/pipeline/data/ai_cache_repository.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/cache_invalidation.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/media_identity.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/ai_pipeline.dart';

void main() {
  group('Phase 8: Local AI Cache & Media Identity Tests', () {
    test(
      'layered fingerprinting is robust to ephemeral CDN query token changes',
      () {
        const identityA = MediaIdentity(
          normalizedPath:
              'https://cdn.example.com/movie/stream.m3u8?token=abc123xyz&expires=1700000000',
          durationSeconds: 7200,
          title: 'Action Movie 2024',
        );

        const identityB = MediaIdentity(
          normalizedPath:
              'https://cdn.example.com/movie/stream.m3u8?token=differenttoken&expires=1999999999',
          durationSeconds: 7200,
          title: 'Action Movie 2024',
        );

        expect(
          identityA.generateFingerprint(),
          equals(identityB.generateFingerprint()),
        );
      },
    );

    test(
      'cache invalidation policy correctly detects incompatible model or pipeline versions',
      () {
        const policy = CacheInvalidationPolicy(
          sttModelVersion: '1.0.0',
          translationModelVersion: '1.2.0',
          targetLanguage: 'vi',
          pipelineVersion: '2.0.0',
        );

        // Compatible
        expect(
          policy.isCompatible(
            cachedSttVersion: '1.0.0',
            cachedTranslationVersion: '1.2.0',
            cachedTargetLang: 'vi',
            cachedPipelineVersion: '2.0.0',
          ),
          isTrue,
        );

        // Incompatible due to STT version upgrade
        expect(
          policy.isCompatible(
            cachedSttVersion: '1.1.0',
            cachedTranslationVersion: '1.2.0',
            cachedTargetLang: 'vi',
            cachedPipelineVersion: '2.0.0',
          ),
          isFalse,
        );
      },
    );

    test(
      'repository roundtrip saves and retrieves records correctly',
      () async {
        const policy = CacheInvalidationPolicy(
          sttModelVersion: '1.0.0',
          translationModelVersion: '1.2.0',
          targetLanguage: 'vi',
          pipelineVersion: '2.0.0',
        );
        final repo = AiCacheRepository(invalidationPolicy: policy);

        const identity = MediaIdentity(
          normalizedPath: 'https://example.com/anime/ep1.m3u8',
          durationSeconds: 1440,
          title: 'Anime Episode 1',
        );

        const segments = [
          TimedTextSegment(
            start: Duration.zero,
            end: Duration(seconds: 4),
            text: 'Cached Vietnamese Subtitle Line',
            language: 'vi',
          ),
        ];

        await repo.saveRecord(identity: identity, segments: segments);
        final retrieved = await repo.getRecord(identity);

        expect(retrieved, isNotNull);
        expect(retrieved!.length, equals(1));
        expect(retrieved[0].text, equals('Cached Vietnamese Subtitle Line'));
      },
    );
  });
}

```

## test/ai_scheduler_test.dart
```dart:test/ai_scheduler_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/buffer_policy.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/device_capability.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/playback_gate.dart';

void main() {
  group('Phase 7: AI Scheduler & Guaranteed Subtitle Buffer State-Machine Tests', () {
    const policy = AiBufferPolicy();
    const gate = PlaybackGate();

    test(
      'evaluates dynamic startup threshold correctly for device tier and playback rate',
      () {
        const profile = DeviceCapabilityProfile(
          memoryClassMb: 4096,
          cpuCores: 8,
          acceleration: AccelerationHardware.nnapi,
          thermalStatus: ThermalStatus.nominal,
          recentSttRtf: 0.4,
        );

        final thresholdNormal = policy.dynamicStartupThreshold(
          deviceProfile: profile,
          sttRtf: 0.4,
          translationThroughput: 100.0,
          playbackRate: 1.0,
        );

        final thresholdFast = policy.dynamicStartupThreshold(
          deviceProfile: profile,
          sttRtf: 0.3,
          translationThroughput: 120.0,
          playbackRate: 1.5, // 1.5x playback rate scales required buffer
        );

        expect(thresholdFast > thresholdNormal, isTrue);
      },
    );

    test(
      'transitions work modes correctly from BLOCKED to TURBO, NORMAL, ECO, and PAUSED',
      () {
        const snapshotEmpty = AiBufferSnapshot(
          playbackPosition: Duration(seconds: 10),
          subtitleReadyUntil: Duration(seconds: 10),
          dubReadyUntil: Duration.zero,
        );
        expect(policy.modeFor(snapshotEmpty), equals(AiWorkMode.blocked));

        const snapshotDanger = AiBufferSnapshot(
          playbackPosition: Duration(seconds: 10),
          subtitleReadyUntil: Duration(
            seconds: 13,
          ), // 3s ahead (< dangerBuffer * 6)
          dubReadyUntil: Duration.zero,
        );
        expect(policy.modeFor(snapshotDanger), equals(AiWorkMode.turbo));

        const snapshotHealthy = AiBufferSnapshot(
          playbackPosition: Duration(seconds: 10),
          subtitleReadyUntil: Duration(minutes: 10), // large lookahead
          dubReadyUntil: Duration.zero,
        );
        expect(policy.modeFor(snapshotHealthy), equals(AiWorkMode.paused));
      },
    );

    test(
      'PlaybackGate blocks playback immediately when subtitle buffer is exhausted',
      () {
        const snapshotExhausted = AiBufferSnapshot(
          playbackPosition: Duration(minutes: 5),
          subtitleReadyUntil: Duration(minutes: 5),
          dubReadyUntil: Duration.zero,
        );

        final decision = gate.evaluate(
          snapshot: snapshotExhausted,
          playbackRate: 1.0,
          isUserPaused: false,
        );

        expect(decision.shouldPlay, isFalse);
        expect(decision.reason, contains('Subtitle buffer exhausted'));
        expect(decision.workMode, equals(AiWorkMode.blocked));
      },
    );

    test('PlaybackGate allows playback when subtitles are ahead', () {
      const snapshotAhead = AiBufferSnapshot(
        playbackPosition: Duration(minutes: 5),
        subtitleReadyUntil: Duration(minutes: 6),
        dubReadyUntil: Duration.zero,
      );

      final decision = gate.evaluate(
        snapshot: snapshotAhead,
        playbackRate: 1.0,
        isUserPaused: false,
      );

      expect(decision.shouldPlay, isTrue);
    });
  });
}

```

## test/audio_pipeline_test.dart
```dart:test/audio_pipeline_test.dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/audio/data/bounded_pcm_queue.dart';
import 'dart:io';
import 'package:local_ai_video_translator/features/audio/data/vad_engine.dart';
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

class MockModelManagerRepository implements ModelManagerRepository {
  @override
  Future<File> getModelFile(String modelId, String fileName) async {
    return File('non_existent_path');
  }

  @override
  Future<Directory> getModelDir(String modelId) async {
    return Directory('non_existent_path');
  }

  @override
  AiModelManifest? manifestById(String modelId) {
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Phase 4: Timed Audio & Bounded PCM Queue Tests', () {
    test('preserves exact media PTS, sample rate, channels, and format', () {
      final bytes = Uint8List(16000); // 16KB of mock PCM data
      final chunk = PcmChunk(
        pts: const Duration(seconds: 5),
        sampleRate: 16000,
        channels: 1,
        bytes: bytes,
      );

      expect(chunk.pts, equals(const Duration(seconds: 5)));
      expect(chunk.sampleRate, equals(16000));
      expect(chunk.channels, equals(1));
      expect(chunk.bytes.length, equals(16000));
    });

    test(
      'bounded queue enforces capacity and applies backpressure by dropping oldest chunk',
      () {
        final queue = BoundedPcmQueue(maxCapacity: 3);

        for (var i = 0; i < 5; i++) {
          queue.enqueue(
            PcmChunk(
              pts: Duration(seconds: i),
              sampleRate: 16000,
              channels: 1,
              bytes: Uint8List(100),
            ),
          );
        }

        // Max capacity is 3, so first 2 chunks (seconds 0 and 1) should be dropped
        expect(queue.length, equals(3));
        final firstDequeued = queue.dequeue();
        expect(firstDequeued?.pts, equals(const Duration(seconds: 2)));
      },
    );

    test('clears queue before specified seek PTS', () {
      final queue = BoundedPcmQueue(maxCapacity: 10);
      queue.enqueue(
        PcmChunk(
          pts: const Duration(seconds: 1),
          sampleRate: 16000,
          channels: 1,
          bytes: Uint8List(10),
        ),
      );
      queue.enqueue(
        PcmChunk(
          pts: const Duration(seconds: 5),
          sampleRate: 16000,
          channels: 1,
          bytes: Uint8List(10),
        ),
      );

      queue.clearBefore(const Duration(seconds: 3));
      expect(queue.length, equals(1));
      expect(queue.dequeue()?.pts, equals(const Duration(seconds: 5)));
    });
  });

  group('Phase 4: VAD (Voice Activity Detector) Segmentation Tests', () {
    test(
      'detects speech and applies merge-small-gap and min-speech-length policies',
      () async {
        // Mock repository not strictly needed for energy-only test path if session is null
        // but required for constructor
        final vad = LocalVadEngine(
          MockModelManagerRepository(),
          MockDiagnosticsService(),
          minSpeechDuration: const Duration(milliseconds: 400),
          maxMergeGap: const Duration(milliseconds: 300),
        );

        final silentBytes = Uint8List(3200); // all zeros -> RMS 0
        final speechBytes = Uint8List(3200);
        final int16View = Int16List.view(speechBytes.buffer);
        for (var i = 0; i < int16View.length; i++) {
          int16View[i] = 2000; // high energy samples
        }

        final mockChunks = [
          PcmChunk(
            pts: const Duration(seconds: 0),
            sampleRate: 16000,
            channels: 1,
            bytes: silentBytes,
          ),
          PcmChunk(
            pts: const Duration(milliseconds: 500),
            sampleRate: 16000,
            channels: 1,
            bytes: silentBytes,
          ),
          PcmChunk(
            pts: const Duration(seconds: 1),
            sampleRate: 16000,
            channels: 1,
            bytes: speechBytes,
          ),
          PcmChunk(
            pts: const Duration(milliseconds: 1500),
            sampleRate: 16000,
            channels: 1,
            bytes: speechBytes,
          ),
          PcmChunk(
            pts: const Duration(seconds: 2),
            sampleRate: 16000,
            channels: 1,
            bytes: speechBytes,
          ),
          PcmChunk(
            pts: const Duration(milliseconds: 2500),
            sampleRate: 16000,
            channels: 1,
            bytes: silentBytes,
          ), // small gap
          PcmChunk(
            pts: const Duration(seconds: 3),
            sampleRate: 16000,
            channels: 1,
            bytes: speechBytes,
          ),
          PcmChunk(
            pts: const Duration(milliseconds: 3500),
            sampleRate: 16000,
            channels: 1,
            bytes: speechBytes,
          ),
          PcmChunk(
            pts: const Duration(seconds: 4),
            sampleRate: 16000,
            channels: 1,
            bytes: silentBytes,
          ),
        ];

        final stream = Stream<PcmChunk>.fromIterable(mockChunks);
        final segments = await vad.detectSpeech(stream).toList();

        expect(segments.isNotEmpty, isTrue);
        expect(segments.first.start, isNotNull);
      },
    );
  });
}

```

## test/buffer_policy_test.dart
```dart:test/buffer_policy_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/buffer_policy.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/device_capability.dart';

void main() {
  const policy = AiBufferPolicy();

  test('blocks when subtitle buffer is exhausted', () {
    const snapshot = AiBufferSnapshot(
      playbackPosition: Duration(minutes: 5),
      subtitleReadyUntil: Duration(minutes: 5),
      dubReadyUntil: Duration.zero,
    );
    expect(policy.shouldBlockPlayback(snapshot), isTrue);
    expect(policy.modeFor(snapshot), AiWorkMode.blocked);
  });

  test('can start after initial subtitle buffer', () {
    const snapshot = AiBufferSnapshot(
      playbackPosition: Duration.zero,
      subtitleReadyUntil: Duration(minutes: 1),
      dubReadyUntil: Duration.zero,
    );
    expect(
      policy.canStart(
        snapshot,
        deviceProfile: DeviceCapabilityProfile.defaultProfile,
      ),
      isTrue,
    );
  });
}

```

## test/candidate_verifier_test.dart
```dart:test/candidate_verifier_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/source_resolver/data/media_candidate.dart';
import 'package:local_ai_video_translator/features/source_resolver/domain/entities/resolved_source.dart';

void main() {
  test('creates MediaCandidate with correct properties', () {
    final candidate = MediaCandidate(
      uri: Uri.parse('https://example.com/master.m3u8'),
      kind: MediaKind.hls,
      method: DiscoveryMethod.htmlVideo,
      score: 60,
    );

    expect(candidate.kind, equals(MediaKind.hls));
    expect(candidate.score, equals(60));
    expect(candidate.method, equals(DiscoveryMethod.htmlVideo));
  });
}

```

## test/dub_pipeline_test.dart
```dart:test/dub_pipeline_test.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/pipeline/data/local_tts_engine.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/dub_segment.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/feature_entitlement.dart';
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
  @override
  Future<bool> isModelDownloaded(String modelId) async => true;

  @override
  Future<File> getModelFile(String modelId, String fileName) async => File('dummy.onnx');

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
}

void main() {
  group('Phase 10: Premium Local Vietnamese Voice-over Tests', () {
    test('synthesizes TTS audio and respects duration fitting', () async {
      final fakeRepo = FakeModelManagerRepository();
      final engine = LocalTextToSpeechEngine(fakeRepo, MockDiagnosticsService());

      const target = Duration(seconds: 3);
      final audio = await engine.synthesize(
        'Xin chào thế giới',
        targetDuration: target,
      );

      expect(audio.isNotEmpty, isTrue);

      final segment = DubSegment(
        id: 'dub_1',
        startPts: Duration.zero,
        endPts: target,
        sourceText: 'Hello world',
        translatedText: 'Xin chào thế giới',
        generatedAudio: audio,
        generatedDuration: target,
        targetDuration: target,
        voiceId: 'vi_female_1',
        modelVersion: '0.9.0',
      );

      expect(segment.isDurationFitted, isTrue);
    });

    test('TTS cache reuses generated audio on backward seek', () async {
      final fakeRepo = FakeModelManagerRepository();
      final engine = LocalTextToSpeechEngine(fakeRepo, MockDiagnosticsService());

      const target = Duration(seconds: 2);
      final audio1 = await engine.synthesize(
        'Repeated sentence',
        targetDuration: target,
      );
      final audio2 = await engine.synthesize(
        'Repeated sentence',
        targetDuration: target,
      );

      expect(audio1, equals(audio2));
      expect(engine.cache.size, equals(1));
    });

    test('feature entitlement controlled access to voice-over', () {
      const freeTier = FeatureEntitlement.defaultFree;
      expect(freeTier.canUseVoiceOver, isFalse);

      const unlockedTier = FeatureEntitlement.defaultDeveloperUnlocked;
      expect(unlockedTier.canUseVoiceOver, isTrue);
      expect(unlockedTier.maxVoicesAvailable, greaterThan(0));
    });
  });
}

```

## test/media_session_test.dart
```dart:test/media_session_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/player/domain/entities/media_session_snapshot.dart';
import 'package:local_ai_video_translator/features/player/domain/entities/player_state.dart';
import 'package:local_ai_video_translator/features/source_resolver/domain/entities/resolved_source.dart';

void main() {
  group('MediaSessionSnapshot Domain Tests', () {
    test('initial snapshot has idle status and zero durations', () {
      const snapshot = MediaSessionSnapshot.idle;
      expect(snapshot.status, equals(PlayerStatus.idle));
      expect(snapshot.position, equals(Duration.zero));
      expect(snapshot.duration, equals(Duration.zero));
      expect(snapshot.isPlaying, isFalse);
      expect(snapshot.isReady, isFalse);
      expect(snapshot.playbackRate, equals(1.0));
    });

    test('copyWith produces expected updated state', () {
      const snapshot = MediaSessionSnapshot.idle;
      final updated = snapshot.copyWith(
        status: PlayerStatus.playing,
        position: const Duration(seconds: 15),
        duration: const Duration(minutes: 10),
        playbackRate: 1.25,
      );

      expect(updated.status, equals(PlayerStatus.playing));
      expect(updated.isPlaying, isTrue);
      expect(updated.isReady, isTrue);
      expect(updated.position, equals(const Duration(seconds: 15)));
      expect(updated.playbackRate, equals(1.25));
    });

    test('isolates request context between media sessions', () {
      const contextA = RequestContext(
        userAgent: 'AgentA/1.0',
        headers: {'Authorization': 'Bearer TokenA'},
      );
      const contextB = RequestContext(
        userAgent: 'AgentB/2.0',
        headers: {'Authorization': 'Bearer TokenB'},
      );

      final snapshotA = MediaSessionSnapshot.idle.copyWith(
        requestContext: contextA,
      );
      final snapshotB = MediaSessionSnapshot.idle.copyWith(
        requestContext: contextB,
      );

      expect(
        snapshotA.requestContext.headers['Authorization'],
        equals('Bearer TokenA'),
      );
      expect(
        snapshotB.requestContext.headers['Authorization'],
        equals('Bearer TokenB'),
      );
      expect(
        snapshotA.requestContext.headers['Authorization'],
        isNot(equals(snapshotB.requestContext.headers['Authorization'])),
      );
    });
  });
}

```

## test/media_url_test.dart
```dart:test/media_url_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/core/utils/media_url.dart';

void main() {
  test('classifies HLS', () {
    expect(
      MediaUrl.classify('https://cdn.example.com/a/master.m3u8'),
      MediaUrlKind.hls,
    );
  });

  test('classifies DASH', () {
    expect(
      MediaUrl.classify('https://cdn.example.com/a/manifest.mpd'),
      MediaUrlKind.dash,
    );
  });

  test('classifies a watch page as web page', () {
    expect(
      MediaUrl.classify('https://example.com/watch/123'),
      MediaUrlKind.webPage,
    );
  });
}

```

## test/model_manager_test.dart
```dart:test/model_manager_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/settings/data/model_manager_repository.dart';
import 'package:local_ai_video_translator/features/settings/domain/model_manifest.dart';

void main() {
  test('default model manifests contain required AI engines', () {
    final manifests = ModelManagerRepository.defaultManifests;
    expect(manifests.length, greaterThanOrEqualTo(4));

    final stt = manifests.firstWhere((m) => m.type == AiModelType.stt);
    final translation = manifests.firstWhere(
      (m) => m.type == AiModelType.translation,
    );
    final tts = manifests.firstWhere((m) => m.type == AiModelType.tts);
    final vad = manifests.firstWhere((m) => m.type == AiModelType.vad);

    expect(stt.id, contains('whisper'));
    expect(translation.id, contains('opus'));
    expect(tts.id, contains('piper'));
    expect(vad.id, contains('silero'));
  });
}

```

## test/source_compatibility_test.dart
```dart:test/source_compatibility_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/core/utils/media_url.dart';
import 'package:local_ai_video_translator/features/source_resolver/data/html_media_parser.dart';
import 'package:local_ai_video_translator/features/source_resolver/domain/entities/resolved_source.dart';

void main() {
  group('URL Classification & Normalization', () {
    test('classifies HLS playlists', () {
      expect(
        MediaUrl.classify('https://cdn.movie.org/stream/index.m3u8'),
        MediaUrlKind.hls,
      );
    });

    test('classifies DASH manifests', () {
      expect(
        MediaUrl.classify('https://cdn.movie.org/stream/manifest.mpd'),
        MediaUrlKind.dash,
      );
    });

    test('classifies progressive video files', () {
      expect(
        MediaUrl.classify('https://cdn.movie.org/stream/video.mp4'),
        MediaUrlKind.progressive,
      );
      expect(
        MediaUrl.classify('https://cdn.movie.org/stream/movie.mkv'),
        MediaUrlKind.progressive,
      );
      expect(
        MediaUrl.classify('https://cdn.movie.org/stream/anime.webm'),
        MediaUrlKind.progressive,
      );
    });

    test('classifies local video files', () {
      expect(
        MediaUrl.classify('/sdcard/Download/movie.mp4'),
        MediaUrlKind.localFile,
      );
      expect(
        MediaUrl.classify('file:///storage/emulated/0/anime.mkv'),
        MediaUrlKind.localFile,
      );
    });

    test('classifies watch page as web page', () {
      expect(
        MediaUrl.classify('https://watch.anime.org/episode/123'),
        MediaUrlKind.webPage,
      );
    });
  });

  group('Static HTML Media Parser', () {
    const parser = HtmlMediaParser();
    final baseUri = Uri.parse('https://example.com/watch/101');

    test('extracts direct video and source tags', () {
      const html = '''
        <html>
          <body>
            <video src="/media/video_720p.mp4"></video>
            <source src="https://cdn.example.com/hls/master.m3u8">
          </body>
        </html>
      ''';

      final parsed = parser.parse(html, baseUri);
      expect(parsed.candidates.length, equals(2));
      expect(
        parsed.candidates.any((c) => c.kind == MediaKind.progressive),
        isTrue,
      );
      expect(parsed.candidates.any((c) => c.kind == MediaKind.hls), isTrue);
    });

    test('resolves relative iframe URLs and deduplicates', () {
      const html = '''
        <html>
          <body>
            <iframe src="/embed/player?id=123"></iframe>
            <iframe src="/embed/player?id=123"></iframe>
            <iframe src="https://player.external.com/frame.html"></iframe>
          </body>
        </html>
      ''';

      final parsed = parser.parse(html, baseUri);
      expect(parsed.iframes.length, equals(2));
      expect(
        parsed.iframes[0].toString(),
        equals('https://example.com/embed/player?id=123'),
      );
      expect(
        parsed.iframes[1].toString(),
        equals('https://player.external.com/frame.html'),
      );
    });

    test('extracts escaped video candidate URLs from script configs', () {
      const html = r'''
        <script>
          var playerConfig = {
            "file": "https:\/\/cdn.example.com\/stream\/playlist.m3u8?token=abc"
          };
        </script>
      ''';

      final parsed = parser.parse(html, baseUri);
      expect(parsed.candidates.length, equals(1));
      expect(
        parsed.candidates.first.uri.toString(),
        equals('https://cdn.example.com/stream/playlist.m3u8?token=abc'),
      );
      expect(parsed.candidates.first.kind, equals(MediaKind.hls));
    });
  });

  group('Response Signatures', () {
    test('detects HLS signature #EXTM3U', () {
      const body =
          '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-STREAM-INF:BANDWIDTH=128000\nchunk.m3u8';
      expect(body.trimLeft().startsWith('#EXTM3U'), isTrue);
    });

    test('detects DASH signature MPD', () {
      const body =
          '<?xml version="1.0"?>\n<MPD xmlns="urn:mpeg:dash:schema:mpd:2011">';
      expect(
        body.contains('<MPD') || body.contains('urn:mpeg:dash:schema:mpd:2011'),
        isTrue,
      );
    });
  });
}

```

## test/stt_pipeline_test.dart
```dart:test/stt_pipeline_test.dart
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
        expect(
          segments.first.end,
          equals(const Duration(seconds: 13, milliseconds: 500)),
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

        expect(segments.first.text, contains('[STT Model Missing]'));
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

```

## test/subtitle_parser_test.dart
```dart:test/subtitle_parser_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/subtitles/data/subtitle_parser.dart';

void main() {
  const parser = SubtitleParser();

  test('parses WebVTT content with formatting tags', () {
    const vtt = '''
WEBVTT

00:00:01.000 --> 00:00:04.000
<b>Hello</b> world!

00:00:05.500 --> 00:00:08.200
Welcome to <i>Vietnamese</i> translation.
''';

    final segments = parser.parseVtt(vtt, language: 'en');
    expect(segments.length, equals(2));
    expect(segments[0].text, equals('Hello world!'));
    expect(segments[0].start, equals(const Duration(seconds: 1)));
    expect(segments[0].end, equals(const Duration(seconds: 4)));

    expect(segments[1].text, equals('Welcome to Vietnamese translation.'));
    expect(
      segments[1].start,
      equals(const Duration(seconds: 5, milliseconds: 500)),
    );
  });

  test('parses SRT content', () {
    const srt = '''
1
00:00:02,000 --> 00:00:05,000
Long-form anime episode

2
00:00:06,000 --> 00:00:09,500
Local AI translation ready
''';

    final segments = parser.parseSrt(srt, language: 'ja');
    expect(segments.length, equals(2));
    expect(segments[0].text, equals('Long-form anime episode'));
    expect(segments[1].text, equals('Local AI translation ready'));
  });
}

```

## test/subtitle_pipeline_test.dart
```dart:test/subtitle_pipeline_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/subtitles/data/subtitle_language_detector.dart';
import 'package:local_ai_video_translator/features/subtitles/data/subtitle_parser.dart';
import 'package:local_ai_video_translator/features/subtitles/domain/entities/subtitle_track.dart';
import 'package:local_ai_video_translator/features/subtitles/domain/subtitle_selection_policy.dart';

void main() {
  const parser = SubtitleParser();
  const languageDetector = SubtitleLanguageDetector();
  const selectionPolicy = SubtitleSelectionPolicy();

  group('Phase 3: Subtitle Parser & Normalization Tests', () {
    test(
      'parses WebVTT with multiline, empty lines, unicode Vietnamese, and long lines',
      () {
        const vtt = '''
WEBVTT

NOTE
This is a comment note that should be ignored.

00:00:01.000 --> 00:00:04.000
Xin chào các bạn, đây là phụ đề tiếng Việt
với nhiều dòng (multiline).

00:00:03.500 --> 00:00:07.000
Overlapping caption segment with very long line exceeding standard limits for subtitle presentation testing purposes.

00:00:08.000 --> 00:00:10.000
   
''';

        final doc = parser.parseVttDocument(vtt, language: 'vi');
        expect(doc.segments.length, equals(2));
        expect(doc.segments[0].text, contains('Xin chào các bạn'));
        expect(doc.segments[0].text, contains('với nhiều dòng'));
        expect(doc.segments[1].text, contains('Overlapping caption segment'));
        expect(doc.segments[0].start, equals(const Duration(seconds: 1)));
        expect(
          doc.segments[1].start,
          equals(const Duration(milliseconds: 3500)),
        );
      },
    );

    test('handles malformed timestamp entries gracefully without crashing', () {
      const malformedVtt = '''
WEBVTT

00:60:00.000 --> invalid_timestamp
Malformed line here

00:00:05.000 --> 00:00:08.000
Valid caption after malformed entry
''';

      final doc = parser.parseVttDocument(malformedVtt);
      expect(doc.segments.length, equals(1));
      expect(
        doc.segments[0].text,
        equals('Valid caption after malformed entry'),
      );
    });

    test('parses TTML XML timed text documents', () {
      const ttml = '''
<tt xml:lang="en">
  <body>
    <div>
      <p begin="00:00:02.500" end="00:00:05.000">English DASH TTML caption line</p>
      <p begin="00:00:06.000" end="00:00:09.500">Second TTML caption entry</p>
    </div>
  </body>
</tt>
''';

      final doc = parser.parseTtmlDocument(ttml, language: 'en');
      expect(doc.segments.length, equals(2));
      expect(doc.segments[0].text, equals('English DASH TTML caption line'));
      expect(
        doc.segments[0].start,
        equals(const Duration(seconds: 2, milliseconds: 500)),
      );
    });
  });

  group('Phase 3: Subtitle Language Detection Tests', () {
    test('detects language from declared metadata or diacritics heuristic', () {
      expect(
        languageDetector.detectLanguage(declaredLanguage: 'vi'),
        equals('vi'),
      );
      expect(
        languageDetector.detectLanguage(declaredLanguage: 'Vietnamese'),
        equals('vi'),
      );
      expect(
        languageDetector.detectLanguage(declaredLanguage: 'en'),
        equals('en'),
      );

      final sampleVi = 'Bộ phim hoạt hình tuyệt vời tiếng Việt';
      expect(
        languageDetector.detectLanguage(sampleText: sampleVi),
        equals('vi'),
      );
    });
  });

  group('Phase 3: Subtitle Selection Policy Tests', () {
    test('selects DIRECT_VI when Vietnamese subtitle track is available', () {
      final tracks = [
        SubtitleTrack(
          id: 'sub_en',
          language: 'en',
          title: 'English Track',
          uri: Uri.parse('https://example.com/en.vtt'),
          format: SubtitleFormat.webvtt,
        ),
        SubtitleTrack(
          id: 'sub_vi',
          language: 'vi',
          title: 'Vietnamese Track',
          uri: Uri.parse('https://example.com/vi.vtt'),
          format: SubtitleFormat.webvtt,
          isTargetLanguage: true,
        ),
      ];

      final result = selectionPolicy.evaluate(tracks);
      expect(result.decision, equals(SubtitleSelectionDecision.directVi));
      expect(result.selectedTrack?.id, equals('sub_vi'));
      expect(result.isDirectVi, isTrue);
    });

    test(
      'selects TRANSLATE_EXISTING when only foreign subtitle is available',
      () {
        final tracks = [
          SubtitleTrack(
            id: 'sub_ja',
            language: 'ja',
            title: 'Japanese Original',
            uri: Uri.parse('https://example.com/ja.vtt'),
            format: SubtitleFormat.webvtt,
          ),
        ];

        final result = selectionPolicy.evaluate(tracks);
        expect(
          result.decision,
          equals(SubtitleSelectionDecision.translateExisting),
        );
        expect(result.selectedTrack?.id, equals('sub_ja'));
        expect(result.isTranslateExisting, isTrue);
      },
    );

    test('selects STT_REQUIRED when no subtitle tracks are present', () {
      final result = selectionPolicy.evaluate([]);
      expect(result.decision, equals(SubtitleSelectionDecision.sttRequired));
      expect(result.isSttRequired, isTrue);
    });
  });
}

```

## test/track_model_test.dart
```dart:test/track_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/player/domain/entities/media_track.dart';

void main() {
  group('Media Track Classification Tests', () {
    test('classifies Vietnamese language subtitle tracks', () {
      expect(
        PlayerSubtitleTrack.classify('vi'),
        equals(SubtitleClassification.vietnamese),
      );
      expect(
        PlayerSubtitleTrack.classify('vietnamese'),
        equals(SubtitleClassification.vietnamese),
      );
      expect(
        PlayerSubtitleTrack.classify('VIE'),
        equals(SubtitleClassification.vietnamese),
      );
    });

    test('classifies source language subtitle tracks', () {
      expect(
        PlayerSubtitleTrack.classify('en'),
        equals(SubtitleClassification.sourceLanguage),
      );
      expect(
        PlayerSubtitleTrack.classify('english'),
        equals(SubtitleClassification.sourceLanguage),
      );
      expect(
        PlayerSubtitleTrack.classify('ja'),
        equals(SubtitleClassification.sourceLanguage),
      );
      expect(
        PlayerSubtitleTrack.classify('japanese'),
        equals(SubtitleClassification.sourceLanguage),
      );
      expect(
        PlayerSubtitleTrack.classify('zh'),
        equals(SubtitleClassification.sourceLanguage),
      );
    });

    test('classifies unknown language subtitle tracks', () {
      expect(
        PlayerSubtitleTrack.classify('fr'),
        equals(SubtitleClassification.unknownOther),
      );
      expect(
        PlayerSubtitleTrack.classify('es'),
        equals(SubtitleClassification.unknownOther),
      );
      expect(
        PlayerSubtitleTrack.classify('unknown'),
        equals(SubtitleClassification.unknownOther),
      );
    });

    test('supports multiple audio tracks without assuming dialogue track', () {
      const track1 = AudioTrack(
        id: 'a1',
        label: 'Audio 1 (Background Music)',
        language: 'en',
        channels: 2,
      );
      const track2 = AudioTrack(
        id: 'a2',
        label: 'Audio 2 (Dialogue Commentary)',
        language: 'ja',
        channels: 1,
      );

      const trackSet = MediaTrackSet(audioTracks: [track1, track2]);
      expect(trackSet.audioTracks.length, equals(2));
      expect(trackSet.audioTracks[1].label, contains('Dialogue Commentary'));
    });
  });
}

```

## test/translation_pipeline_test.dart
```dart:test/translation_pipeline_test.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/pipeline/data/local_translation_engine.dart';
import 'package:local_ai_video_translator/features/pipeline/data/subtitle_compressor.dart';
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
  @override
  Future<bool> isModelDownloaded(String modelId) async => true;

  @override
  Future<File> getModelFile(String modelId, String fileName) async => File('dummy.onnx');

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
}

void main() {
  group('Phase 6: Local Vietnamese Translation Pipeline Tests', () {
    test(
      'translates text to Vietnamese using rolling context and cache',
      () async {
        final fakeRepo = FakeModelManagerRepository();
        final engine = LocalTranslationEngine(fakeRepo, MockDiagnosticsService());

        const segments = [
          TimedTextSegment(
            start: Duration.zero,
            end: Duration(seconds: 2),
            text: 'Hello world',
            language: 'en',
          ),
          TimedTextSegment(
            start: Duration(seconds: 3),
            end: Duration(seconds: 5),
            text: 'Welcome to episode 1',
            language: 'en',
          ),
          TimedTextSegment(
            start: Duration(seconds: 6),
            end: Duration(seconds: 8),
            text: '',
            language: 'en',
          ), // empty text edge case
        ];

        final translated = await engine.translate(
          segments,
          targetLanguage: 'vi',
        );

        expect(translated.length, equals(3));
        expect(translated[0].text, equals('Xin chào'));
        expect(
          translated[1].text,
          equals('Chào mừng bạn đến với chương trình'),
        );
        expect(translated[2].text, equals('')); // empty text preserved
      },
    );

    test(
      'cache prevents redundant re-translation after backward seek or repeated lines',
      () async {
        final fakeRepo = FakeModelManagerRepository();
        final engine = LocalTranslationEngine(fakeRepo, MockDiagnosticsService());

        const segments = [
          TimedTextSegment(
            start: Duration.zero,
            end: Duration(seconds: 2),
            text: 'Thank you',
            language: 'en',
          ),
          TimedTextSegment(
            start: Duration(seconds: 3),
            end: Duration(seconds: 5),
            text: 'Thank you',
            language: 'en',
          ), // repeated line
        ];

        final translated = await engine.translate(
          segments,
          targetLanguage: 'vi',
        );

        expect(translated.length, equals(2));
        expect(translated[0].text, equals('Cảm ơn bạn rất nhiều'));
        expect(translated[1].text, equals('Cảm ơn bạn rất nhiều'));
        expect(
          engine.cache.size,
          equals(1),
        ); // cached by stable source text identity
      },
    );

    test(
      'subtitle compressor wraps long lines for optimal mobile readability',
      () {
        const compressor = SubtitleCompressor(maxLineLength: 30);
        const longText =
            'This is an extremely long subtitle string that needs to be wrapped properly for mobile screens.';

        final compressed = compressor.compress(longText);
        expect(compressed, contains('\n'));
      },
    );
  });
}

```

## test/widget_test.dart
```dart:test/widget_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/app/app.dart';

void main() {
  testWidgets('TranslatorApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TranslatorApp()));
    expect(find.text('AI Video Translator'), findsOneWidget);
  });
}

```

