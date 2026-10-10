import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/subtitles/data/subtitle_language_detector.dart';
import 'package:local_ai_video_translator/features/subtitles/data/subtitle_parser.dart';
import 'package:local_ai_video_translator/features/subtitles/domain/entities/subtitle_track.dart';
import 'package:local_ai_video_translator/features/subtitles/domain/subtitle_selection_policy.dart';

void main() {
  const parser = SubtitleParser();
  const languageDetector = SubtitleLanguageDetector();
  const selectionPolicy = SubtitleSelectionPolicy();

  group('Phase 3: Subtitle Parser & Normalization Tests', () {
    test(
      'parses WebVTT with multiline, empty lines, unicode Vietnamese, and long lines',
      () {
        const vtt = '''
WEBVTT

NOTE
This is a comment note that should be ignored.

00:00:01.000 --> 00:00:04.000
Xin chào các bạn, đây là phụ đề tiếng Việt
với nhiều dòng (multiline).

00:00:03.500 --> 00:00:07.000
Overlapping caption segment with very long line exceeding standard limits for subtitle presentation testing purposes.

00:00:08.000 --> 00:00:10.000
   
''';

        final doc = parser.parseVttDocument(vtt, language: 'vi');
        expect(doc.segments.length, equals(2));
        expect(doc.segments[0].text, contains('Xin chào các bạn'));
        expect(doc.segments[0].text, contains('với nhiều dòng'));
        expect(doc.segments[1].text, contains('Overlapping caption segment'));
        expect(doc.segments[0].start, equals(const Duration(seconds: 1)));
        expect(
          doc.segments[1].start,
          equals(const Duration(milliseconds: 3500)),
        );
      },
    );

    test('handles malformed timestamp entries gracefully without crashing', () {
      const malformedVtt = '''
WEBVTT

00:60:00.000 --> invalid_timestamp
Malformed line here

00:00:05.000 --> 00:00:08.000
Valid caption after malformed entry
''';

      final doc = parser.parseVttDocument(malformedVtt);
      expect(doc.segments.length, equals(1));
      expect(
        doc.segments[0].text,
        equals('Valid caption after malformed entry'),
      );
    });

    test('parses TTML XML timed text documents', () {
      const ttml = '''
<tt xml:lang="en">
  <body>
    <div>
      <p begin="00:00:02.500" end="00:00:05.000">English DASH TTML caption line</p>
      <p begin="00:00:06.000" end="00:00:09.500">Second TTML caption entry</p>
    </div>
  </body>
</tt>
''';

      final doc = parser.parseTtmlDocument(ttml, language: 'en');
      expect(doc.segments.length, equals(2));
      expect(doc.segments[0].text, equals('English DASH TTML caption line'));
      expect(
        doc.segments[0].start,
        equals(const Duration(seconds: 2, milliseconds: 500)),
      );
    });
  });

  group('Phase 3: Subtitle Language Detection Tests', () {
    test('detects language from declared metadata or diacritics heuristic', () {
      expect(
        languageDetector.detectLanguage(declaredLanguage: 'vi'),
        equals('vi'),
      );
      expect(
        languageDetector.detectLanguage(declaredLanguage: 'Vietnamese'),
        equals('vi'),
      );
      expect(
        languageDetector.detectLanguage(declaredLanguage: 'en'),
        equals('en'),
      );

      final sampleVi = 'Bộ phim hoạt hình tuyệt vời tiếng Việt';
      expect(
        languageDetector.detectLanguage(sampleText: sampleVi),
        equals('vi'),
      );
    });
  });

  group('Phase 3: Subtitle Selection Policy Tests', () {
    test('selects DIRECT_VI when Vietnamese subtitle track is available', () {
      final tracks = [
        SubtitleTrack(
          id: 'sub_en',
          language: 'en',
          title: 'English Track',
          uri: Uri.parse('https://example.com/en.vtt'),
          format: SubtitleFormat.webvtt,
        ),
        SubtitleTrack(
          id: 'sub_vi',
          language: 'vi',
          title: 'Vietnamese Track',
          uri: Uri.parse('https://example.com/vi.vtt'),
          format: SubtitleFormat.webvtt,
          isTargetLanguage: true,
        ),
      ];

      final result = selectionPolicy.evaluate(tracks);
      expect(result.decision, equals(SubtitleSelectionDecision.directVi));
      expect(result.selectedTrack?.id, equals('sub_vi'));
      expect(result.isDirectVi, isTrue);
    });

    test(
      'selects TRANSLATE_EXISTING when only foreign subtitle is available',
      () {
        final tracks = [
          SubtitleTrack(
            id: 'sub_ja',
            language: 'ja',
            title: 'Japanese Original',
            uri: Uri.parse('https://example.com/ja.vtt'),
            format: SubtitleFormat.webvtt,
          ),
        ];

        final result = selectionPolicy.evaluate(tracks);
        expect(
          result.decision,
          equals(SubtitleSelectionDecision.translateExisting),
        );
        expect(result.selectedTrack?.id, equals('sub_ja'));
        expect(result.isTranslateExisting, isTrue);
      },
    );

    test('selects STT_REQUIRED when no subtitle tracks are present', () {
      final result = selectionPolicy.evaluate([]);
      expect(result.decision, equals(SubtitleSelectionDecision.sttRequired));
      expect(result.isSttRequired, isTrue);
    });
  });
}
