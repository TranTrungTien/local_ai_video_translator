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
