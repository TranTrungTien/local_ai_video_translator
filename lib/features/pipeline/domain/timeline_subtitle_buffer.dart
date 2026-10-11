import 'ai_pipeline.dart';

class TimelineSubtitleBuffer {
  final List<TimedTextSegment> _segments = [];
  Duration _processedUntil = Duration.zero;

  List<TimedTextSegment> get segments => List.unmodifiable(_segments);

  Duration get subtitleReadyUntil {
    final lastSegmentEnd =
        _segments.isEmpty ? Duration.zero : _segments.last.end;
    return lastSegmentEnd > _processedUntil ? lastSegmentEnd : _processedUntil;
  }

  void reportProgress(Duration pts) {
    if (pts > _processedUntil) {
      _processedUntil = pts;
    }
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
    if (beforePts > _processedUntil) {
      _processedUntil = beforePts;
    }
  }

  void clear() {
    _segments.clear();
    _processedUntil = Duration.zero;
  }
}
