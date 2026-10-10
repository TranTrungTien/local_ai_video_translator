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
