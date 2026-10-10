class TtsCache {
  final Map<String, List<int>> _cache = {};

  int get size => _cache.length;

  List<int>? get(String textKey) {
    return _cache[textKey.trim().toLowerCase()];
  }

  void put(String textKey, List<int> audioBytes) {
    _cache[textKey.trim().toLowerCase()] = audioBytes;
  }

  void clear() {
    _cache.clear();
  }
}
