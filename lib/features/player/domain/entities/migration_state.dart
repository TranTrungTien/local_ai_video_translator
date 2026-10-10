enum MigrationStatus {
  embedded,
  validatingCandidate,
  preparingNative,
  nativeReady,
  switchedToNative,
  nativeFailedReverted,
}

class NativeMigrationResult {
  const NativeMigrationResult({
    required this.status,
    required this.attemptedCandidateUri,
    this.capturedPosition = Duration.zero,
    this.prepareDuration = Duration.zero,
    this.failureReason,
  });

  final MigrationStatus status;
  final Uri attemptedCandidateUri;
  final Duration capturedPosition;
  final Duration prepareDuration;
  final String? failureReason;

  bool get isSuccess =>
      status == MigrationStatus.switchedToNative ||
      status == MigrationStatus.nativeReady;
}
