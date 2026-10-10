import '../../../source_resolver/domain/entities/resolved_source.dart';
import 'media_track.dart';
import 'migration_state.dart';
import 'player_state.dart';

class MediaSessionSnapshot {
  const MediaSessionSnapshot({
    required this.mediaIdentity,
    required this.duration,
    required this.position,
    required this.buffered,
    required this.status,
    required this.playbackRate,
    this.activeVideoTrack,
    this.activeAudioTrack,
    this.activeSubtitleTrack,
    this.trackSet = MediaTrackSet.empty,
    this.requestContext = RequestContext.defaultContext,
    this.error,
    this.migrationStatus = MigrationStatus.embedded,
  });

  final String mediaIdentity;
  final Duration duration;
  final Duration position;
  final Duration buffered;
  final PlayerStatus status;
  final double playbackRate;
  final VideoTrack? activeVideoTrack;
  final AudioTrack? activeAudioTrack;
  final PlayerSubtitleTrack? activeSubtitleTrack;
  final MediaTrackSet trackSet;
  final RequestContext requestContext;
  final PlayerError? error;
  final MigrationStatus migrationStatus;

  bool get isPlaying => status == PlayerStatus.playing;
  bool get isPaused => status == PlayerStatus.paused;
  bool get isBuffering => status == PlayerStatus.buffering;
  bool get isCompleted => status == PlayerStatus.ended;
  bool get isReady =>
      status == PlayerStatus.ready ||
      status == PlayerStatus.playing ||
      status == PlayerStatus.paused;

  MediaSessionSnapshot copyWith({
    String? mediaIdentity,
    Duration? duration,
    Duration? position,
    Duration? buffered,
    PlayerStatus? status,
    double? playbackRate,
    VideoTrack? activeVideoTrack,
    AudioTrack? activeAudioTrack,
    PlayerSubtitleTrack? activeSubtitleTrack,
    MediaTrackSet? trackSet,
    RequestContext? requestContext,
    PlayerError? error,
    MigrationStatus? migrationStatus,
  }) {
    return MediaSessionSnapshot(
      mediaIdentity: mediaIdentity ?? this.mediaIdentity,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      buffered: buffered ?? this.buffered,
      status: status ?? this.status,
      playbackRate: playbackRate ?? this.playbackRate,
      activeVideoTrack: activeVideoTrack ?? this.activeVideoTrack,
      activeAudioTrack: activeAudioTrack ?? this.activeAudioTrack,
      activeSubtitleTrack: activeSubtitleTrack ?? this.activeSubtitleTrack,
      trackSet: trackSet ?? this.trackSet,
      requestContext: requestContext ?? this.requestContext,
      error: error ?? this.error,
      migrationStatus: migrationStatus ?? this.migrationStatus,
    );
  }

  static const idle = MediaSessionSnapshot(
    mediaIdentity: '',
    duration: Duration.zero,
    position: Duration.zero,
    buffered: Duration.zero,
    status: PlayerStatus.idle,
    playbackRate: 1.0,
  );
}
