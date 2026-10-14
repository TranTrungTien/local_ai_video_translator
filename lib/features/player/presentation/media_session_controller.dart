import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/network/dio_provider.dart';
import '../../pipeline/data/dubbing_player_service.dart';
import '../../pipeline/presentation/ai_scheduler_controller.dart';
import '../../source_resolver/data/candidate_verifier.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import '../data/migration_controller.dart';
import '../data/native_media_session.dart';
import '../domain/entities/embedded_playback_snapshot.dart';
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
    NotifierProvider<MediaSessionController, MediaSessionSnapshot>(
      MediaSessionController.new,
    );

class MediaSessionController extends Notifier<MediaSessionSnapshot> {
  Timer? _fadeTimer;

  // Sử dụng getter để truy cập các provider ổn định, tránh rủi ro late init trong suốt vòng đời của phương thức build()
  NativeMediaSession get _session => ref.read(nativeMediaSessionProvider);
  NativeMigrationController get _migration => ref.read(migrationControllerProvider);

  @override
  MediaSessionSnapshot build() {
    final session = ref.watch(nativeMediaSessionProvider);
    final dubbing = ref.watch(dubbingPlayerServiceProvider);

    final sub = session.snapshotStream.listen((snapshot) {
      state = snapshot;
      dubbing.syncWithPlayback(snapshot.position, snapshot.isPlaying);
    });

    final duckSub = dubbing.duckingStream.listen((shouldDuck) {
      _fadeVolume(shouldDuck ? 20.0 : 100.0);
    });

    ref.onDispose(() {
      sub.cancel();
      duckSub.cancel();
      _fadeTimer?.cancel();
    });

    return MediaSessionSnapshot.idle;
  }

  void _fadeVolume(double targetVolume) {
    _fadeTimer?.cancel();
    final startVolume = state.volume;
    const steps = 10;
    const duration = Duration(milliseconds: 200);
    final stepDuration = Duration(milliseconds: duration.inMilliseconds ~/ steps);
    final volumeDelta = (targetVolume - startVolume) / steps;

    int currentStep = 0;
    _fadeTimer = Timer.periodic(stepDuration, (timer) {
      currentStep++;
      final nextVolume = startVolume + (volumeDelta * currentStep);
      _session.setVolume(nextVolume.clamp(0.0, 100.0));
      if (currentStep >= steps) timer.cancel();
    });
  }

  Future<void> openSource(ResolvedSource source) => _session.open(source);
  Future<void> play() => _session.play();
  Future<void> pause() => _session.pause();
  Future<void> seek(Duration position) => _session.seek(position);
  Future<void> setPlaybackRate(double rate) => _session.setPlaybackRate(rate);

  Future<void> selectVideoTrack(VideoTrack track) => _session.selectVideoTrack(track);
  Future<void> selectAudioTrack(AudioTrack track) => _session.selectAudioTrack(track);
  Future<void> selectSubtitleTrack(PlayerSubtitleTrack? track) => _session.selectSubtitleTrack(track);

  /// Đã khớp chữ ký với UI trong EmbeddedPlayerView (Critical #2)
  Future<bool> attemptMigrationToNative({
    required ResolvedSource source,
    required EmbeddedPlaybackSnapshot snapshot,
  }) async {
    final result = await _migration.attemptMigration(
      source: source,
      snapshot: snapshot,
    );
    return result.isSuccess;
  }

  Future<void> updateNativeAudioAnchor({
    required Duration position,
    required bool isPlaying,
    required double playbackRate,
    required int timelineEpoch,
    required String playbackSessionId,
    required int seekGeneration,
  }) async {
    const channel = MethodChannel('local_ai_video_translator/native_resolver');
    final anchorMonotonicUs = await channel.invokeMethod<int>('getMonotonicUs') ??
        DateTime.now().microsecondsSinceEpoch;

    await channel.invokeMethod('updateAudioAnchor', {
      'mediaPositionUs': position.inMicroseconds,
      'anchorMonotonicUs': anchorMonotonicUs,
      'playbackRate': playbackRate,
      'isPlaying': isPlaying,
      'isBuffering': false,
      'timelineEpoch': timelineEpoch,
      'playbackSessionId': playbackSessionId,
      'seekGeneration': seekGeneration,
    });
  }
}
