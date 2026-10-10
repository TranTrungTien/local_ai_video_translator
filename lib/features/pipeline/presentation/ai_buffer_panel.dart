import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../source_resolver/domain/entities/resolved_source.dart';
import '../domain/buffer_policy.dart';
import 'ai_scheduler_controller.dart';

class AiBufferPanel extends ConsumerWidget {
  const AiBufferPanel({required this.source, super.key});
  final ResolvedSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiState = ref.watch(aiSchedulerProvider);
    final isNative = source.playbackMode == PlaybackMode.native;

    final aheadSeconds = aiState.subtitleAhead.inSeconds.clamp(0, 999);
    final modeColor = switch (aiState.workMode) {
      AiWorkMode.blocked => Colors.redAccent,
      AiWorkMode.turbo => Colors.orangeAccent,
      AiWorkMode.normal => Colors.greenAccent,
      AiWorkMode.eco => Colors.blueAccent,
      AiWorkMode.paused => Colors.grey,
    };

    return Material(
      color: const Color(0xFF14141A),
      elevation: 4,
      child: Padding(
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
                        aiState.activeSourceStrategy,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Subtitle Pipeline: Priority 1 (Existing VI) -> Priority 2 (Translate) -> Priority 3 (STT)',
                        style: TextStyle(fontSize: 10, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: modeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: modeColor, width: 1),
                  ),
                  child: Text(
                    aiState.workMode.name.toUpperCase(),
                    style: TextStyle(
                      color: modeColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
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
      ),
    );
  }
}
