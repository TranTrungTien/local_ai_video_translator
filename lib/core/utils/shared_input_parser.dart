/// Extracts http(s) URLs or valid file paths from shared content.
abstract final class SharedInputParser {
  static final RegExp _urlPattern = RegExp(
    r'''https?://[^\s<>"']+''',
    caseSensitive: false,
  );

  /// Returns the first usable source, or null if none found.
  static String? extract(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    // 1. Check for URLs embedded in text ("Check this out https://...")
    final match = _urlPattern.firstMatch(text);
    if (match != null) {
      // Clean up common trailing punctuation from sharing apps
      return match.group(0)!.replaceFirst(RegExp(r'[)\].,;!?]+$'), '');
    }

    // 2. Local file or content provider path
    if (text.startsWith('/') || text.startsWith('content://') || text.startsWith('file://')) {
      return text;
    }

    // 3. Fallback for raw domains (e.g. "youtube.com/watch...")
    if (text.contains('.') && !text.contains(' ')) {
       return text.startsWith('http') ? text : 'https://$text';
    }

    return null;
  }
}
