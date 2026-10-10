import '../../source_resolver/domain/entities/resolved_source.dart';

abstract interface class PlaybackGateway {
  Future<void> open(ResolvedSource source);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Stream<Duration> get position;
  Stream<Duration> get buffered;
}
