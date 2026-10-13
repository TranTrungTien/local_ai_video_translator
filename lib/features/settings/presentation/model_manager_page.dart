import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_components.dart';
import '../data/model_manager_repository.dart';
import '../domain/model_manifest.dart';

class ModelManagerPage extends ConsumerStatefulWidget {
  const ModelManagerPage({super.key});

  @override
  ConsumerState<ModelManagerPage> createState() => _ModelManagerPageState();
}

class _ModelManagerPageState extends ConsumerState<ModelManagerPage> {
  final Map<String, ModelDownloadProgress> _progressMap = {};
  StreamSubscription<ModelDownloadProgress>? _progressSub;

  @override
  void initState() {
    super.initState();
    _progressSub = ref
        .read(modelManagerRepositoryProvider)
        .progressStream
        .listen((progress) {
          if (!mounted) return;
          setState(() {
            _progressMap[progress.modelId] = progress;
          });
        });
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(modelManagerRepositoryProvider);
    final manifests = ModelManagerRepository.defaultManifests;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Quản lý AI Models Offline'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Storage Summary Card
            AppGlassCard(
              padding: const EdgeInsets.all(20),
              child: const Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.storage_rounded, color: AppColors.cyanAccent),
                      SizedBox(width: 12),
                      Text(
                        'Bộ nhớ AI',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: 0.15,
                    backgroundColor: AppColors.surfaceCardBorder,
                    color: AppColors.cyanAccent,
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Đã sử dụng: 1.2 GB',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        'Trống: 124 GB',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Các Model khả dụng',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),

            ...manifests.map((manifest) {
              final progress = _progressMap[manifest.id];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ModelCard(
                  manifest: manifest,
                  progress: progress,
                  repo: repo,
                ),
              );
            }),

            const SizedBox(height: 40),
            const Center(
              child: Text(
                'Lưu ý: Bạn nên tải qua Wi-Fi để tiết kiệm dữ liệu di động.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.manifest,
    required this.progress,
    required this.repo,
  });

  final AiModelManifest manifest;
  final ModelDownloadProgress? progress;
  final ModelManagerRepository repo;

  @override
  Widget build(BuildContext context) {
    final sizeMb = (manifest.totalBytes / (1024 * 1024)).toStringAsFixed(1);
    final isDownloading = progress?.state == ModelDownloadState.downloading;
    final isFailed = progress?.state == ModelDownloadState.failed;
    final isReady = progress?.state == ModelDownloadState.ready;

    return AppGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _typeIcon(manifest.type),
                  color: AppColors.primaryLight,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _friendlyName(manifest.id),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${manifest.version} • $sizeMb MB',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              FutureBuilder<bool>(
                future: repo.isModelDownloaded(manifest.id),
                builder: (context, snapshot) {
                  final isDownloaded = snapshot.data ?? false;

                  if (isDownloading) {
                    return const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primaryLight,
                      ),
                    );
                  }

                  if (isDownloaded || isReady) {
                    return IconButton(
                      icon: const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.success,
                      ),
                      onPressed: () => _showDeleteDialog(context),
                    );
                  }

                  return IconButton(
                    icon: const Icon(
                      Icons.download_rounded,
                      color: AppColors.primaryLight,
                    ),
                    onPressed: () => repo.downloadModel(manifest),
                  );
                },
              ),
            ],
          ),
          if (isDownloading && progress != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress!.progress,
                minHeight: 6,
                backgroundColor: AppColors.surfaceCardBorder,
                valueColor: const AlwaysStoppedAnimation(
                  AppColors.primaryLight,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Đang tải... ${(progress!.progress * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  '${(progress!.downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} / $sizeMb MB',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
          if (isFailed) ...[
            const SizedBox(height: 8),
            Text(
              'Lỗi: ${progress?.errorMessage ?? "Tải thất bại"}',
              style: const TextStyle(color: AppColors.error, fontSize: 11),
            ),
            TextButton(
              onPressed: () => repo.downloadModel(manifest),
              child: const Text('Thử lại', style: TextStyle(fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: const Text(
          'Xóa Model?',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa model ${manifest.id}? Bạn sẽ cần tải lại để sử dụng tính năng này.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () {
              repo.deleteModel(manifest.id);
              Navigator.pop(context);
            },
            child: const Text('Xóa', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  String _friendlyName(String id) {
    if (id.contains('whisper')) return 'Whisper STT (Nhận dạng giọng nói)';
    if (id.contains('opus')) return 'Opus-MT (Dịch Anh-Việt)';
    if (id.contains('piper')) return 'Piper TTS (Lồng tiếng Việt)';
    if (id.contains('silero')) return 'Silero VAD (Lọc tiếng động)';
    return id;
  }

  IconData _typeIcon(AiModelType type) => switch (type) {
    AiModelType.stt => Icons.mic_rounded,
    AiModelType.translation => Icons.translate_rounded,
    AiModelType.tts => Icons.record_voice_over_rounded,
    AiModelType.vad => Icons.graphic_eq_rounded,
  };
}
