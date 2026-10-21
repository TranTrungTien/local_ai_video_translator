import '../../../core/diagnostics/diagnostics_service.dart';
import 'ai_pipeline.dart';

enum TimelineReadinessMode { liveAi, completeSubtitleDocument }

class TimelineSubtitleBuffer {
  TimelineSubtitleBuffer(this._diagnostics);

  final DiagnosticsService _diagnostics;
  final List<TimedTextSegment> _segments = [];
  final List<_PendingRange> _pendingSegments = [];
  Duration _vadProgress = Duration.zero;
  Duration _watermark = Duration.zero;
  Duration _floor = Duration.zero;
  TimelineReadinessMode _mode = TimelineReadinessMode.liveAi;

  List<TimedTextSegment> get segments => List.unmodifiable(_segments);
  Duration get subtitleReadyUntil => _watermark;
  Duration get retainedFrom => _floor;
  TimedTextSegment? get lastProcessedSegment => _segments.isNotEmpty ? _segments.last : null;

  void beginLiveAiTimeline({Duration floor = Duration.zero}) {
    _mode = TimelineReadinessMode.liveAi;
    _floor = floor;
    _vadProgress = floor;
    _watermark = floor;
    // Tắt việc xóa segment để giữ lịch sử phục vụ export SRT
    // _segments.removeWhere((s) => s.end < floor);
    _pendingSegments.clear();
    _updateWatermark();
  }

  void markSubtitleDocumentComplete(Duration processedThrough) {
    _mode = TimelineReadinessMode.completeSubtitleDocument;
    if (processedThrough > _watermark) _watermark = processedThrough;
  }

  void reportProgress(Duration pts, {Duration? activeSpeechStart}) {
    if (_mode != TimelineReadinessMode.liveAi) return;
    // Cập nhật tiến độ VAD. Ngay cả khi không có tiếng, watermark vẫn có thể tiến tới pts
    if (pts > _vadProgress) {
      _vadProgress = pts;
    }
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
    // metadata chính là 'start' của pending range, cần xóa nó để watermark có thể tiến tiếp
    if (metadata != null) {
      _pendingSegments.removeWhere((p) => p.start == metadata);
    }

    if (newSegments.isNotEmpty) {
      for (var s in newSegments) {
        _diagnostics.log('SUB_BUFFER', 'Adding segment: [${s.start.inMilliseconds}ms - ${s.end.inMilliseconds}ms] "${s.text}"');
      }
    }
    _segments.addAll(newSegments.where((s) => s.end >= _floor));
    _segments.sort((a, b) => a.start.compareTo(b.start));
    _fixOverlaps();
    _deduplicate();
    _updateWatermark();
  }

  void _fixOverlaps() {
    if (_segments.length < 2) return;
    for (int i = 0; i < _segments.length - 1; i++) {
      final current = _segments[i];
      final next = _segments[i + 1];

      // Nếu segment hiện tại kết thúc sau khi segment tiếp theo bắt đầu
      if (current.end > next.start) {
        // Thu ngắn segment hiện tại lại, chừa ra 50ms nghỉ
        final newEnd = next.start - const Duration(milliseconds: 50);

        // Cập nhật lại segment (do TimedTextSegment là immutable nên phải tạo mới)
        _segments[i] = TimedTextSegment(
          start: current.start,
          end: newEnd > current.start ? newEnd : current.start + const Duration(milliseconds: 100),
          text: current.text,
          language: current.language,
        );
      }
    }
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
    _diagnostics.log('SUB_BUFFER', 'Total segments in buffer: ${_segments.length}, watermark: ${_watermark.inMilliseconds}ms');
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

      // Nếu có khoảng trống (gap), kiểm tra xem VAD đã quét qua chưa
      if (range.start > current + const Duration(milliseconds: 10)) {
        if (_vadProgress > current) {
          // VAD đã quét qua một phần hoặc toàn bộ khoảng trống
          final clearedUntil = range.start < _vadProgress ? range.start : _vadProgress;
          current = clearedUntil;

          if (current < range.start) {
            // VAD chưa quét hết khoảng trống tới segment tiếp theo
            _watermark = current;
            return;
          }
        } else {
          // VAD chưa đạt tới mốc 'current', kẹt tại đây
          _watermark = current;
          return;
        }
      }

      if (range.isPending) {
        // Gặp segment đang xử lý, dừng watermark tại đây
        _watermark = current;
        return;
      }

      if (range.end > current) current = range.end;
    }

    if (_vadProgress > current) current = _vadProgress;
    if (current > _watermark || _watermark < _floor) _watermark = current;
  }

  TimedTextSegment? segmentAt(Duration pts) {
    // Linear search is fine for small buffers, but let's ensure it's not missing matches
    for (final seg in _segments) {
      if (pts >= seg.start && pts <= seg.end) {
        return seg;
      }
    }
    return null;
  }

  void pruneObsolete(Duration currentPts) {
    final cutoff = currentPts - const Duration(seconds: 60);
    if (cutoff <= _floor) return;
    _floor = cutoff;
    // Tắt việc xóa segment để giữ lịch sử phục vụ export SRT
    // _segments.removeWhere((seg) => seg.end < cutoff);
    _pendingSegments.removeWhere((p) => p.end < cutoff);
    if (_vadProgress < _floor) _vadProgress = _floor;
    if (_watermark < _floor) _watermark = _floor;
    _updateWatermark();
  }

  void handleSeek(Duration newPts) {
    _pendingSegments.clear();
    // Remove segments that overlap or are after the seek point to avoid "ghosts"
    // when we re-process this area.
    _segments.removeWhere((seg) => seg.end > newPts);

    // Reset or advance VAD progress to the seek point.
    // This allows the watermark to jump to the newPts even if there's a gap behind it,
    // because _updateWatermark will see that VAD has "cleared" up to newPts.
    _vadProgress = newPts;

    // If we seek back before our current floor, we must expand the floor to ensure
    // we track the timeline correctly from the new start point.
    if (newPts < _floor) {
      _floor = newPts;
    }

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
