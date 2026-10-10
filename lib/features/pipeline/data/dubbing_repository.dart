import 'dart:async';
import '../domain/dub_segment.dart';

class DubbingRepository {
  final Map<Duration, DubSegment> _segments = {};
  final StreamController<DubSegment> _controller = StreamController.broadcast();

  Stream<DubSegment> get dubStream => _controller.stream;

  void addSegment(DubSegment segment) {
    _segments[segment.startPts] = segment;
    _controller.add(segment);
  }

  DubSegment? getSegmentAt(Duration pts) {
    // Tìm segment gần nhất với pts hiện tại
    for (final entry in _segments.entries) {
      if (pts >= entry.key && pts < entry.value.endPts) {
        return entry.value;
      }
    }
    return null;
  }

  Duration get dubReadyUntil {
    if (_segments.isEmpty) return Duration.zero;
    return _segments.values.map((e) => e.endPts).reduce((a, b) => a > b ? a : b);
  }

  void clear() {
    _segments.clear();
  }
}
