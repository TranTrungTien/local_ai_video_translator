enum MediaUrlKind { hls, dash, progressive, webPage, localFile, unknown }

abstract final class MediaUrl {
  static MediaUrlKind classify(String input) {
    final value = input.trim();
    if (value.startsWith('file://') ||
        value.startsWith('content://') ||
        value.startsWith('/')) {
      return MediaUrlKind.localFile;
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      return MediaUrlKind.unknown;
    }
    final path = uri.path.toLowerCase();
    if (path.endsWith('.m3u8')) {
      return MediaUrlKind.hls;
    }
    if (path.endsWith('.mpd')) {
      return MediaUrlKind.dash;
    }
    if (['.mp4', '.mkv', '.webm', '.mov', '.m4v'].any(path.endsWith)) {
      return MediaUrlKind.progressive;
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return MediaUrlKind.webPage;
    }
    return MediaUrlKind.unknown;
  }
}
