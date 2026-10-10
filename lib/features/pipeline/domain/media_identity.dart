import 'dart:convert';
import 'package:crypto/crypto.dart';

class MediaIdentity {
  const MediaIdentity({
    required this.normalizedPath,
    required this.durationSeconds,
    this.title,
    this.episode,
    this.streamCharacteristics = 'hls_video',
  });

  final String normalizedPath;
  final int durationSeconds;
  final String? title;
  final String? episode;
  final String streamCharacteristics;

  /// Generates a robust layered fingerprint that is immune to ephemeral CDN query token changes.
  String generateFingerprint() {
    // Strip ephemeral query parameters or signed tokens from URI path
    Uri uri;
    try {
      uri = Uri.parse(normalizedPath);
    } catch (_) {
      uri = Uri(path: normalizedPath);
    }

    final cleanPath = '${uri.scheme}://${uri.host}${uri.path}'
        .toLowerCase()
        .trim();
    final rawKey =
        '$cleanPath|$durationSeconds|${(title ?? '').toLowerCase().trim()}|${(episode ?? '').toLowerCase().trim()}|$streamCharacteristics';

    final bytes = utf8.encode(rawKey);
    return sha256.convert(bytes).toString();
  }
}
