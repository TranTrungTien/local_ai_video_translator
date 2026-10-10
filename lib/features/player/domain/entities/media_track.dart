enum SubtitleClassification { vietnamese, sourceLanguage, unknownOther }

class VideoTrack {
  const VideoTrack({
    required this.id,
    required this.label,
    this.language,
    this.width,
    this.height,
    this.bitrate,
    this.codec,
    this.isSelected = false,
  });

  final String id;
  final String label;
  final String? language;
  final int? width;
  final int? height;
  final int? bitrate;
  final String? codec;
  final bool isSelected;

  VideoTrack copyWith({bool? isSelected}) {
    return VideoTrack(
      id: id,
      label: label,
      language: language,
      width: width,
      height: height,
      bitrate: bitrate,
      codec: codec,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.label,
    this.language,
    this.channels,
    this.sampleRate,
    this.codec,
    this.isSelected = false,
    this.isDefault = false,
  });

  final String id;
  final String label;
  final String? language;
  final int? channels;
  final int? sampleRate;
  final String? codec;
  final bool isSelected;
  final bool isDefault;

  AudioTrack copyWith({bool? isSelected}) {
    return AudioTrack(
      id: id,
      label: label,
      language: language,
      channels: channels,
      sampleRate: sampleRate,
      codec: codec,
      isSelected: isSelected ?? this.isSelected,
      isDefault: isDefault,
    );
  }
}

class PlayerSubtitleTrack {
  const PlayerSubtitleTrack({
    required this.id,
    required this.label,
    required this.language,
    this.format,
    this.uri,
    this.isEmbedded = false,
    this.isSelected = false,
    required this.classification,
  });

  final String id;
  final String label;
  final String language;
  final String? format;
  final Uri? uri;
  final bool isEmbedded;
  final bool isSelected;
  final SubtitleClassification classification;

  static SubtitleClassification classify(String lang) {
    final lower = lang.toLowerCase().trim();
    if (lower == 'vi' || lower == 'vietnamese' || lower == 'vie') {
      return SubtitleClassification.vietnamese;
    }
    if (lower == 'en' ||
        lower == 'english' ||
        lower == 'ja' ||
        lower == 'japanese' ||
        lower == 'zh' ||
        lower == 'chinese') {
      return SubtitleClassification.sourceLanguage;
    }
    return SubtitleClassification.unknownOther;
  }

  PlayerSubtitleTrack copyWith({bool? isSelected}) {
    return PlayerSubtitleTrack(
      id: id,
      label: label,
      language: language,
      format: format,
      uri: uri,
      isEmbedded: isEmbedded,
      isSelected: isSelected ?? this.isSelected,
      classification: classification,
    );
  }
}

class MediaTrackSet {
  const MediaTrackSet({
    this.videoTracks = const [],
    this.audioTracks = const [],
    this.subtitleTracks = const [],
  });

  final List<VideoTrack> videoTracks;
  final List<AudioTrack> audioTracks;
  final List<PlayerSubtitleTrack> subtitleTracks;

  static const empty = MediaTrackSet();
}
