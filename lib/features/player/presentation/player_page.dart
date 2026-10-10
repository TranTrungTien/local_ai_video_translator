import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../pipeline/presentation/ai_buffer_panel.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import '../../source_resolver/presentation/source_inspector_page.dart';
import 'embedded_player_view.dart';
import 'native_player_view.dart';

class PlayerPage extends StatelessWidget {
  const PlayerPage({required this.source, super.key});
  final ResolvedSource source;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              source.input.isNotEmpty ? source.input : 'AI Video Stream Player',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${source.kind.name.toUpperCase()} • ${source.playbackMode.name.toUpperCase()}',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, color: Colors.white),
            tooltip: 'Nguồn & Inspector',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SourceInspectorPage(source: source),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            tooltip: 'Cài đặt AI',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: source.playbackMode == PlaybackMode.native
                  ? NativePlayerView(source: source)
                  : EmbeddedPlayerView(source: source),
            ),
            AiBufferPanel(source: source),
          ],
        ),
      ),
    );
  }
}
