class DubSegment {
  const DubSegment({
    required this.id,
    required this.startPts,
    required this.endPts,
    required this.sourceText,
    required this.translatedText,
    required this.generatedAudio,
    required this.generatedDuration,
    required this.targetDuration,
    required this.voiceId,
    this.speakerId,
    required this.modelVersion,
  });

  final String id;
  final Duration startPts;
  final Duration endPts;
  final String sourceText;
  final String translatedText;
  final List<int> generatedAudio;
  final Duration generatedDuration;
  final Duration targetDuration;
  final String voiceId;
  final String? speakerId;
  final String modelVersion;

  bool get isDurationFitted =>
      generatedDuration <= targetDuration + const Duration(milliseconds: 200);
}
