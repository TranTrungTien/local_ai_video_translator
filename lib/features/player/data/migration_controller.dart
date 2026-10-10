import 'dart:async';

import 'package:local_ai_video_translator/core/diagnostics/diagnostics_service.dart';
import 'package:local_ai_video_translator/features/source_resolver/data/candidate_verifier.dart';
import 'package:local_ai_video_translator/features/source_resolver/domain/entities/resolved_source.dart';

import '../domain/entities/migration_state.dart';
import '../domain/entities/player_state.dart';
import 'native_media_session.dart';

class NativeMigrationController {
  NativeMigrationController(
    this._nativeSession,
    this._verifier,
    this._diagnostics,
  );

  final NativeMediaSession _nativeSession;
  final CandidateVerifier _verifier;
  final DiagnosticsService _diagnostics;

  MigrationStatus _status = MigrationStatus.embedded;
  final _statusController = StreamController<MigrationStatus>.broadcast();

  MigrationStatus get status => _status;
  Stream<MigrationStatus> get statusStream => _statusController.stream;

  Future<NativeMigrationResult> attemptMigration({
    required ResolvedSource source,
    Duration? capturedPosition,
  }) async {
    final stopwatch = Stopwatch()..start();
    _updateStatus(MigrationStatus.validatingCandidate);
    _diagnostics.log(
      'MigrationController',
      'Beginning candidate verification before native migration for ${source.finalUri}',
    );

    try {
      // Step 1: Validate candidate accessibility
      final candidate =
          source.selectedCandidate ?? source.candidates.firstOrNull;

      if (candidate != null) {
        final verification = await _verifier.verify(
          candidate,
          context: source.requestContext,
        );
        if (!verification.isAccessible) {
          throw NativePlayerBackendException(
            'Candidate ${candidate.uri} failed verification: ${verification.error ?? 'HTTP ${verification.statusCode}'}',
          );
        }
      }

      // Step 2: Prepare native player session while keeping embedded view active
      _updateStatus(MigrationStatus.preparingNative);
      _diagnostics.log(
        'MigrationController',
        'Candidate verified accessible. Opening native media session.',
      );

      await _nativeSession.open(source);

      if (_nativeSession.currentSnapshot.status == PlayerStatus.error) {
        throw _nativeSession.currentSnapshot.error ??
            const NativePlayerBackendException(
              'Native player encountered error during preparation',
            );
      }

      _updateStatus(MigrationStatus.nativeReady);

      // Step 3: Seek to captured webview position if applicable
      if (capturedPosition != null && capturedPosition > Duration.zero) {
        _diagnostics.log(
          'MigrationController',
          'Seeking native player to captured position: $capturedPosition',
        );
        await _nativeSession.seek(capturedPosition);
      }

      // Step 4: Switch UI playback mode and confirm completion
      stopwatch.stop();
      _updateStatus(MigrationStatus.switchedToNative);
      _diagnostics.log(
        'MigrationController',
        'Successfully migrated to native player in ${stopwatch.elapsed.inMilliseconds}ms',
      );

      return NativeMigrationResult(
        status: MigrationStatus.switchedToNative,
        attemptedCandidateUri: source.finalUri,
        capturedPosition: capturedPosition ?? Duration.zero,
        prepareDuration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      _diagnostics.log(
        'MigrationController',
        'Native migration failed: $e. Reverting to embedded WebView.',
        level: LogLevel.warning,
      );
      await _nativeSession.close();

      _updateStatus(MigrationStatus.nativeFailedReverted);

      return NativeMigrationResult(
        status: MigrationStatus.nativeFailedReverted,
        attemptedCandidateUri: source.finalUri,
        capturedPosition: capturedPosition ?? Duration.zero,
        prepareDuration: stopwatch.elapsed,
        failureReason: e.toString(),
      );
    }
  }

  void _updateStatus(MigrationStatus newStatus) {
    _status = newStatus;
    if (!_statusController.isClosed) {
      _statusController.add(_status);
    }
  }

  void dispose() {
    _statusController.close();
  }
}
