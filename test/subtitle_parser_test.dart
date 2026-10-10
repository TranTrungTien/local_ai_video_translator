import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/subtitles/data/subtitle_parser.dart';

void main() {
  const parser = SubtitleParser();

  test('parses WebVTT content with formatting tags', () {
    const vtt = '''
WEBVTT

00:00:01.000 --> 00:00:04.000
<b>Hello</b> world!

00:00:05.500 --> 00:00:08.200
Welcome to <i>Vietnamese</i> translation.
''';

    final segments = parser.parseVtt(vtt, language: 'en');
    expect(segments.length, equals(2));
    expect(segments[0].text, equals('Hello world!'));
    expect(segments[0].start, equals(const Duration(seconds: 1)));
    expect(segments[0].end, equals(const Duration(seconds: 4)));

    expect(segments[1].text, equals('Welcome to Vietnamese translation.'));
    expect(
      segments[1].start,
      equals(const Duration(seconds: 5, milliseconds: 500)),
    );
  });

  test('parses SRT content', () {
    const srt = '''
1
00:00:02,000 --> 00:00:05,000
Long-form anime episode

2
00:00:06,000 --> 00:00:09,500
Local AI translation ready
''';

    final segments = parser.parseSrt(srt, language: 'ja');
    expect(segments.length, equals(2));
    expect(segments[0].text, equals('Long-form anime episode'));
    expect(segments[1].text, equals('Local AI translation ready'));
  });
}
