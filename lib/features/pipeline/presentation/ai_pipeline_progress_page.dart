import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_components.dart';
import 'ai_scheduler_controller.dart';

class AiPipelineProgressPage extends ConsumerStatefulWidget {
  final double initialProgress;
  final String title;
  final VoidCallback? onNavigateToHome;

  const AiPipelineProgressPage({
    super.key,
    this.initialProgress = 0.68,
    this.title = 'Video TikTok #102 - Hướng dẫn AI',
    this.onNavigateToHome,
  });

  @override
  ConsumerState<AiPipelineProgressPage> createState() => _AiPipelineProgressPageState();
}

class _AiPipelineProgressPageState extends ConsumerState<AiPipelineProgressPage> {
  late double _progress;

  @override
  void initState() {
    super.initState();
    _progress = widget.initialProgress;
  }

  @override
  Widget build(BuildContext context) {
    final aiSchedulerController = ref.watch(aiSchedulerProvider.notifier);
    final aiState = ref.watch(aiSchedulerProvider);
    final activeSource = aiSchedulerController.activeSource;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tiến trình Dịch AI'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: activeSource == null ? _buildEmptyState() : _buildActivePipelineView(activeSource, aiState),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        AppGlassCard(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryGlow,
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_motion_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Chưa có tiến trình dịch nào',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Hãy dán liên kết video hoặc chọn file từ Trang chủ để bắt đầu dịch phụ đề & lồng tiếng AI tiếng Việt.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              GlowButton(
                label: 'Đến Trang chủ Dịch Video',
                icon: Icons.add_link_rounded,
                onPressed: widget.onNavigateToHome ?? () => context.go('/'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // History Section in Empty State
        const Text(
          'Các tác vụ đã hoàn thành gần đây',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),

        _buildHistoryCard(
          title: 'Hướng dẫn AI Video Translation bằng Whisper',
          source: 'YouTube • 12:45',
          status: 'Hoàn thành 100%',
          statusColor: AppColors.success,
        ),
        const SizedBox(height: 10),
        _buildHistoryCard(
          title: 'Video TikTok công nghệ ngắn #102',
          source: 'TikTok • 01:30',
          status: 'Đã lưu đệm',
          statusColor: AppColors.cyanAccent,
        ),
      ],
    );
  }

  Widget _buildActivePipelineView(ResolvedSource activeSource, AiSchedulerState aiState) {
    final subtitleProgress = aiState.subtitleReadyUntil.inMilliseconds /
        (activeSource.capability.duration?.inMilliseconds ?? 1.0);
    final dubProgress = aiState.dubReadyUntil.inMilliseconds /
        (activeSource.capability.duration?.inMilliseconds ?? 1.0);
    final overallProgress = (subtitleProgress + dubProgress) / 2.0;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Video Title & Subtitle Badge
        AppGlassCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppColors.primaryGlow,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                child: const Icon(
                  Icons.movie_filter_rounded,
                  color: AppColors.primaryLight,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activeSource.input,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Text(
                          'Tiếng Anh -> Tiếng Việt',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        PillBadge(
                          label: aiState.activeSourceStrategy,
                          backgroundColor: AppColors.surface,
                          textColor: AppColors.primaryLight,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // Circular Progress Gauge Center
        Center(
          child: ProgressGauge(
            progress: overallProgress,
            title: 'Tiến độ Tổng thể',
            subtitle: 'Phụ đề: ${(subtitleProgress * 100).toInt()}% | Lồng tiếng: ${(dubProgress * 100).toInt()}%',
            size: 200,
          ),
        ),
        const SizedBox(height: 28),

        // Metrics Row
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                icon: Icons.speed_rounded,
                label: 'Tốc độ Dịch',
                value: '1.8x Realtime',
                color: AppColors.cyanAccent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                icon: Icons.memory_rounded,
                label: 'Thiết bị NPU',
                value: 'High Tier (GPU)',
                color: AppColors.primaryLight,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                icon: Icons.subtitles_rounded,
                label: 'Đã tạo',
                value: '142 Phụ đề',
                color: AppColors.success,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Checklist Pipeline Steps Header
        const Text(
          'Danh sách Nhiệm vụ AI Pipeline',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),

        // Steps Checklist Card
        AppGlassCard(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: const Column(
            children: [
              StepTimelineTile(
                title: 'Tách Âm thanh 16kHz PCM Mono',
                subtitle: 'Đã hoàn thành bóc tách luồng âm thanh gốc',
                stepState: AppStepState.completed,
              ),
              StepTimelineTile(
                title: 'Speech-to-Text (Whisper AI Engine)',
                subtitle: 'Đang nhận dạng giọng nói & tạo mốc thời gian (PTS)',
                stepState: AppStepState.active,
              ),
              StepTimelineTile(
                title: 'Dịch thuật Neural Sang Tiếng Việt',
                subtitle: 'Tối ưu ngữ cảnh & ghép nối phụ đề',
                stepState: AppStepState.pending,
              ),
              StepTimelineTile(
                title: 'Tổng hợp Giọng nói Lồng tiếng (TTS)',
                subtitle: 'Tạo luồng âm thanh song song cho Player',
                stepState: AppStepState.pending,
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  side: const BorderSide(color: AppColors.surfaceCardBorder),
                ),
                icon: const Icon(Icons.pause_circle_outline_rounded, size: 20),
                label: const Text('Tạm dừng'),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã tạm dừng tiến trình AI')),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlowButton(
                label: 'Mở Trình phát',
                icon: Icons.play_arrow_rounded,
                onPressed: () {
                  if (activeSource != null) {
                    context.push('/player', extra: activeSource);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return AppGlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard({
    required String title,
    required String source,
    required String status,
    required Color statusColor,
  }) {
    return AppGlassCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceCardBorder),
            ),
            child: const Icon(
              Icons.play_circle_fill_rounded,
              color: AppColors.primaryLight,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  source,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PillBadge(
            label: status,
            backgroundColor: statusColor.withValues(alpha: 0.15),
            textColor: statusColor,
            borderColor: statusColor.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}
