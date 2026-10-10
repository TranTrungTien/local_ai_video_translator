class SubtitleSegment {
  const SubtitleSegment({
    required this.id,
    required this.start,
    required this.end,
    required this.text,
    this.language,
    this.source,
    this.confidence = 1.0,
  });

  final String id;
  final Duration start;
  final Duration end;
  final String text;
  final String? language;
  final String? source;
  final double confidence;
}

class SubtitleDocument {
  const SubtitleDocument({
    required this.id,
    required this.title,
    required this.language,
    required this.format,
    required this.segments,
    this.sourceUri,
    this.confidence = 1.0,
  });

  final String id;
  final String title;
  final String language;
  final String format;
  final List<SubtitleSegment> segments;
  final Uri? sourceUri;
  final double confidence;

  bool get isEmpty => segments.isEmpty;
  bool get isNotEmpty => segments.isNotEmpty;
}
