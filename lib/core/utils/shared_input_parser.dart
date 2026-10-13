/// Tiện ích phân tách URL http(s) hoặc đường dẫn tệp cục bộ từ input của người dùng.
abstract final class SharedInputParser {
  /// Pattern URL tập trung vào http/https với xác thực host cơ bản.
  /// Loại bỏ các ký tự dấu câu thừa ở cuối chuỗi thường gặp khi dán link.
  static final RegExp _urlPattern = RegExp(
    r'https?://(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
    caseSensitive: false,
  );

  /// Whitelist of allowed schemes for local/content files.
  static const _allowedLocalSchemes = ['content://', 'file://'];

  /// Returns the first usable source, or null if none found.
  static String? extract(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    // 1. Check for URLs embedded in text ("Check this out https://...")
    final match = _urlPattern.firstMatch(text);
    if (match != null) {
      final url = match.group(0)!;
      // Clean up common trailing punctuation from sharing apps if the regex missed it
      return url.replaceFirst(RegExp(r'[)\].,;!?]+$'), '');
    }

    // 2. Local file or content provider path
    for (final scheme in _allowedLocalSchemes) {
      if (text.startsWith(scheme)) {
        return text;
      }
    }

    // Support absolute Unix-style paths (common in Android/Linux)
    if (text.startsWith('/')) {
      return text;
    }

    // 3. Fallback for raw domains (e.g. "youtube.com/watch...")
    // Only if it looks like a domain and has no spaces (strict validation)
    if (RegExp(r'^(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&//=]*)$').hasMatch(text)) {
       return 'https://$text';
    }

    return null;
  }
}
