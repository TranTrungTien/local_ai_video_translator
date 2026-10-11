class TimedTextSegment {
  const TimedTextSegment({
    required this.start,
    required this.end,
    required this.text,
    this.language,
  });
  final Duration start;
  final Duration end;
  final String text;
  final String? language;
}

class PcmChunk {
  const PcmChunk({
    required this.pts,
    required this.sampleRate,
    required this.channels,
    required this.bytes,
  });
  final Duration pts;
  final int sampleRate;
  final int channels;
  final Uint8List bytes;
}

abstract interface class SpeechToTextEngine {
  bool get installed;
  Future<List<TimedTextSegment>> transcribe(Stream<PcmChunk> audio);
  Future<List<TimedTextSegment>> transcribeWithCancellation(
    Stream<PcmChunk> audio, {
    required CancellationToken cancellationToken,
  });
}

abstract interface class TranslationEngine {
  bool get installed;
  Future<List<TimedTextSegment>> translate(
    List<TimedTextSegment> segments, {
    required String targetLanguage,
  });
}

abstract interface class TextToSpeechEngine {
  bool get installed;
  Future<Uint8List> synthesize(String text, {required Duration targetDuration});
}
