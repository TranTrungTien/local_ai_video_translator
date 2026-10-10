import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/pipeline/data/local_translation_engine.dart';
import 'package:local_ai_video_translator/features/pipeline/data/subtitle_compressor.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/ai_pipeline.dart';
import 'package:local_ai_video_translator/features/settings/data/model_manager_repository.dart';
import 'package:local_ai_video_translator/features/settings/domain/model_manifest.dart';

class FakeModelManagerRepository implements ModelManagerRepository {
  @override
  Future<bool> isModelDownloaded(String modelId) async => true;

  @override
  Future<File> getModelFile(String modelId) async => File('dummy.onnx');

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
        final engine = LocalTranslationEngine(fakeRepo);

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
        final engine = LocalTranslationEngine(fakeRepo);

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
