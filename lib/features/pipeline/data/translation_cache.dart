class TranslationCache {
  final Map<String, String> _cache = {};
  final List<String> _keys = [];
  final int maxEntries = 1000;

  int get size => _cache.length;

  String? get(String sourceText) {
    final key = sourceText.trim().toLowerCase();
    if (_cache.containsKey(key)) {
      _keys.remove(key);
      _keys.add(key);
      return _cache[key];
    }
    return null;
  }

  void put(String sourceText, String translatedText) {
    final key = sourceText.trim().toLowerCase();
    if (_cache.containsKey(key)) {
      _keys.remove(key);
    } else if (_keys.length >= maxEntries) {
      final oldKey = _keys.removeAt(0);
      _cache.remove(oldKey);
    }
    _cache[key] = translatedText;
    _keys.add(key);
  }

  void clear() {
    _cache.clear();
    _keys.clear();
  }
}
