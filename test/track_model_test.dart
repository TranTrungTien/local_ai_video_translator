import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/player/domain/entities/media_track.dart';

void main() {
  group('Media Track Classification Tests', () {
    test('classifies Vietnamese language subtitle tracks', () {
      expect(
        PlayerSubtitleTrack.classify('vi'),
        equals(SubtitleClassification.vietnamese),
      );
      expect(
        PlayerSubtitleTrack.classify('vietnamese'),
        equals(SubtitleClassification.vietnamese),
      );
      expect(
        PlayerSubtitleTrack.classify('VIE'),
        equals(SubtitleClassification.vietnamese),
      );
    });

    test('classifies source language subtitle tracks', () {
      expect(
        PlayerSubtitleTrack.classify('en'),
        equals(SubtitleClassification.sourceLanguage),
      );
      expect(
        PlayerSubtitleTrack.classify('english'),
        equals(SubtitleClassification.sourceLanguage),
      );
      expect(
        PlayerSubtitleTrack.classify('ja'),
        equals(SubtitleClassification.sourceLanguage),
      );
      expect(
        PlayerSubtitleTrack.classify('japanese'),
        equals(SubtitleClassification.sourceLanguage),
      );
      expect(
        PlayerSubtitleTrack.classify('zh'),
        equals(SubtitleClassification.sourceLanguage),
      );
    });

    test('classifies unknown language subtitle tracks', () {
      expect(
        PlayerSubtitleTrack.classify('fr'),
        equals(SubtitleClassification.unknownOther),
      );
      expect(
        PlayerSubtitleTrack.classify('es'),
        equals(SubtitleClassification.unknownOther),
      );
      expect(
        PlayerSubtitleTrack.classify('unknown'),
        equals(SubtitleClassification.unknownOther),
      );
    });

    test('supports multiple audio tracks without assuming dialogue track', () {
      const track1 = AudioTrack(
        id: 'a1',
        label: 'Audio 1 (Background Music)',
        language: 'en',
        channels: 2,
      );
      const track2 = AudioTrack(
        id: 'a2',
        label: 'Audio 2 (Dialogue Commentary)',
        language: 'ja',
        channels: 1,
      );

      const trackSet = MediaTrackSet(audioTracks: [track1, track2]);
      expect(trackSet.audioTracks.length, equals(2));
      expect(trackSet.audioTracks[1].label, contains('Dialogue Commentary'));
    });
  });
}
