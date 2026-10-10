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
