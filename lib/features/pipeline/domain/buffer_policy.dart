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
