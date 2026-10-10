import '../domain/entities/subtitle_track.dart';

enum SubtitleSelectionDecision { directVi, translateExisting, sttRequired }

class SubtitleSelectionResult {
  const SubtitleSelectionResult({
    required this.decision,
    this.selectedTrack,
    required this.reason,
  });

  final SubtitleSelectionDecision decision;
  final SubtitleTrack? selectedTrack;
  final String reason;

  bool get isDirectVi => decision == SubtitleSelectionDecision.directVi;
  bool get isTranslateExisting =>
      decision == SubtitleSelectionDecision.translateExisting;
  bool get isSttRequired => decision == SubtitleSelectionDecision.sttRequired;
}

class SubtitleSelectionPolicy {
  const SubtitleSelectionPolicy();

  SubtitleSelectionResult evaluate(List<SubtitleTrack> availableTracks) {
    if (availableTracks.isEmpty) {
      return const SubtitleSelectionResult(
        decision: SubtitleSelectionDecision.sttRequired,
        reason:
            'No subtitle tracks discovered. Speech-to-Text (STT) is required.',
      );
    }

    // Priority 1: Vietnamese subtitle -> use directly
    final viTrack = availableTracks
        .where(
          (t) =>
              t.isTargetLanguage ||
              t.language.toLowerCase() == 'vi' ||
              t.language.toLowerCase() == 'vietnamese',
        )
        .firstOrNull;

    if (viTrack != null) {
      return SubtitleSelectionResult(
        decision: SubtitleSelectionDecision.directVi,
        selectedTrack: viTrack,
        reason:
            'Found Vietnamese subtitle track [${viTrack.id}]. Using directly.',
      );
    }

    // Priority 2: Source-language / Foreign subtitle -> translate later
    final foreignTrack = availableTracks.firstOrNull;
    if (foreignTrack != null) {
      return SubtitleSelectionResult(
        decision: SubtitleSelectionDecision.translateExisting,
        selectedTrack: foreignTrack,
        reason:
            'Found foreign subtitle track [${foreignTrack.id}, lang: ${foreignTrack.language}]. Translating existing.',
      );
    }

    return const SubtitleSelectionResult(
      decision: SubtitleSelectionDecision.sttRequired,
      reason:
          'No useful subtitle tracks available. Speech-to-Text (STT) required.',
    );
  }
}
