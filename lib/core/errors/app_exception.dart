sealed class AppException implements Exception {
  const AppException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

final class InvalidInputException extends AppException {
  const InvalidInputException(super.message);
}

final class ResolutionException extends AppException {
  const ResolutionException(super.message, [super.cause]);
}

final class PlaybackException extends AppException {
  const PlaybackException(super.message, [super.cause]);
}
