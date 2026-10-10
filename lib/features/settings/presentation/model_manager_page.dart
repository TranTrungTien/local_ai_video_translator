import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/model_manager_repository.dart';
import '../domain/model_manifest.dart';

class ModelManagerPage extends ConsumerStatefulWidget {
  const ModelManagerPage({super.key});

  @override
  ConsumerState<ModelManagerPage> createState() => _ModelManagerPageState();
}

class _ModelManagerPageState extends ConsumerState<ModelManagerPage> {
  final Map<String, ModelDownloadProgress> _progressMap = {};

  @override
  void initState() {
    super.initState();
    ref.read(modelManagerRepositoryProvider).progressStream.listen((progress) {
      if (!mounted) return;
      setState(() {
        _progressMap[progress.modelId] = progress;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(modelManagerRepositoryProvider);
    final manifests = ModelManagerRepository.defaultManifests;

    return Scaffold(
      appBar: AppBar(title: const Text('Local AI Model Manager')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: manifests.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final manifest = manifests[index];
          final progress = _progressMap[manifest.id];

          return _ModelCard(manifest: manifest, progress: progress, repo: repo);
        },
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
    final sizeMb = (manifest.bytes / (1024 * 1024)).toStringAsFixed(1);
    final isDownloading = progress?.state == ModelDownloadState.downloading;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_typeIcon(manifest.type), color: const Color(0xFF7C5CFC)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        manifest.id,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${manifest.type.name.toUpperCase()} • v${manifest.version} • ${sizeMb}MB',
                        style: const TextStyle(
                          color: Colors.white60,
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
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    }
                    if (isDownloaded) {
                      return IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                        ),
                        onPressed: () => repo.deleteModel(manifest.id),
                        tooltip: 'Delete downloaded model',
                      );
                    }
                    return FilledButton.icon(
                      onPressed: () => repo.downloadModel(manifest),
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Download'),
                    );
                  },
                ),
              ],
            ),
            if (isDownloading && progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress!.progress),
              const SizedBox(height: 4),
              Text(
                'Downloading ${(progress!.downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} / $sizeMb MB',
                style: const TextStyle(fontSize: 11, color: Colors.white60),
              ),
            ],
            if (progress?.state == ModelDownloadState.failed) ...[
              const SizedBox(height: 8),
              Text(
                'Download failed: ${progress?.errorMessage}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(AiModelType type) => switch (type) {
    AiModelType.stt => Icons.mic,
    AiModelType.translation => Icons.translate,
    AiModelType.tts => Icons.record_voice_over,
    AiModelType.vad => Icons.graphic_eq,
  };
}
