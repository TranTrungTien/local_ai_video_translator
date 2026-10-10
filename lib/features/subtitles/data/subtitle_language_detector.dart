class SubtitleLanguageDetector {
  const SubtitleLanguageDetector();

  /// Detects or normalizes language code from metadata or text content heuristic.
  String detectLanguage({String? declaredLanguage, String? sampleText}) {
    if (declaredLanguage != null && declaredLanguage.trim().isNotEmpty) {
      final normalized = declaredLanguage.toLowerCase().trim();
      if (normalized.startsWith('vi') || normalized.contains('vietnamese')) {
        return 'vi';
      }
      if (normalized.startsWith('en') || normalized.contains('english')) {
        return 'en';
      }
      if (normalized.startsWith('ja') || normalized.contains('japanese')) {
        return 'ja';
      }
      if (normalized.startsWith('zh') || normalized.contains('chinese')) {
        return 'zh';
      }
      return normalized;
    }

    if (sampleText != null && sampleText.trim().isNotEmpty) {
      return _heuristicDetect(sampleText);
    }

    return 'unknown';
  }

  String _heuristicDetect(String text) {
    // Vietnamese diacritics check
    final vietnameseDiacriticsRx = RegExp(
      r'[ăâđêôơưàằầằắấẫẩẳẵẳằằặặẹẻẽéèẻẽếềểễệỉĩíìịọỏõóòỏõốồổỗộớờởỡợụủũúùủũứừửữựỳỷỹýỵ]',
      caseSensitive: false,
    );

    if (vietnameseDiacriticsRx.hasMatch(text)) {
      return 'vi';
    }

    // Default fallback assumption for foreign sample text
    return 'en';
  }
}
