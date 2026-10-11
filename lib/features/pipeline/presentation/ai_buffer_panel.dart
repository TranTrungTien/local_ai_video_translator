import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../source_resolver/domain/entities/resolved_source.dart';
import '../domain/buffer_policy.dart';
import 'ai_scheduler_controller.dart';
import '../data/performance_monitor.dart';
import '../../../core/diagnostics/presentation/diagnostic_log_overlay.dart';

class AiBufferPanel extends ConsumerWidget {
  const AiBufferPanel({required this.source, super.key});
  final ResolvedSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiState = ref.watch(aiSchedulerProvider);
    final isNative = source.playbackMode == PlaybackMode.native;

    final aheadSeconds = aiState.subtitleAhead.inSeconds.clamp(0, 999);
    final modeColor = switch (aiState.workMode) {
      AiWorkMode.starting => Colors.purpleAccent,
      AiWorkMode.blocked => Colors.redAccent,
      AiWorkMode.turbo => Colors.orangeAccent,
      AiWorkMode.normal => Colors.greenAccent,
      AiWorkMode.eco => Colors.blueAccent,
      AiWorkMode.paused => Colors.grey,
    };

    return Material(
      color: const Color(0xFF14141A),
      elevation: 4,
      child: StreamBuilder<PerformanceMetrics>(
        stream: PerformanceMonitor.instance.metricsStream,
        builder: (context, snapshot) {
          final metrics = snapshot.data ?? PerformanceMonitor.instance.current;
          
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      isNative ? Icons.auto_awesome : Icons.language,
                      color: const Color(0xFF7C5CFC),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            aiState.errorMessage ?? aiState.activeSourceStrategy,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: aiState.errorMessage != null ? Colors.redAccent : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'RTF: STT ${metrics.sttRtf.toStringAsFixed(2)}x | TTS ${metrics.ttsRtf.toStringAsFixed(2)}x',
                            style: const TextStyle(fontSize: 10, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => const SizedBox(
                            height: 600,
                            child: ClipRRect(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                              child: Material(child: DiagnosticLogOverlay()),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: modeColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: modeColor, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (aiState.workMode == AiWorkMode.blocked)
                              const Icon(Icons.bug_report, color: Colors.white, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              aiState.workMode.name.toUpperCase(),
                              style: TextStyle(
                                color: modeColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text(
                      'Subtitle Lookahead Buffer:',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const Spacer(),
                    Text(
                      '${aheadSeconds}s ahead',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (aheadSeconds / 120.0).clamp(0.0, 1.0),
                    backgroundColor: Colors.white12,
                    color: modeColor,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          );
        }
      ),
    );
  }
}
