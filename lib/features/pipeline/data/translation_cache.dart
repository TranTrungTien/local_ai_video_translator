class TranslationCache {
  final Map<String, String> _cache = {};

  int get size => _cache.length;

  String? get(String sourceText) {
    return _cache[sourceText.trim().toLowerCase()];
  }

  void put(String sourceText, String translatedText) {
    _cache[sourceText.trim().toLowerCase()] = translatedText;
  }

  void clear() {
    _cache.clear();
  }
}
