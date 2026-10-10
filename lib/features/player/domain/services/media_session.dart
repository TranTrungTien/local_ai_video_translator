import '../../../source_resolver/domain/entities/resolved_source.dart';
import '../entities/media_session_snapshot.dart';
import '../entities/media_track.dart';

abstract interface class MediaSession {
  MediaSessionSnapshot get currentSnapshot;
  Stream<MediaSessionSnapshot> get snapshotStream;

  Future<void> open(ResolvedSource source);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setPlaybackRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> selectVideoTrack(VideoTrack track);
  Future<void> selectAudioTrack(AudioTrack track);
  Future<void> selectSubtitleTrack(PlayerSubtitleTrack? track);
  Future<void> close();
}
