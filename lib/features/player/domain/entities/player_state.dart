enum PlayerStatus {
  idle,
  initializing,
  ready,
  playing,
  paused,
  buffering,
  seeking,
  ended,
  error,
}

sealed class PlayerError implements Exception {
  const PlayerError(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType: $message${cause != null ? ' ($cause)' : ''}';
}

final class PlaybackInitializationException extends PlayerError {
  const PlaybackInitializationException(super.message, [super.cause]);
}

final class MediaFormatUnsupportedException extends PlayerError {
  const MediaFormatUnsupportedException(super.message, [super.cause]);
}

final class NetworkStreamException extends PlayerError {
  const NetworkStreamException(super.message, [super.cause]);
}

final class NativePlayerBackendException extends PlayerError {
  const NativePlayerBackendException(super.message, [super.cause]);
}
