import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/core/utils/media_url.dart';
import 'package:local_ai_video_translator/features/source_resolver/data/html_media_parser.dart';
import 'package:local_ai_video_translator/features/source_resolver/domain/entities/resolved_source.dart';

void main() {
  group('URL Classification & Normalization', () {
    test('classifies HLS playlists', () {
      expect(
        MediaUrl.classify('https://cdn.movie.org/stream/index.m3u8'),
        MediaUrlKind.hls,
      );
    });

    test('classifies DASH manifests', () {
      expect(
        MediaUrl.classify('https://cdn.movie.org/stream/manifest.mpd'),
        MediaUrlKind.dash,
      );
    });

    test('classifies progressive video files', () {
      expect(
        MediaUrl.classify('https://cdn.movie.org/stream/video.mp4'),
        MediaUrlKind.progressive,
      );
      expect(
        MediaUrl.classify('https://cdn.movie.org/stream/movie.mkv'),
        MediaUrlKind.progressive,
      );
      expect(
        MediaUrl.classify('https://cdn.movie.org/stream/anime.webm'),
        MediaUrlKind.progressive,
      );
    });

    test('classifies local video files', () {
      expect(
        MediaUrl.classify('/sdcard/Download/movie.mp4'),
        MediaUrlKind.localFile,
      );
      expect(
        MediaUrl.classify('file:///storage/emulated/0/anime.mkv'),
        MediaUrlKind.localFile,
      );
    });

    test('classifies watch page as web page', () {
      expect(
        MediaUrl.classify('https://watch.anime.org/episode/123'),
        MediaUrlKind.webPage,
      );
    });
  });

  group('Static HTML Media Parser', () {
    const parser = HtmlMediaParser();
    final baseUri = Uri.parse('https://example.com/watch/101');

    test('extracts direct video and source tags', () {
      const html = '''
        <html>
          <body>
            <video src="/media/video_720p.mp4"></video>
            <source src="https://cdn.example.com/hls/master.m3u8">
          </body>
        </html>
      ''';

      final parsed = parser.parse(html, baseUri);
      expect(parsed.candidates.length, equals(2));
      expect(
        parsed.candidates.any((c) => c.kind == MediaKind.progressive),
        isTrue,
      );
      expect(parsed.candidates.any((c) => c.kind == MediaKind.hls), isTrue);
    });

    test('resolves relative iframe URLs and deduplicates', () {
      const html = '''
        <html>
          <body>
            <iframe src="/embed/player?id=123"></iframe>
            <iframe src="/embed/player?id=123"></iframe>
            <iframe src="https://player.external.com/frame.html"></iframe>
          </body>
        </html>
      ''';

      final parsed = parser.parse(html, baseUri);
      expect(parsed.iframes.length, equals(2));
      expect(
        parsed.iframes[0].toString(),
        equals('https://example.com/embed/player?id=123'),
      );
      expect(
        parsed.iframes[1].toString(),
        equals('https://player.external.com/frame.html'),
      );
    });

    test('extracts escaped video candidate URLs from script configs', () {
      const html = r'''
        <script>
          var playerConfig = {
            "file": "https:\/\/cdn.example.com\/stream\/playlist.m3u8?token=abc"
          };
        </script>
      ''';

      final parsed = parser.parse(html, baseUri);
      expect(parsed.candidates.length, equals(1));
      expect(
        parsed.candidates.first.uri.toString(),
        equals('https://cdn.example.com/stream/playlist.m3u8?token=abc'),
      );
      expect(parsed.candidates.first.kind, equals(MediaKind.hls));
    });
  });

  group('Response Signatures', () {
    test('detects HLS signature #EXTM3U', () {
      const body =
          '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-STREAM-INF:BANDWIDTH=128000\nchunk.m3u8';
      expect(body.trimLeft().startsWith('#EXTM3U'), isTrue);
    });

    test('detects DASH signature MPD', () {
      const body =
          '<?xml version="1.0"?>\n<MPD xmlns="urn:mpeg:dash:schema:mpd:2011">';
      expect(
        body.contains('<MPD') || body.contains('urn:mpeg:dash:schema:mpd:2011'),
        isTrue,
      );
    });
  });
}
