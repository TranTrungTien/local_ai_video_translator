import 'dart:typed_data';
import '../../../core/utils/cancellation_token.dart';

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
    this.playbackSessionId = '',
    this.timelineEpoch = 0,
    this.seekGeneration = 0,
  });
  final Duration pts;
  final int sampleRate;
  final int channels;
  final Uint8List bytes;
  final String playbackSessionId;
  final int timelineEpoch;
  final int seekGeneration;
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
    CancellationToken? cancellationToken,
  });
}

abstract interface class TextToSpeechEngine {
  bool get installed;
  Future<Uint8List> synthesize(String text, {required Duration targetDuration});
  Future<Uint8List> synthesizeWithCancellation(
    String text, {
    required Duration targetDuration,
    required CancellationToken cancellationToken,
  });
}
