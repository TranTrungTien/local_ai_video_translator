import 'dart:async';
import '../domain/dub_segment.dart';

class DubbingRepository {
  final Map<Duration, DubSegment> _segments = {};
  final StreamController<DubSegment> _controller = StreamController.broadcast();
  final StreamController<String?> _activeIdController = StreamController.broadcast();

  Stream<DubSegment> get dubStream => _controller.stream;
  Stream<String?> get activeIdStream => _activeIdController.stream;

  String? _lastActiveId;

  void addSegment(DubSegment segment) {
    _segments[segment.startPts] = segment;
    _controller.add(segment);
  }

  void markAsActive(String? id) {
    if (_lastActiveId == id) return;
    _lastActiveId = id;
    _activeIdController.add(id);
  }

  DubSegment? getSegmentAt(Duration pts) {
    // Tìm segment gần nhất với pts hiện tại
    DubSegment? found;
    for (final entry in _segments.entries) {
      if (pts >= entry.key && pts < entry.value.endPts) {
        found = entry.value;
        break;
      }
    }
    
    if (found == null && _lastActiveId != null) {
      markAsActive(null);
    }
    
    return found;
  }

  Duration get dubReadyUntil {
    if (_segments.isEmpty) return Duration.zero;
    return _segments.values.map((e) => e.endPts).reduce((a, b) => a > b ? a : b);
  }

  void clear() {
    _segments.clear();
  }
}
