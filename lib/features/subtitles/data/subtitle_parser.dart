import '../../pipeline/domain/ai_pipeline.dart';
import '../domain/entities/subtitle_document.dart';

class SubtitleParser {
  const SubtitleParser();

  List<TimedTextSegment> parseVtt(String content, {String? language}) {
    final doc = parseVttDocument(content, language: language);
    return doc.segments
        .map(
          (s) => TimedTextSegment(
            start: s.start,
            end: s.end,
            text: s.text,
            language: s.language,
          ),
        )
        .toList();
  }

  SubtitleDocument parseVttDocument(String content, {String? language}) {
    final lines = content.split(RegExp(r'\r?\n'));
    final segments = <SubtitleSegment>[];

    Duration? currentStart;
    Duration? currentEnd;
    final textBuffer = StringBuffer();

    final timingRx = RegExp(
      r'(\d{2}:)?(\d{2}):(\d{2})[\.,](\d{3})\s*-->\s*(\d{2}:)?(\d{2}):(\d{2})[\.,](\d{3})',
    );

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (currentStart != null &&
            currentEnd != null &&
            textBuffer.isNotEmpty) {
          final cleanText = _cleanCaptionText(textBuffer.toString());
          if (cleanText.isNotEmpty && currentEnd > currentStart) {
            segments.add(
              SubtitleSegment(
                id: 'vtt_seg_${segments.length}',
                start: currentStart,
                end: currentEnd,
                text: cleanText,
                language: language,
                source: 'WebVTT',
              ),
            );
          }
          currentStart = null;
          currentEnd = null;
          textBuffer.clear();
        }
        continue;
      }

      if (trimmed.startsWith('WEBVTT') ||
          trimmed.startsWith('NOTE') ||
          trimmed.startsWith('STYLE') ||
          trimmed.startsWith('REGION')) {
        continue;
      }

