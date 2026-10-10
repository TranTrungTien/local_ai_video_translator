import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_ai_video_translator/core/diagnostics/diagnostics_service.dart';
import 'package:local_ai_video_translator/core/network/dio_provider.dart';
import 'package:local_ai_video_translator/features/source_resolver/data/candidate_verifier.dart';
import 'package:local_ai_video_translator/features/pipeline/data/dubbing_player_service.dart';
import 'package:local_ai_video_translator/features/pipeline/presentation/ai_scheduler_controller.dart';

import '../../source_resolver/domain/entities/resolved_source.dart';
import '../data/migration_controller.dart';
import '../data/native_media_session.dart';
import '../domain/entities/media_session_snapshot.dart';
import '../domain/entities/media_track.dart';

final nativeMediaSessionProvider = Provider<NativeMediaSession>((ref) {
  final session = NativeMediaSession();
  ref.onDispose(() => unawaited(session.close()));
  return session;
});

final migrationControllerProvider = Provider<NativeMigrationController>((ref) {
  final session = ref.watch(nativeMediaSessionProvider);
  final dio = ref.watch(dioProvider);
  final verifier = CandidateVerifier(dio);
  final diagnostics = ref.watch(diagnosticsServiceProvider);

  final controller = NativeMigrationController(session, verifier, diagnostics);
  ref.onDispose(controller.dispose);
  return controller;
});

final dubbingPlayerServiceProvider = Provider<DubbingPlayerService>((ref) {
  final repo = ref.watch(dubbingRepositoryProvider);
  final service = DubbingPlayerService(repo);
  ref.onDispose(service.dispose);
  return service;
});

final mediaSessionControllerProvider =
    StateNotifierProvider<MediaSessionController, MediaSessionSnapshot>((ref) {
      final session = ref.watch(nativeMediaSessionProvider);
      final migration = ref.watch(migrationControllerProvider);
      final dubbingPlayer = ref.watch(dubbingPlayerServiceProvider);

      return MediaSessionController(session, migration, dubbingPlayer);
    });

class MediaSessionController extends StateNotifier<MediaSessionSnapshot> {
  MediaSessionController(
    this._session,
    this._migrationController,
    this._dubbingPlayer,
  ) : super(MediaSessionSnapshot.idle) {
    _subscription = _session.snapshotStream.listen((snapshot) {
      state = snapshot;

      // Đồng bộ âm thanh lồng tiếng mỗi khi vị trí video thay đổi
      _dubbingPlayer.syncWithPlayback(
        snapshot.position,
        snapshot.isPlaying,
      );
    });

    // Lắng nghe tín hiệu ducking để giảm âm lượng video mượt mà khi có lồng tiếng
    _duckingSubscription = _dubbingPlayer.duckingStream.listen((shouldDuck) {
      _fadeVolume(shouldDuck ? 20.0 : 100.0);
    });
  }

  final NativeMediaSession _session;
  final NativeMigrationController _migrationController;
  final DubbingPlayerService _dubbingPlayer;
  StreamSubscription<MediaSessionSnapshot>? _subscription;
  StreamSubscription<bool>? _duckingSubscription;
  Timer? _fadeTimer;

  void _fadeVolume(double targetVolume) {
    _fadeTimer?.cancel();

    final startVolume = state.volume;
    final steps = 10;
    final duration = const Duration(milliseconds: 200);
    final stepDuration = Duration(milliseconds: duration.inMilliseconds ~/ steps);
    final volumeDelta = (targetVolume - startVolume) / steps;

    int currentStep = 0;
    _fadeTimer = Timer.periodic(stepDuration, (timer) {
      currentStep++;
      final nextVolume = startVolume + (volumeDelta * currentStep);
      _session.setVolume(nextVolume.clamp(0.0, 100.0));

      if (currentStep >= steps) {
        timer.cancel();
      }
    });
  }

  Future<void> openSource(ResolvedSource source) async {
    await _session.open(source);
  }

  Future<void> play() => _session.play();
  Future<void> pause() => _session.pause();
  Future<void> seek(Duration position) => _session.seek(position);
  Future<void> setPlaybackRate(double rate) => _session.setPlaybackRate(rate);

  Future<void> selectVideoTrack(VideoTrack track) =>
      _session.selectVideoTrack(track);
  Future<void> selectAudioTrack(AudioTrack track) =>
      _session.selectAudioTrack(track);
  Future<void> selectSubtitleTrack(PlayerSubtitleTrack? track) =>
      _session.selectSubtitleTrack(track);

  Future<bool> attemptMigrationToNative({
    required ResolvedSource source,
    Duration? capturedPosition,
  }) async {
    final result = await _migrationController.attemptMigration(
      source: source,
      capturedPosition: capturedPosition,
    );
    return result.isSuccess;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _duckingSubscription?.cancel();
    _fadeTimer?.cancel();
    super.dispose();
  }
}
