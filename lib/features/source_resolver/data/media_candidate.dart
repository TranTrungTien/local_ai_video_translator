import '../domain/entities/resolved_source.dart';

enum CandidateValidationStatus {
  valid,
  invalid,
  requiresEmbeddedSession,
  unknown,
}

class MediaCandidate {
  const MediaCandidate({
    required this.uri,
    required this.kind,
    required this.method,
    this.score = 0,
    this.validationStatus = CandidateValidationStatus.unknown,
    this.statusCode = -1,
    this.contentType = '',
    this.contentLength = -1,
    this.rejectionReason,
  });

  final Uri uri;
  final MediaKind kind;
  final DiscoveryMethod method;
  final int score;
  final CandidateValidationStatus validationStatus;
  final int statusCode;
  final String contentType;
  final int contentLength;
  final String? rejectionReason;

  MediaCandidate copyWith({
    Uri? uri,
    MediaKind? kind,
    DiscoveryMethod? method,
    int? score,
    CandidateValidationStatus? validationStatus,
    int? statusCode,
    String? contentType,
    int? contentLength,
    String? rejectionReason,
  }) {
    return MediaCandidate(
      uri: uri ?? this.uri,
      kind: kind ?? this.kind,
      method: method ?? this.method,
      score: score ?? this.score,
      validationStatus: validationStatus ?? this.validationStatus,
      statusCode: statusCode ?? this.statusCode,
      contentType: contentType ?? this.contentType,
      contentLength: contentLength ?? this.contentLength,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }
}
