import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/source_resolver/data/media_candidate.dart';
import 'package:local_ai_video_translator/features/source_resolver/domain/entities/resolved_source.dart';

void main() {
  test('creates MediaCandidate with correct properties', () {
    final candidate = MediaCandidate(
      uri: Uri.parse('https://example.com/master.m3u8'),
      kind: MediaKind.hls,
      method: DiscoveryMethod.htmlVideo,
      score: 60,
    );

    expect(candidate.kind, equals(MediaKind.hls));
    expect(candidate.score, equals(60));
    expect(candidate.method, equals(DiscoveryMethod.htmlVideo));
  });
}
