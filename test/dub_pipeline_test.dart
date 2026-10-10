import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/pipeline/data/local_tts_engine.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/dub_segment.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/feature_entitlement.dart';
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
  group('Phase 10: Premium Local Vietnamese Voice-over Tests', () {
    test('synthesizes TTS audio and respects duration fitting', () async {
      final fakeRepo = FakeModelManagerRepository();
      final engine = LocalTextToSpeechEngine(fakeRepo);

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
      final engine = LocalTextToSpeechEngine(fakeRepo);

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
