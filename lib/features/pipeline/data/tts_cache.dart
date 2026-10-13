class TtsCache {
  final Map<String, List<int>> _cache = {};
  final List<String> _keys = [];
  final int maxBytes = 50 * 1024 * 1024; // 50MB limit
  int _currentBytes = 0;

  int get size => _cache.length;

  List<int>? get(String textKey) {
    final key = textKey.trim().toLowerCase();
    if (_cache.containsKey(key)) {
      // Move to end for LRU
      _keys.remove(key);
      _keys.add(key);
      return _cache[key];
    }
    return null;
  }

  void put(String textKey, List<int> audioBytes) {
    final key = textKey.trim().toLowerCase();

    if (_cache.containsKey(key)) {
      _currentBytes -= _cache[key]!.length;
      _keys.remove(key);
    }

    // Prune if limit exceeded
    while (_keys.isNotEmpty && _currentBytes + audioBytes.length > maxBytes) {
      final oldKey = _keys.removeAt(0);
      final removed = _cache.remove(oldKey);
      if (removed != null) {
        _currentBytes -= removed.length;
      }
    }

    if (audioBytes.length <= maxBytes) {
      _cache[key] = audioBytes;
      _keys.add(key);
      _currentBytes += audioBytes.length;
    }
  }

  void clear() {
    _cache.clear();
    _keys.clear();
    _currentBytes = 0;
  }
}
