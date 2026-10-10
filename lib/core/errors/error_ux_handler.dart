enum AppErrorType {
  invalidUrl,
  unsupportedMedia,
  networkFailure,
  sourceGone,
  codecUnsupported,
  modelMissing,
  modelCorrupted,
  aiOom,
  aiTooSlow,
  embeddedAudioUnavailable,
  permissionDenied,
  translationError,
  storageFull,
  unknown,
}

class UserFriendlyError {
  const UserFriendlyError({
    required this.type,
    required this.title,
    required this.message,
    required this.actionLabel,
  });

  final AppErrorType type;
  final String title;
  final String message;
  final String actionLabel;

  static UserFriendlyError handle(Object error) {
    final str = error.toString().toLowerCase();

    if (str.contains('url') || str.contains('invalid')) {
      return const UserFriendlyError(
        type: AppErrorType.invalidUrl,
        title: 'Invalid URL',
        message:
            'The provided media link is invalid or malformed. Please check and try again.',
        actionLabel: 'Edit URL',
      );
    }
    if (str.contains('codec') || str.contains('unsupported')) {
      return const UserFriendlyError(
        type: AppErrorType.codecUnsupported,
        title: 'Codec Unsupported',
        message:
            'The media format or codec is not supported by the playback backend.',
        actionLabel: 'Switch Mode',
      );
    }
    if (str.contains('network') ||
        str.contains('socket') ||
        str.contains('dioexception')) {
      return const UserFriendlyError(
        type: AppErrorType.networkFailure,
        title: 'Network Connection Error',
        message:
            'Unable to connect to media source. Please check your internet connection.',
        actionLabel: 'Retry Connection',
      );
    }
    if (str.contains('model') &&
        (str.contains('missing') || str.contains('not found'))) {
      return const UserFriendlyError(
        type: AppErrorType.modelMissing,
        title: 'AI Model Required',
        message:
            'Required local AI models are not downloaded. Please download them in Settings.',
        actionLabel: 'Open Model Manager',
      );
    }
    if (str.contains('storage') || str.contains('space')) {
      return const UserFriendlyError(
        type: AppErrorType.storageFull,
        title: 'Storage Full',
        message:
            'Device storage is nearly full. Please clear cache or free up space.',
        actionLabel: 'Clear Cache',
      );
    }
    if (str.contains('permission') || str.contains('denied')) {
      return const UserFriendlyError(
        type: AppErrorType.permissionDenied,
        title: 'Permission Denied',
        message:
            'Required audio capture permission was denied. AI subtitles will remain disabled.',
        actionLabel: 'Open Settings',
      );
    }

    return const UserFriendlyError(
      type: AppErrorType.unknown,
      title: 'Playback Error',
      message: 'An unexpected error occurred during playback or AI processing.',
      actionLabel: 'Retry',
    );
  }
}
