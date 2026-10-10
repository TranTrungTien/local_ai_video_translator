import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/core/utils/media_url.dart';

void main() {
  test('classifies HLS', () {
    expect(
      MediaUrl.classify('https://cdn.example.com/a/master.m3u8'),
      MediaUrlKind.hls,
    );
  });

  test('classifies DASH', () {
    expect(
      MediaUrl.classify('https://cdn.example.com/a/manifest.mpd'),
      MediaUrlKind.dash,
    );
  });

  test('classifies a watch page as web page', () {
    expect(
      MediaUrl.classify('https://example.com/watch/123'),
      MediaUrlKind.webPage,
    );
  });
}
