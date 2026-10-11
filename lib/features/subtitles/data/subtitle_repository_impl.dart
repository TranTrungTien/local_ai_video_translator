import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';
import '../../pipeline/domain/ai_pipeline.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import '../domain/entities/subtitle_document.dart';
import '../domain/entities/subtitle_track.dart';
import '../domain/subtitle_selection_policy.dart';
import 'subtitle_language_detector.dart';
import 'subtitle_parser.dart';
import '../domain/repositories/subtitle_repository.dart';

class SubtitleRepositoryImpl implements SubtitleRepository, SubtitleTrackProvider {
  SubtitleRepositoryImpl(
    this._dio, [
    SubtitleParser? parser,
    SubtitleLanguageDetector? languageDetector,
    SubtitleSelectionPolicy? selectionPolicy,
  ]) : _parser = parser ?? const SubtitleParser(),
       _languageDetector = languageDetector ?? const SubtitleLanguageDetector(),
       _selectionPolicy = selectionPolicy ?? const SubtitleSelectionPolicy();

  final Dio _dio;
  final SubtitleParser _parser;
  final SubtitleLanguageDetector _languageDetector;
  final SubtitleSelectionPolicy _selectionPolicy;

  @override
  Future<List<SubtitleTrack>> findSubtitleTracks(ResolvedSource source) async {
    final tracks = <SubtitleTrack>[];

    if (source.kind == MediaKind.hls) {
      final hlsTracks = await _extractHlsSubtitles(source.uri, source.requestContext);
      tracks.addAll(hlsTracks);
    } else if (source.kind == MediaKind.dash) {
      final dashTracks = await _extractDashSubtitles(source.uri, source.requestContext);
      tracks.addAll(dashTracks);
    }

    if (source.kind == MediaKind.localFile || source.uri.isScheme('file')) {
      final sidecarTracks = await _checkLocalSidecarSubtitles(source.uri);
      tracks.addAll(sidecarTracks);
    }

    return tracks;
  }

  Future<List<SubtitleTrack>> _extractHlsSubtitles(
    Uri playlistUri,
    RequestContext context,
  ) async {
    final tracks = <SubtitleTrack>[];
    try {
      final response = await _dio.get<String>(
        playlistUri.toString(),
        options: Options(headers: context.headers),
      );
      final content = response.data ?? '';

      // Improved regex for HLS subtitles to capture more attributes
      final subtitleRx = RegExp(
        r'#EXT-X-MEDIA:TYPE=SUBTITLES.*?,NAME="([^"]+)"(?:.*?,LANGUAGE="([^"]+)")?.*?URI="([^"]+)"',
        caseSensitive: false,
      );

      for (final match in subtitleRx.allMatches(content)) {
        final title = match.group(1) ?? 'Subtitle';
        final rawLang = match.group(2) ?? 'en';
        final relUri = match.group(3);

        if (relUri != null) {
          final absUri = playlistUri.resolve(relUri);
          final lang = _languageDetector.detectLanguage(
            declaredLanguage: rawLang,
          );
          final isVi = lang == AppConstants.targetLanguage;

          tracks.add(
            SubtitleTrack(
              id: 'hls_sub_${tracks.length}_$lang',
              language: lang,
              title: title,
              uri: absUri,
              format: SubtitleFormat.webvtt,
              isTargetLanguage: isVi,
              requestContext: context,
            ),
          );
        }
      }
    } catch (_) {
      // HLS subtitle discovery fallback
    }
    return tracks;
  }

