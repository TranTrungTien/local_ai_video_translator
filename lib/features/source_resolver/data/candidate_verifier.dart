import 'package:dio/dio.dart';
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
    // Try native Android verification first
    try {
      final res = await _nativeChannel
          .invokeMethod<Map<dynamic, dynamic>>('verifyCandidate', {
            'url': candidate.uri.toString(),
            'headers': headers ?? <String, String>{},
          });
      if (res != null) {
        final isAccessible = res['isAccessible'] as bool? ?? false;
        final statusCode = res['statusCode'] as int? ?? -1;
        final contentType = res['contentType'] as String? ?? '';
        final contentLength = res['contentLength'] as int? ?? -1;
        final error = res['error'] as String?;

        final updatedKind =
            _detectKindFromContentType(contentType) ?? candidate.kind;
        final status = isAccessible
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

    return _verifyWithDio(candidate, headers: headers);
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
