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
