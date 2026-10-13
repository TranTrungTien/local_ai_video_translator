import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  VideoController? _videoController;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctrl = ref.read(mediaSessionControllerProvider.notifier);
      await ctrl.openSource(widget.source);

      final session = ref.read(nativeMediaSessionProvider);
      final p = session.player;

      if (p != null && mounted) {
        final controller = VideoController(p);
        if (mounted) {
          setState(() {
            _videoController = controller;
          });
        }
      }

      ref.read(aiSchedulerProvider.notifier).initializeForSource(widget.source);
    });
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
    final player = ref.read(nativeMediaSessionProvider).player;

    ref.listen<AiSchedulerState>(aiSchedulerProvider, (previous, next) {
      if (player == null) return;

      if (next.isBufferingForAi && player.state.playing) {
        ref.read(mediaSessionControllerProvider.notifier).pause();
      } else if (!next.isBufferingForAi && previous?.isBufferingForAi == true) {
        ref.read(mediaSessionControllerProvider.notifier).play();
      }
    });

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
                onPressed: () => ref
                    .read(dubbingControllerProvider.notifier)
                    .toggleDubbing(),
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
