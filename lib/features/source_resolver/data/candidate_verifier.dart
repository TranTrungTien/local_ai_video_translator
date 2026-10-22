import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/entities/resolved_source.dart';
import 'media_candidate.dart';

class VerifiedCandidateResult {
  const VerifiedCandidateResult({
    required this.candidate,
    required this.isAccessible,
    required this.statusCode,
    required this.contentType,
    required this.contentLength,
    this.error,
  });

  final MediaCandidate candidate;
  final bool isAccessible;
  final int statusCode;
  final String contentType;
  final int contentLength;
  final String? error;
}

class CandidateVerifier {
  CandidateVerifier(this._dio);

  final Dio _dio;
  static const _nativeChannel = MethodChannel(
    'local_ai_video_translator/native_resolver',
  );

  Future<VerifiedCandidateResult> verify(
    MediaCandidate candidate, {
    Map<String, String>? headers,
  }) async {
    if (kIsWeb) {
      // On Web, CORS often blocks HEAD/GET requests from JS.
      // If it looks like a direct media URL, we might want to skip strict verification
      // or at least handle the failure gracefully.
      return _verifyForWeb(candidate, headers: headers);
    }

    // Try native Android verification first
    if (!kIsWeb) {
      try {
        final res = await _nativeChannel.invokeMethod<Map<dynamic, dynamic>>(
          'verifyCandidate',
          {
            'url': candidate.uri.toString(),
            'headers': headers ?? <String, String>{},
          },
        );
        if (res != null) {
          final isAccessible = res['isAccessible'] as bool? ?? false;
          final statusCode = res['statusCode'] as int? ?? -1;
          final contentType = res['contentType'] as String? ?? '';
          final contentLength = res['contentLength'] as int? ?? -1;
          final error = res['error'] as String?;

          final updatedKind =
              _detectKindFromContentType(contentType) ?? candidate.kind;
          final status =
              isAccessible
                  ? CandidateValidationStatus.valid
                  : (statusCode == 403 || statusCode == 401
                      ? CandidateValidationStatus.requiresEmbeddedSession
                      : CandidateValidationStatus.invalid);

          final updatedCandidate = candidate.copyWith(
            kind: updatedKind,
            score: isAccessible ? (candidate.score + 25) : candidate.score,
            validationStatus: status,
            statusCode: statusCode,
            contentType: contentType,
            contentLength: contentLength,
            rejectionReason: isAccessible ? null : error ?? 'HTTP $statusCode',
          );

          return VerifiedCandidateResult(
            candidate: updatedCandidate,
            isAccessible: isAccessible,
            statusCode: statusCode,
            contentType: contentType,
            contentLength: contentLength,
            error: error,
          );
        }
      } catch (_) {
        // Native channel fallback
      }
    }

    return _verifyWithDio(candidate, headers: headers);
  }

  Future<VerifiedCandidateResult> _verifyForWeb(
    MediaCandidate candidate, {
    Map<String, String>? headers,
  }) async {
    // For Blob URLs, they are always accessible locally
    if (candidate.uri.scheme == 'blob' || candidate.uri.scheme == 'data') {
      return VerifiedCandidateResult(
        candidate: candidate.copyWith(
          validationStatus: CandidateValidationStatus.valid,
          score: candidate.score + 100,
        ),
        isAccessible: true,
        statusCode: 200,
        contentType: '',
        contentLength: -1,
      );
    }

    try {
      // Try a real check, but expect CORS failures
      return await _verifyWithDio(candidate, headers: headers);
    } catch (e) {
      // On Web, if it fails, we check if it's a known media extension.
      // If so, we MARK IT AS VALID but with a warning or lower score,
      // because <video> tags might still be able to play it due to different CORS rules
      // (e.g. simple requests vs preflight).
      final path = candidate.uri.path.toLowerCase();
      final isLikelyMedia =
          path.endsWith('.m3u8') ||
          path.endsWith('.mp4') ||
          path.endsWith('.mpd') ||
          path.endsWith('.webm');

      if (isLikelyMedia) {
        return VerifiedCandidateResult(
          candidate: candidate.copyWith(
            validationStatus: CandidateValidationStatus.valid,
            score: candidate.score + 10, // Lower score because unverified
            rejectionReason: 'CORS/Network error during verification, but extension matches.',
          ),
          isAccessible: true,
          statusCode: -1,
          contentType: '',
          contentLength: -1,
        );
      }
      rethrow;
    }
  }

  Future<VerifiedCandidateResult> _verifyWithDio(
    MediaCandidate candidate, {
    Map<String, String>? headers,
  }) async {
    try {
      final response = await _dio.head<void>(
        candidate.uri.toString(),
        options: Options(
          headers: headers,
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      final statusCode = response.statusCode ?? 200;
      final contentType = response.headers.value('content-type') ?? '';
      final contentLengthStr = response.headers.value('content-length');
      final contentLength = int.tryParse(contentLengthStr ?? '') ?? -1;

      final updatedKind =
          _detectKindFromContentType(contentType) ?? candidate.kind;

      final updatedCandidate = candidate.copyWith(
        kind: updatedKind,
        score: candidate.score + 20,
        validationStatus: CandidateValidationStatus.valid,
        statusCode: statusCode,
        contentType: contentType,
        contentLength: contentLength,
      );

      return VerifiedCandidateResult(
        candidate: updatedCandidate,
        isAccessible: true,
        statusCode: statusCode,
        contentType: contentType,
        contentLength: contentLength,
      );
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode ?? -1;
      final status = (statusCode == 403 || statusCode == 401)
          ? CandidateValidationStatus.requiresEmbeddedSession
          : CandidateValidationStatus.invalid;

      final updatedCandidate = candidate.copyWith(
        validationStatus: status,
        statusCode: statusCode,
        contentType: '',
        contentLength: -1,
        rejectionReason: e.message ?? 'HTTP $statusCode',
      );

      return VerifiedCandidateResult(
        candidate: updatedCandidate,
        isAccessible: false,
        statusCode: statusCode,
        contentType: '',
        contentLength: -1,
        error: e.message,
      );
    }
  }

  MediaKind? _detectKindFromContentType(String contentType) {
    final lower = contentType.toLowerCase();
    if (lower.contains('mpegurl') || lower.contains('m3u8')) {
      return MediaKind.hls;
    }
    if (lower.contains('dash+xml')) {
      return MediaKind.dash;
    }
    if (lower.startsWith('video/')) {
      return MediaKind.progressive;
    }
    return null;
  }
}
