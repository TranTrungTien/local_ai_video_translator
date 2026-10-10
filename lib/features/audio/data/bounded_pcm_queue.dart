import 'dart:collection';
import '../../pipeline/domain/ai_pipeline.dart';

class BoundedPcmQueue {
  BoundedPcmQueue({this.maxCapacity = 100});

  final int maxCapacity;
  final Queue<PcmChunk> _queue = Queue<PcmChunk>();

  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  bool get isFull => _queue.length >= maxCapacity;

  void enqueue(PcmChunk chunk) {
    if (isFull) {
      // Drop oldest chunk to apply backpressure & prevent unlimited memory accumulation
      _queue.removeFirst();
    }
    _queue.add(chunk);
  }

  PcmChunk? dequeue() {
    if (_queue.isEmpty) return null;
    return _queue.removeFirst();
  }

  void clearBefore(Duration pts) {
    _queue.removeWhere(
      (chunk) => chunk.pts + const Duration(milliseconds: 500) < pts,
    );
  }

  void clear() {
    _queue.clear();
  }

  Duration get queuedAudioDuration {
    if (_queue.isEmpty) return Duration.zero;
    final first = _queue.first.pts;
    final last = _queue.last.pts + const Duration(milliseconds: 500);
    return last > first ? last - first : Duration.zero;
  }

  int get approximateMemoryBytes {
    int total = 0;
    for (final chunk in _queue) {
      total += chunk.bytes.length;
    }
    return total;
  }
}
