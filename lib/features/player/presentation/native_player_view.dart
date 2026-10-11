import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart' hide AudioTrack;
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/diagnostics/presentation/diagnostic_log_overlay.dart';
import '../../pipeline/presentation/ai_scheduler_controller.dart';
import '../../pipeline/presentation/dubbing_controller.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import '../domain/entities/media_session_snapshot.dart';
import '../domain/entities/media_track.dart';
import '../domain/entities/player_state.dart';
import 'media_session_controller.dart';
import 'subtitle_overlay.dart';

class NativePlayerView extends ConsumerStatefulWidget {
  const NativePlayerView({required this.source, super.key});
  final ResolvedSource source;

  @override
  ConsumerState<NativePlayerView> createState() => _NativePlayerViewState();
}

class _NativePlayerViewState extends ConsumerState<NativePlayerView> {
  late final Player _player;
  VideoController? _videoController;
  StreamSubscription<Duration>? _positionSub;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);

    _player.open(
      Media(widget.source.uri.toString(), httpHeaders: widget.source.headers),
      play: true,
    );

    _positionSub = _player.stream.position.listen((pos) {
      if (!mounted) return;
      ref.read(aiSchedulerProvider.notifier).updatePlaybackPosition(pos);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(aiSchedulerProvider.notifier).initializeForSource(widget.source);
      ref
          .read(mediaSessionControllerProvider.notifier)
          .openSource(widget.source);
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_videoController == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF7C5CFC)),
        ),
      );
    }

    final aiState = ref.watch(aiSchedulerProvider);
    final sessionSnapshot = ref.watch(mediaSessionControllerProvider);

    // Auto-pause when AI subtitle buffer is exhausted
    ref.listen<AiSchedulerState>(aiSchedulerProvider, (previous, next) {
      if (next.isBufferingForAi && !(_player.state.playing == false)) {
        _player.pause();
      } else if (!next.isBufferingForAi && previous?.isBufferingForAi == true) {
        _player.play();
      }
    });

    // Audio Ducking: Giảm âm lượng video khi có lồng tiếng AI phát
    ref.listen<AsyncValue<String?>>(
      activeDubIdProvider,
      (previous, next) {
        if (ref.read(dubbingControllerProvider)) {
          final activeId = next.value;
          if (activeId != null) {
            _player.setVolume(25.0); // Set to 25% for ducking
          } else {
            _player.setVolume(100.0);
          }
        }
      },
    );

    if (sessionSnapshot.status == PlayerStatus.error) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Card(
            color: Colors.red.withValues(alpha: 0.2),
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Native Player Error',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    sessionSnapshot.error?.message ?? 'Unknown playback error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => ref
                        .read(mediaSessionControllerProvider.notifier)
                        .openSource(widget.source),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry Playback'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: Video(controller: _videoController!)),
          SubtitleOverlay(segment: aiState.activeSegment),
          _TrackSelectorOverlay(sessionSnapshot: sessionSnapshot),
          if (kDebugMode)
            Positioned(
              bottom: 80,
              right: 16,
              child: FloatingActionButton.small(
                backgroundColor: Colors.black54,
                child: const Icon(Icons.bug_report, color: Colors.redAccent),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => const DiagnosticLogOverlay(),
                  );
                },
              ),
            ),
          if (aiState.isBufferingForAi)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF7C5CFC)),
                    const SizedBox(height: 16),
                    Text(
                      'Refilling Subtitle Buffer (${aiState.subtitleAhead.inSeconds}s / ${AppConstants.initialSubtitleBuffer.inSeconds}s)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Video paused to guarantee synchronized Vietnamese subtitles',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackSelectorOverlay extends ConsumerWidget {
  const _TrackSelectorOverlay({required this.sessionSnapshot});
  final MediaSessionSnapshot sessionSnapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioTracks = sessionSnapshot.trackSet.audioTracks;
    final subtitleTracks = sessionSnapshot.trackSet.subtitleTracks;

    if (audioTracks.length <= 1 && subtitleTracks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 12,
      right: 12,
      child: Material(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (audioTracks.length > 1) ...[
                PopupMenuButton<AudioTrack>(
                  icon: const Icon(
                    Icons.audiotrack,
                    size: 18,
                    color: Colors.white,
                  ),
                  tooltip: 'Select Audio Track',
                  onSelected: (track) {
                    ref
                        .read(mediaSessionControllerProvider.notifier)
                        .selectAudioTrack(track);
                  },
                  itemBuilder: (context) {
                    return audioTracks.map((a) {
                      return PopupMenuItem<AudioTrack>(
                        value: a,
                        child: Text('${a.label} (${a.language ?? 'unknown'})'),
                      );
                    }).toList();
                  },
                ),
              ],
              // Nút Bật/Tắt Lồng tiếng (AI Dubbing)
              IconButton(
                icon: Icon(
                  ref.watch(dubbingControllerProvider)
                      ? Icons.record_voice_over
                      : Icons.voice_over_off,
                  size: 18,
                  color: ref.watch(dubbingControllerProvider)
                      ? const Color(0xFF7C5CFC)
                      : Colors.white,
                ),
                tooltip: 'AI Vietnamese Dubbing',
                onPressed: () =>
                    ref.read(dubbingControllerProvider.notifier).toggleDubbing(),
              ),
              if (subtitleTracks.isNotEmpty) ...[
                PopupMenuButton<PlayerSubtitleTrack?>(
                  icon: const Icon(
                    Icons.subtitles,
                    size: 18,
                    color: Colors.white,
                  ),
                  tooltip: 'Select Subtitle Track',
                  onSelected: (track) {
                    ref
                        .read(mediaSessionControllerProvider.notifier)
                        .selectSubtitleTrack(track);
                  },
                  itemBuilder: (context) {
                    return [
                      const PopupMenuItem<PlayerSubtitleTrack?>(
                        value: null,
                        child: Text('Off / AI Pipeline Default'),
                      ),
                      ...subtitleTracks.map((s) {
                        return PopupMenuItem<PlayerSubtitleTrack?>(
                          value: s,
                          child: Text('${s.label} [${s.classification.name}]'),
                        );
                      }),
                    ];
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
