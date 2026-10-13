import 'ai_pipeline.dart';

class TimelineSubtitleBuffer {
  final List<TimedTextSegment> _segments = [];
  final List<_PendingRange> _pendingSegments = [];
  Duration _vadProgress = Duration.zero;
  Duration _watermark = Duration.zero;

  List<TimedTextSegment> get segments => List.unmodifiable(_segments);

  Duration get subtitleReadyUntil => _watermark;

  void reportProgress(Duration pts, {Duration? activeSpeechStart}) {
    // If activeSpeechStart is set, VAD is currently processing a segment starting there.
    // So we know for sure what happened before activeSpeechStart.
    final certainUntil = activeSpeechStart ?? pts;
    if (certainUntil > _vadProgress) {
      _vadProgress = certainUntil;
    }
    _updateWatermark();
  }

  void registerPendingRange(Duration start, Duration end) {
    _pendingSegments.add(_PendingRange(start, end));
    _updateWatermark();
  }

  void addSegments(List<TimedTextSegment> newSegments, {Duration? metadata}) {
    if (metadata != null) {
      // Remove the pending range that matches the start of these segments
      _pendingSegments.removeWhere((p) => p.start == metadata);
    }
    _segments.addAll(newSegments);
    _segments.sort((a, b) => a.start.compareTo(b.start));
    _updateWatermark();
  }

  void _updateWatermark() {
    // Start from the beginning or where we last were
    Duration current = Duration.zero;

    // Create a combined list of all ranges that "block" or "occupy" time
    final allKnown = [
      ..._segments.map((s) => _TimelineRange(s.start, s.end, isPending: false)),
      ..._pendingSegments.map((p) => _TimelineRange(p.start, p.end, isPending: true)),
    ];
    allKnown.sort((a, b) => a.start.compareTo(b.start));

    for (final range in allKnown) {
      if (range.start > current + const Duration(milliseconds: 100)) {
        // There is a gap. Can we confirm this gap is silence?
        if (range.start > _vadProgress) {
          // No, VAD hasn't reached the end of this gap yet.
          _watermark = current;
          return;
        }
        // Yes, VAD passed this gap and didn't find speech.
        current = range.start;
      }

      if (range.isPending) {
        // We hit a segment that is still being processed by STT/Translation.
        // We must not advance the watermark past its start.
        _watermark = current;
        return;
      }

      // Continuous or overlapping
      if (range.end > current) {
        current = range.end;
      }
    }

    // After all segments, we might have silence until _vadProgress
    if (_vadProgress > current) {
      current = _vadProgress;
    }

    _watermark = current;
  }

  TimedTextSegment? segmentAt(Duration pts) {
    for (final seg in _segments) {
      if (pts >= seg.start && pts <= seg.end) {
        return seg;
      }
    }
    return null;
  }

  /// Prunes obsolete segments older than 60 seconds from current playhead position
  void pruneObsolete(Duration currentPts) {
    final cutoffPts = currentPts - const Duration(seconds: 60);
    if (cutoffPts > Duration.zero) {
      _segments.removeWhere((seg) => seg.end < cutoffPts);
      _pendingSegments.removeWhere((p) => p.end < cutoffPts);
    }
  }

  void flushObsolete(Duration beforePts) {
    _segments.removeWhere((seg) => seg.end < beforePts);
    _pendingSegments.clear();
    _vadProgress = beforePts;
    _updateWatermark();
  }

  void clear() {
    _segments.clear();
    _pendingSegments.clear();
    _vadProgress = Duration.zero;
    _watermark = Duration.zero;
  }
}

class _PendingRange {
  const _PendingRange(this.start, this.end);
  final Duration start;
  final Duration end;
}

class _TimelineRange {
  const _TimelineRange(this.start, this.end, {required this.isPending});
  final Duration start;
  final Duration end;
  final bool isPending;
}