      final match = timingRx.firstMatch(trimmed);
      if (match != null) {
        try {
          currentStart = _parseTimestamp(
            hours: match.group(1),
            minutes: match.group(2)!,
            seconds: match.group(3)!,
            millis: match.group(4)!,
          );
          currentEnd = _parseTimestamp(
            hours: match.group(5),
            minutes: match.group(6)!,
            seconds: match.group(7)!,
            millis: match.group(8)!,
          );
        } catch (_) {
          // Skip malformed timing entry
          currentStart = null;
          currentEnd = null;
        }
      } else if (currentStart != null && currentEnd != null) {
        if (textBuffer.isNotEmpty) textBuffer.write('\n');
        textBuffer.write(trimmed);
      }
    }

    if (currentStart != null && currentEnd != null && textBuffer.isNotEmpty) {
      final cleanText = _cleanCaptionText(textBuffer.toString());
      if (cleanText.isNotEmpty && currentEnd > currentStart) {
        segments.add(
          SubtitleSegment(
            id: 'vtt_seg_${segments.length}',
            start: currentStart,
            end: currentEnd,
            text: cleanText,
            language: language,
            source: 'WebVTT',
          ),
        );
      }
    }

    // Sort and handle overlapping captions gracefully
    segments.sort((a, b) => a.start.compareTo(b.start));

    return SubtitleDocument(
      id: 'vtt_doc_${DateTime.now().millisecondsSinceEpoch}',
      title: 'WebVTT Document',
      language: language ?? 'unknown',
      format: 'WebVTT',
      segments: segments,
    );
  }

  List<TimedTextSegment> parseSrt(String content, {String? language}) {
    final doc = parseSrtDocument(content, language: language);
    return doc.segments
        .map(
          (s) => TimedTextSegment(
            start: s.start,
            end: s.end,
            text: s.text,
            language: s.language,
          ),
        )
        .toList();
  }

  SubtitleDocument parseSrtDocument(String content, {String? language}) {
    final lines = content.split(RegExp(r'\r?\n'));
    final segments = <SubtitleSegment>[];

    Duration? currentStart;
    Duration? currentEnd;
    final textBuffer = StringBuffer();

    final timingRx = RegExp(
      r'(\d{2}):(\d{2}):(\d{2})[\.,](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[\.,](\d{3})',
    );

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (currentStart != null &&
            currentEnd != null &&
            textBuffer.isNotEmpty) {
          final cleanText = _cleanCaptionText(textBuffer.toString());
          if (cleanText.isNotEmpty && currentEnd > currentStart) {
            segments.add(
              SubtitleSegment(
                id: 'srt_seg_${segments.length}',
                start: currentStart,
                end: currentEnd,
                text: cleanText,
                language: language,
                source: 'SRT',
              ),
            );
          }
          currentStart = null;
          currentEnd = null;
          textBuffer.clear();
        }
        continue;
      }

      final match = timingRx.firstMatch(trimmed);
      if (match != null) {
        try {
          currentStart = _parseTimestamp(
            hours: match.group(1),
            minutes: match.group(2)!,
            seconds: match.group(3)!,
            millis: match.group(4)!,
          );
          currentEnd = _parseTimestamp(
            hours: match.group(5),
            minutes: match.group(6)!,
            seconds: match.group(7)!,
            millis: match.group(8)!,
          );
        } catch (_) {
          currentStart = null;
          currentEnd = null;
        }
      } else if (int.tryParse(trimmed) != null && currentStart == null) {
        // SRT sequence index number line
        continue;
      } else if (currentStart != null && currentEnd != null) {
        if (textBuffer.isNotEmpty) textBuffer.write('\n');
        textBuffer.write(trimmed);
      }
    }

    if (currentStart != null && currentEnd != null && textBuffer.isNotEmpty) {
      final cleanText = _cleanCaptionText(textBuffer.toString());
      if (cleanText.isNotEmpty && currentEnd > currentStart) {
        segments.add(
          SubtitleSegment(
            id: 'srt_seg_${segments.length}',
            start: currentStart,
            end: currentEnd,
            text: cleanText,
            language: language,
            source: 'SRT',
          ),
        );
      }
    }

    segments.sort((a, b) => a.start.compareTo(b.start));

    return SubtitleDocument(
      id: 'srt_doc_${DateTime.now().millisecondsSinceEpoch}',
      title: 'SRT Document',
      language: language ?? 'unknown',
      format: 'SRT',
      segments: segments,
    );
  }

  /// Parses TTML (XML-based timed text) format commonly used in DASH manifests.
  SubtitleDocument parseTtmlDocument(String content, {String? language}) {
    final segments = <SubtitleSegment>[];
    try {
      // Simple robust XML <p> element extractor for TTML
      final pRx = RegExp(
        r'<p\s+([^>]*?)>(.*?)<\/p>',
        caseSensitive: false,
        dotAll: true,
      );
      final beginRx = RegExp(r'begin="([^"]+)"', caseSensitive: false);
      final endRx = RegExp(r'end="([^"]+)"', caseSensitive: false);

      for (final match in pRx.allMatches(content)) {
        final attrs = match.group(1) ?? '';
        final rawText = match.group(2) ?? '';

        final beginMatch = beginRx.firstMatch(attrs);
        final endMatch = endRx.firstMatch(attrs);

        if (beginMatch != null && endMatch != null) {
          final start = _parseTtmlTimestamp(beginMatch.group(1)!);
          final end = _parseTtmlTimestamp(endMatch.group(1)!);
          final cleanText = _cleanCaptionText(rawText);

          if (cleanText.isNotEmpty && end > start) {
            segments.add(
              SubtitleSegment(
                id: 'ttml_seg_${segments.length}',
                start: start,
                end: end,
                text: cleanText,
                language: language,
                source: 'TTML',
              ),
            );
          }
        }
      }
    } catch (_) {
      // TTML parsing fallback
    }

    segments.sort((a, b) => a.start.compareTo(b.start));

    return SubtitleDocument(
      id: 'ttml_doc_${DateTime.now().millisecondsSinceEpoch}',
      title: 'TTML Document',
      language: language ?? 'unknown',
      format: 'TTML',
      segments: segments,
    );
  }

  String _cleanCaptionText(String raw) {
    // Strip HTML/WebVTT styling tags (e.g. <b>, <i>, <font>, <v Speaker>, etc.)
    var cleaned = raw.replaceAll(RegExp(r'<[^>]*>'), '');
    // Replace html entities
    cleaned = cleaned
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    // Normalize whitespace / newlines
    cleaned = cleaned.replaceAll(RegExp(r'\r?\n'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.trim();
  }

  Duration _parseTimestamp({
    required String? hours,
    required String minutes,
    required String seconds,
    required String millis,
  }) {
    final h = hours != null ? int.parse(hours.replaceAll(':', '')) : 0;
    final m = int.parse(minutes);
    final s = int.parse(seconds);
    final ms = int.parse(millis);
    return Duration(hours: h, minutes: m, seconds: s, milliseconds: ms);
  }

  Duration _parseTtmlTimestamp(String timeStr) {
    final trimmed = timeStr.trim();
    // Supports clock format HH:MM:SS.mmm or seconds format like 12.34s or 123s
    if (trimmed.endsWith('s')) {
      final secs =
          double.tryParse(trimmed.substring(0, trimmed.length - 1)) ?? 0.0;
      return Duration(milliseconds: (secs * 1000).toInt());
    }

    final parts = trimmed.split(':');
    if (parts.length >= 3) {
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final secParts = parts[2].split('.');
      final s = int.parse(secParts[0]);
      final ms = secParts.length > 1
          ? int.parse(secParts[1].padRight(3, '0').substring(0, 3))
          : 0;
      return Duration(hours: h, minutes: m, seconds: s, milliseconds: ms);
    }

    final secs = double.tryParse(trimmed) ?? 0.0;
    return Duration(milliseconds: (secs * 1000).toInt());
  }
}
