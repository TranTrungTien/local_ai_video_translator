import 'dart:async';

import 'package:local_ai_video_translator/core/diagnostics/diagnostics_service.dart';
import 'package:local_ai_video_translator/core/utils/cancellation_token.dart';
import 'package:local_ai_video_translator/features/source_resolver/data/candidate_verifier.dart';
import 'package:local_ai_video_translator/features/source_resolver/domain/entities/resolved_source.dart';

import '../domain/entities/embedded_playback_snapshot.dart';
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

  int _activeTransactionId = 0;
  CancellationToken? _activeCancellationToken;

  Future<NativeMigrationResult> attemptMigration({
    required ResolvedSource source,
    required EmbeddedPlaybackSnapshot snapshot,
  }) async {
    final transactionId = ++_activeTransactionId;
    _activeCancellationToken?.cancel();
    _activeCancellationToken = CancellationToken();
    final token = _activeCancellationToken!;

    final stopwatch = Stopwatch()..start();

    _updateStatus(MigrationStatus.validatingCandidate);
    _diagnostics.log(
      'MigrationController',
      'Beginning migration transaction #$transactionId for ${source.finalUri}',
    );

    try {
      // Step 1: Validate candidate accessibility
      final candidate =
          source.selectedCandidate ?? source.candidates.firstOrNull;

      if (candidate != null) {
        final verification = await _verifier.verify(candidate);
        if (transactionId != _activeTransactionId || token.isCancelled) {
          throw OperationCancelledException();
        }
        if (!verification.isAccessible) {
          throw NativePlayerBackendException(
            'Candidate ${candidate.uri} failed verification: ${verification.error ?? 'HTTP ${verification.statusCode}'}',
          );
        }
      }

      // Step 2: Prepare native player session
      _updateStatus(MigrationStatus.preparingNative);

      // If native session is already playing this source, don't reopen
      if (_nativeSession.currentSnapshot.mediaIdentity != source.finalUri.toString() ||
          _nativeSession.currentSnapshot.status == PlayerStatus.idle ||
          _nativeSession.currentSnapshot.status == PlayerStatus.error) {
        await _nativeSession.open(source);
      }

      if (transactionId != _activeTransactionId || token.isCancelled) {
        throw OperationCancelledException();
      }

      if (_nativeSession.currentSnapshot.status == PlayerStatus.error) {
        throw _nativeSession.currentSnapshot.error ??
            const NativePlayerBackendException(
              'Native player encountered error during preparation',
            );
      }

      // Step 3: Sync state (Seek, Rate, Volume)
      _diagnostics.log(
        'MigrationController',
        'Syncing state to native: position=${snapshot.position}, rate=${snapshot.playbackRate}',
      );

      await _nativeSession.seek(snapshot.position);
      await _nativeSession.setPlaybackRate(snapshot.playbackRate);
      await _nativeSession.setVolume(snapshot.volume);

      if (transactionId != _activeTransactionId || token.isCancelled) {
        throw OperationCancelledException();
      }

      if (snapshot.wasPlaying) {
        await _nativeSession.play();
      } else {
        await _nativeSession.pause();
      }

      if (transactionId != _activeTransactionId || token.isCancelled) {
        throw OperationCancelledException();
      }

      _updateStatus(MigrationStatus.nativeReady);

      // Step 4: Atomic cutover
      stopwatch.stop();
      _updateStatus(MigrationStatus.switchedToNative);

      return NativeMigrationResult(
        status: MigrationStatus.switchedToNative,
        attemptedCandidateUri: source.finalUri,
        capturedPosition: snapshot.position,
        prepareDuration: stopwatch.elapsed,
      );
    } on OperationCancelledException {
      _diagnostics.log('MigrationController', 'Discarding cancelled/superceded transaction #$transactionId');
      return NativeMigrationResult(
        status: MigrationStatus.nativeFailedReverted,
        attemptedCandidateUri: source.finalUri,
      );
    } catch (e) {
      if (transactionId != _activeTransactionId || token.isCancelled) {
        _diagnostics.log('MigrationController', 'Discarding failed superceded transaction #$transactionId');
        return NativeMigrationResult(
          status: MigrationStatus.nativeFailedReverted,
          attemptedCandidateUri: source.finalUri,
        );
      }

      stopwatch.stop();
      _diagnostics.log(
        'MigrationController',
        'Native migration failed: $e. Reverting to embedded WebView.',
        level: LogLevel.warning,
      );

      // Only close if it was this transaction that failed
      await _nativeSession.close();
      _updateStatus(MigrationStatus.nativeFailedReverted);

      return NativeMigrationResult(
        status: MigrationStatus.nativeFailedReverted,
        attemptedCandidateUri: source.finalUri,
        capturedPosition: snapshot.position,
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
    _activeCancellationToken?.cancel();
    _statusController.close();
  }
}
