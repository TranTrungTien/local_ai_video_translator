enum SubtitleFormat { webvtt, srt, hlsSegment }

class SubtitleTrack {
  const SubtitleTrack({
    required this.id,
    required this.language,
    required this.title,
    required this.uri,
    required this.format,
    this.isTargetLanguage = false,
    this.isOriginal = false,
  });

  final String id;
  final String language;
  final String title;
  final Uri uri;
  final SubtitleFormat format;
  final bool isTargetLanguage;
  final bool isOriginal;
}
