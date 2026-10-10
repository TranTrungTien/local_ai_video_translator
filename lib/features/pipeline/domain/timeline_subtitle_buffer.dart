import 'ai_pipeline.dart';

class TimelineSubtitleBuffer {
  final List<TimedTextSegment> _segments = [];

  List<TimedTextSegment> get segments => List.unmodifiable(_segments);

  Duration get subtitleReadyUntil {
    if (_segments.isEmpty) return Duration.zero;
    return _segments.last.end;
  }

  void addSegments(List<TimedTextSegment> newSegments) {
    _segments.addAll(newSegments);
    _segments.sort((a, b) => a.start.compareTo(b.start));
  }

  TimedTextSegment? segmentAt(Duration pts) {
    for (final seg in _segments) {
      if (pts >= seg.start && pts <= seg.end) {
        return seg;
      }
    }
    return null;
  }

  void flushObsolete(Duration beforePts) {
    _segments.removeWhere((seg) => seg.end < beforePts);
  }

  void clear() {
    _segments.clear();
  }
}
