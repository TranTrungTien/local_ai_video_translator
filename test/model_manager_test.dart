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
