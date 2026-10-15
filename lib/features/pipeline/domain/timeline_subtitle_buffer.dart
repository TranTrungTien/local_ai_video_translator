import 'ai_pipeline.dart';

enum TimelineReadinessMode { liveAi, completeSubtitleDocument }

class TimelineSubtitleBuffer {
  final List<TimedTextSegment> _segments = [];
  final List<_PendingRange> _pendingSegments = [];
  Duration _vadProgress = Duration.zero;
  Duration _watermark = Duration.zero;
  Duration _floor = Duration.zero;
  TimelineReadinessMode _mode = TimelineReadinessMode.liveAi;

  List<TimedTextSegment> get segments => List.unmodifiable(_segments);
  Duration get subtitleReadyUntil => _watermark;
  Duration get retainedFrom => _floor;

  void beginLiveAiTimeline({Duration floor = Duration.zero}) {
    _mode = TimelineReadinessMode.liveAi;
    _floor = floor;
    _vadProgress = floor;
    _watermark = floor;
    _segments.removeWhere((s) => s.end < floor);
    _pendingSegments.clear();
    _updateWatermark();
  }

  void markSubtitleDocumentComplete(Duration processedThrough) {
    _mode = TimelineReadinessMode.completeSubtitleDocument;
    if (processedThrough > _watermark) _watermark = processedThrough;
  }

  void reportProgress(Duration pts, {Duration? activeSpeechStart}) {
    if (_mode != TimelineReadinessMode.liveAi) return;
    final certainUntil = activeSpeechStart ?? pts;
    if (certainUntil > _vadProgress) _vadProgress = certainUntil;
    _updateWatermark();
  }

  void registerPendingRange(Duration start, Duration end) {
    if (end <= _floor) return;
    _pendingSegments.add(_PendingRange(start, end));
    _updateWatermark();
  }

  void failPendingRange(Duration start) {
    _pendingSegments.removeWhere((p) => p.start == start);
    _updateWatermark();
  }

  void addSegments(List<TimedTextSegment> newSegments, {Duration? metadata}) {
    if (metadata != null) {
      _pendingSegments.removeWhere((p) => p.start == metadata);
    }
    _segments.addAll(newSegments.where((s) => s.end >= _floor));
    _segments.sort((a, b) => a.start.compareTo(b.start));
    _deduplicate();
    _updateWatermark();
  }

  void _deduplicate() {
    if (_segments.length < 2) return;
    final unique = <TimedTextSegment>[];
    for (final segment in _segments) {
      if (unique.isNotEmpty) {
        final previous = unique.last;
        if (previous.start == segment.start &&
            previous.end == segment.end &&
            previous.text == segment.text) {
          continue;
        }
      }
      unique.add(segment);
    }
    _segments
      ..clear()
      ..addAll(unique);
  }

  void _updateWatermark() {
    if (_mode == TimelineReadinessMode.completeSubtitleDocument) {
      // Document readiness is not derived from cue gaps. A valid subtitle file
      // naturally contains silent gaps between cues.
      if (_watermark < _floor) _watermark = _floor;
      return;
    }

    var current = _floor;
    final allKnown = <_TimelineRange>[
      ..._segments.map((s) => _TimelineRange(s.start, s.end, isPending: false)),
      ..._pendingSegments.map((p) => _TimelineRange(p.start, p.end, isPending: true)),
    ]..sort((a, b) => a.start.compareTo(b.start));

    for (final range in allKnown) {
      if (range.end <= current) continue;

      // If there's a gap larger than 100ms, we check if VAD has cleared this gap.
      if (range.start > current + const Duration(milliseconds: 100)) {
        if (range.start > _vadProgress) {
          // VAD hasn't reached the next segment yet, so we're only sure until 'current'.
          _watermark = current;
          return;
        }
        // VAD cleared the gap, move 'current' to start of this range.
        current = range.start;
      }

      if (range.isPending) {
        // We hit a segment that is still being processed.
        _watermark = current;
        return;
      }

      if (range.end > current) current = range.end;
    }

    if (_vadProgress > current) current = _vadProgress;
    if (current > _watermark || _watermark < _floor) _watermark = current;
  }

  TimedTextSegment? segmentAt(Duration pts) {
    // Retained window is bounded, so a linear lookup remains inexpensive.
    for (final seg in _segments) {
      if (pts >= seg.start && pts <= seg.end) return seg;
    }
    return null;
  }

  void pruneObsolete(Duration currentPts) {
    final cutoff = currentPts - const Duration(seconds: 60);
    if (cutoff <= _floor) return;
    _floor = cutoff;
    _segments.removeWhere((seg) => seg.end < cutoff);
    _pendingSegments.removeWhere((p) => p.end < cutoff);
    if (_vadProgress < _floor) _vadProgress = _floor;
    if (_watermark < _floor) _watermark = _floor;
    _updateWatermark();
  }

  void flushObsolete(Duration beforePts) {
    _floor = beforePts;
    _segments.removeWhere((seg) => seg.end < beforePts);
    _pendingSegments.clear();
    _vadProgress = beforePts;
    _watermark = beforePts;
    _mode = TimelineReadinessMode.liveAi;
    _updateWatermark();
  }

  void clear() {
    _segments.clear();
    _pendingSegments.clear();
    _vadProgress = Duration.zero;
    _watermark = Duration.zero;
    _floor = Duration.zero;
    _mode = TimelineReadinessMode.liveAi;
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
