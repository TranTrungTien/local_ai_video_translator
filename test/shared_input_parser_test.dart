import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/core/utils/shared_input_parser.dart';

void main() {
  group('SharedInputParser', () {
    test('extracts clean URL from text', () {
      expect(
        SharedInputParser.extract('Check this out: https://example.com/video.mp4'),
        'https://example.com/video.mp4',
      );
    });

    test('trims trailing punctuation from URL', () {
      expect(
        SharedInputParser.extract('Watch here https://example.com/video.mp4!!!'),
        'https://example.com/video.mp4',
      );
      expect(
        SharedInputParser.extract('(https://example.com/video.mp4)'),
        'https://example.com/video.mp4',
      );
    });

    test('extracts local file paths', () {
      expect(
        SharedInputParser.extract('/storage/emulated/0/Download/video.mp4'),
        '/storage/emulated/0/Download/video.mp4',
      );
      expect(
        SharedInputParser.extract('file:///data/user/0/com.app/video.mkv'),
        'file:///data/user/0/com.app/video.mkv',
      );
      expect(
        SharedInputParser.extract('content://media/external/video/media/123'),
        'content://media/external/video/media/123',
      );
    });

    test('handles raw domains with fallback to https', () {
      expect(SharedInputParser.extract('youtube.com/watch?v=123'), 'https://youtube.com/watch?v=123');
      expect(SharedInputParser.extract('www.example.com'), 'https://www.example.com');
    });

    test('rejects invalid or unsafe inputs', () {
      expect(SharedInputParser.extract('just some random text'), isNull);
      expect(SharedInputParser.extract('ftp://unsafe.site/file'), isNull);
      expect(SharedInputParser.extract(''), isNull);
      expect(SharedInputParser.extract('  '), isNull);
    });

    test('strict domain validation in fallback', () {
      // Should not fallback if there are spaces
      expect(SharedInputParser.extract('example .com'), isNull);
      // Should not fallback if it's just a string without dots
      expect(SharedInputParser.extract('localhost'), isNull);
    });
  });
}
