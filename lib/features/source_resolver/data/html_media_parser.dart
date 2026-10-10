import '../domain/entities/resolved_source.dart';
import 'media_candidate.dart';

class ParsedHtmlMedia {
  const ParsedHtmlMedia({required this.candidates, required this.iframes});
  final List<MediaCandidate> candidates;
  final List<Uri> iframes;
}

class HtmlMediaParser {
  const HtmlMediaParser();

  ParsedHtmlMedia parse(String html, Uri baseUri) {
    final candidates = <MediaCandidate>[];
    final iframes = <Uri>[];

    final iframeRx = RegExp(
      r'''<iframe[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in iframeRx.allMatches(html)) {
      final uri = _absolute(baseUri, match.group(1));
      if (uri != null) {
        iframes.add(uri);
      }
    }

    final urlRx = RegExp(
      r'''(?:src|file|url)\s*[:=]\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in urlRx.allMatches(html)) {
      final uri = _absolute(baseUri, match.group(1));
      if (uri != null) {
        final kind = _kind(uri);
        if (kind != null) {
          candidates.add(
            MediaCandidate(
              uri: uri,
              kind: kind,
              method: DiscoveryMethod.htmlVideo,
              score: 60,
            ),
          );
        }
      }
    }

    final rawMediaRx = RegExp(
      r'''https?:\\?/\\?/[^-\u0020"'<>]+?(?:\.m3u8|\.mpd|\.mp4|\.webm)(?:\?[^-\u0020"'<>]*)?''',
      caseSensitive: false,
    );
    for (final match in rawMediaRx.allMatches(html)) {
      final raw = match.group(0)?.replaceAll(r'\/', '/');
      final uri = raw == null ? null : Uri.tryParse(raw);
      if (uri != null) {
        final kind = _kind(uri);
        if (kind != null) {
          candidates.add(
            MediaCandidate(
              uri: uri,
              kind: kind,
              method: DiscoveryMethod.htmlVideo,
              score: 70,
            ),
          );
        }
      }
    }

    return ParsedHtmlMedia(
      candidates: _dedupe(candidates),
      iframes: iframes.toSet().toList(),
    );
  }

  Uri? _absolute(Uri base, String? raw) {
    if (raw == null ||
        raw.startsWith('blob:') ||
        raw.startsWith('javascript:')) {
      return null;
    }
    final normalized = raw.replaceAll('&amp;', '&').trim();
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return null;
    }
    return uri.hasScheme ? uri : base.resolveUri(uri);
  }

  MediaKind? _kind(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.endsWith('.m3u8')) {
      return MediaKind.hls;
    }
    if (path.endsWith('.mpd')) {
      return MediaKind.dash;
    }
    if (['.mp4', '.webm', '.mkv', '.m4v'].any(path.endsWith)) {
      return MediaKind.progressive;
    }
    return null;
  }

  List<MediaCandidate> _dedupe(List<MediaCandidate> input) {
    final seen = <String>{};
    return input.where((item) => seen.add(item.uri.toString())).toList();
  }
}