  Future<List<SubtitleTrack>> _extractDashSubtitles(
    Uri mpdUri,
    RequestContext context,
  ) async {
    final tracks = <SubtitleTrack>[];
    try {
      final response = await _dio.get<String>(
        mpdUri.toString(),
        options: Options(headers: context.headers),
      );
      final content = response.data ?? '';

      // DASH parsing for subtitles is complex, we look for AdaptationSets with mimeType="text/vtt" or similar
      final adaptSetRx = RegExp(
        r'<AdaptationSet[^>]*?(?:contentType|mimeType)="text/(?:vtt|ttml|xml)"[^>]*?>(.*?)</AdaptationSet>',
        caseSensitive: false,
        dotAll: true,
      );
      final langRx = RegExp(r'lang="([^"]+)"', caseSensitive: false);
      final baseUriRx = RegExp(r'<BaseURL>(.*?)</BaseURL>', caseSensitive: false);

      for (final match in adaptSetRx.allMatches(content)) {
        final setContent = match.group(1)!;
        final langMatch = langRx.firstMatch(match.group(0)!);
        final rawLang = langMatch?.group(1) ?? 'en';
        final lang = _languageDetector.detectLanguage(
          declaredLanguage: rawLang,
        );

        final baseUrlMatch = baseUriRx.firstMatch(setContent);
        final subUri = baseUrlMatch != null
            ? mpdUri.resolve(baseUrlMatch.group(1)!)
            : mpdUri;

        final isVi = lang == AppConstants.targetLanguage;

        tracks.add(
          SubtitleTrack(
            id: 'dash_sub_${tracks.length}_$lang',
            language: lang,
            title: 'DASH Subtitle ($lang)',
            uri: subUri,
            format: setContent.contains('vtt') ? SubtitleFormat.webvtt : SubtitleFormat.hlsSegment,
            isTargetLanguage: isVi,
            requestContext: context,
          ),
        );
      }
    } catch (_) {
      // DASH subtitle discovery fallback
    }
    return tracks;
  }

  Future<List<SubtitleTrack>> _checkLocalSidecarSubtitles(Uri fileUri) async {
    final tracks = <SubtitleTrack>[];
    final path = fileUri.toFilePath();
    final basePath = path.contains('.')
        ? path.substring(0, path.lastIndexOf('.'))
        : path;

    for (final ext in [
      '.vi.vtt',
      '.vi.srt',
      '.en.vtt',
      '.en.srt',
      '.vtt',
      '.srt',
      '.ttml',
    ]) {
      final subFile = File('$basePath$ext');
      try {
        if (await subFile.exists()) {
          final content = await subFile.readAsString();
          if (content.isNotEmpty) {
            final isVi =
                ext.contains('.vi.') ||
                _languageDetector.detectLanguage(sampleText: content) == 'vi';
            final lang = isVi
                ? 'vi'
                : _languageDetector.detectLanguage(
                    declaredLanguage: ext.contains('.en.') ? 'en' : 'unknown',
                  );

            tracks.add(
              SubtitleTrack(
                id: 'local_sub_${tracks.length}',
                language: lang,
                title: isVi
                    ? 'Vietnamese Sidecar Subtitle'
                    : 'Local Sidecar Subtitle ($lang)',
                uri: Uri.file(subFile.path),
                format: ext.contains('vtt')
                    ? SubtitleFormat.webvtt
                    : (ext.contains('ttml')
                          ? SubtitleFormat.hlsSegment
                          : SubtitleFormat.srt),
                isTargetLanguage: isVi,
              ),
            );
          }
        }
      } catch (_) {
        // Local subtitle file error
      }
    }
    return tracks;
  }

  Future<SubtitleDocument> fetchSubtitleDocument(SubtitleTrack track) async {
    try {
      String body;
      if (track.uri.isScheme('file')) {
        body = await File(track.uri.toFilePath()).readAsString();
      } else {
        final response = await _dio.get<String>(track.uri.toString());
        body = response.data ?? '';
      }

      final lang = _languageDetector.detectLanguage(
        declaredLanguage: track.language,
        sampleText: body.substring(0, body.length > 500 ? 500 : body.length),
      );

      if (track.uri.path.endsWith('.ttml') ||
          body.contains('<tt') ||
          body.contains('<p begin=')) {
        return _parser.parseTtmlDocument(body, language: lang);
      } else if (track.format == SubtitleFormat.webvtt ||
          body.contains('WEBVTT')) {
        return _parser.parseVttDocument(body, language: lang);
      } else {
        return _parser.parseSrtDocument(body, language: lang);
      }
    } catch (_) {
      return SubtitleDocument(
        id: track.id,
        title: track.title,
        language: track.language,
        format: 'unknown',
        segments: const [],
        sourceUri: track.uri,
      );
    }
  }

  @override
  Future<List<TimedTextSegment>> fetchSubtitleSegments(
    SubtitleTrack track,
  ) async {
    final doc = await fetchSubtitleDocument(track);
    return doc.segments
        .map(
          (s) => TimedTextSegment(
            start: s.start,
            end: s.end,
            text: s.text,
            language: s.language,
          ),
        )
        .toList();
  }

  @override
  Future<List<TimedTextSegment>> findExistingSubtitles(
    String targetLanguage,
  ) async {
    return const [];
  }
}
