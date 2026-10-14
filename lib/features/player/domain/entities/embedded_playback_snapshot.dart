
class EmbeddedPlaybackSnapshot {
  const EmbeddedPlaybackSnapshot({
    required this.source,
    required this.position,
    this.duration,
    required this.playbackRate,
    required this.wasPlaying,
    required this.volume,
    required this.playbackSessionId,
    required this.timelineEpoch,
    required this.requestHeaders,
  });

  final Uri source;
  final Duration position;
  final Duration? duration;
  final double playbackRate;
  final bool wasPlaying;
  final double volume;
  final String playbackSessionId;
  final int timelineEpoch;
  final Map<String, String> requestHeaders;

  @override
  String toString() {
    return 'EmbeddedPlaybackSnapshot(position: $position, wasPlaying: $wasPlaying, playbackRate: $playbackRate)';
  }
}
