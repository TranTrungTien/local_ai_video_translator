import '../../../source_resolver/domain/entities/resolved_source.dart';
import '../../../pipeline/domain/ai_pipeline.dart';
import '../entities/subtitle_track.dart';

abstract interface class SubtitleRepository {
  Future<List<SubtitleTrack>> findSubtitleTracks(ResolvedSource source);
  Future<List<TimedTextSegment>> fetchSubtitleSegments(SubtitleTrack track);
  Future<List<TimedTextSegment>> findExistingSubtitles(String targetLanguage);
}

abstract interface class SubtitleTrackProvider {
  Future<List<SubtitleTrack>> findSubtitleTracks(ResolvedSource source);
}
