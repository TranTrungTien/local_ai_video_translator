# Review Module: 06. Subtitles, Home & Model Manager

## Included Files (12 files)

```text
lib/features/home/presentation/home_page.dart
lib/features/settings/data/model_manager_repository.dart
lib/features/settings/domain/model_manifest.dart
lib/features/settings/presentation/ai_settings_page.dart
lib/features/settings/presentation/model_manager_page.dart
lib/features/subtitles/data/subtitle_language_detector.dart
lib/features/subtitles/data/subtitle_parser.dart
lib/features/subtitles/data/subtitle_repository_impl.dart
lib/features/subtitles/domain/entities/subtitle_document.dart
lib/features/subtitles/domain/entities/subtitle_track.dart
lib/features/subtitles/domain/repositories/subtitle_repository.dart
lib/features/subtitles/domain/subtitle_selection_policy.dart
```

## lib/features/home/presentation/home_page.dart
```dart:lib/features/home/presentation/home_page.dart
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_components.dart';
import '../../source_resolver/presentation/source_resolver_controller.dart';
import '../../../core/utils/shared_input_parser.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _controller = TextEditingController();
  StreamSubscription<List<SharedMediaFile>>? _shareSubscription;

  bool _isPickingFile = false;

  @override
  void initState() {
    super.initState();
    _listenToShares();
  }

  void _listenToShares() {
    _shareSubscription = ReceiveSharingIntent.instance.getMediaStream().listen(
      _consumeSharedItems,
    );
    ReceiveSharingIntent.instance.getInitialMedia().then(_consumeSharedItems);
  }

  void _consumeSharedItems(List<SharedMediaFile> items) {
    if (items.isEmpty || !mounted) return;

    final rawPath = items.first.path;
    final value = SharedInputParser.extract(rawPath);

    // Reset so the same intent doesn't trigger again on rebuild
    ReceiveSharingIntent.instance.reset();

    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy liên kết video hợp lệ.')),
      );
      return;
    }

    _controller.text = value;
    unawaited(_resolve(value));
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() {
        _controller.text = data.text!;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã dán liên kết từ bộ nhớ tạm!'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Future<void> _openFile() async {
    if (_isPickingFile) return;
    setState(() => _isPickingFile = true);

    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.video);
      final path = result?.files.firstOrNull?.path;
      if (path != null) await _resolve(path);
    } catch (e) {
      debugPrint('Error picking file: $e');
    } finally {
      if (mounted) {
        setState(() => _isPickingFile = false);
      }
    }
  }

  Future<void> _pickSubtitle() async {
    if (_isPickingFile) return;
    setState(() => _isPickingFile = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt', 'ass'],
      );
      final path = result?.files.firstOrNull?.path;
      if (path != null && mounted) {
        ref.read(sourceResolverControllerProvider.notifier).setManualSubtitle(path);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã chọn phụ đề: ${result?.files.first.name}'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error picking subtitle: $e');
    } finally {
      if (mounted) {
        setState(() => _isPickingFile = false);
      }
    }
  }

  Future<void> _resolve(String value) async {
    if (value.trim().isEmpty) return;
    context.push('/analysis', extra: value.trim());
  }

  @override
  void dispose() {
    _shareSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolver = ref.watch(sourceResolverControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Top Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: AppColors.primaryGlow,
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.subtitles_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AI Video Translator',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              'Dịch phụ đề & Lồng tiếng AI On-Device',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.surfaceCardBorder,
                          ),
                        ),
                        child: const Icon(
                          Icons.download_for_offline_rounded,
                          color: AppColors.primaryLight,
                          size: 20,
                        ),
                      ),
                      tooltip: 'Quản lý AI Models',
                      onPressed: () => context.push('/models'),
                    ),
                  ],
                ),
              ),
            ),

            // Hero Input Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: AppGlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.link_rounded,
                            color: AppColors.primaryLight,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Nhập đường dẫn Video hoặc Trang Web',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _controller,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        onSubmitted: _resolve,
                        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'https://youtube.com/watch?v=... hoặc tiktok.com/...',
                          suffixIcon: IconButton(
                            icon: const Icon(
                              Icons.content_paste_rounded,
                              color: AppColors.primaryLight,
                              size: 20,
                            ),
                            tooltip: 'Dán liên kết',
                            onPressed: _pasteFromClipboard,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GlowButton(
                        label: 'Phân tích & Dịch ngay',
                        icon: Icons.auto_awesome_rounded,
                        isLoading: resolver.isLoading,
                        onPressed: () => _resolve(_controller.text),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 3 Quick Action Cards
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildActionTile(
                        icon: Icons.assignment_turned_in_rounded,
                        title: 'Dán Link',
                        subtitle: 'Từ Bộ nhớ',
                        color: AppColors.primaryLight,
                        onTap: _pasteFromClipboard,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildActionTile(
                        icon: Icons.video_library_rounded,
                        title: 'File Video',
                        subtitle: 'Từ Thiết bị',
                        color: AppColors.cyanAccent,
                        onTap: _openFile,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildActionTile(
                        icon: Icons.subtitles_outlined,
                        title: 'File Phụ đề',
                        subtitle: 'SRT / VTT',
                        color: AppColors.secondary,
                        onTap: _pickSubtitle,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // AI Engine Status Banner
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primaryGlow.withValues(alpha: 0.15),
                        AppColors.cyanGlow.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primaryLight.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.memory_rounded,
                          color: AppColors.primaryLight,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'AI Engine: Whisper Base',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(width: 6),
                                PillBadge(
                                  label: 'Ready',
                                  backgroundColor: Color(0x3310B981),
                                  textColor: AppColors.success,
                                ),
                              ],
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Sẵn sàng dịch Offline tiếng Việt không cần mạng.',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Supported Sources Grid Header
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Text(
                  'Nguồn Nền tảng Hỗ trợ',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),

            // Supported Sources List
            SliverToBoxAdapter(
              child: SizedBox(
                height: 72,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _buildSourceChip('YouTube', Icons.play_circle_fill, Colors.red),
                    _buildSourceChip('TikTok', Icons.music_note_rounded, Colors.cyan),
                    _buildSourceChip('Facebook', Icons.facebook_rounded, Colors.blue),
                    _buildSourceChip('HLS / MP4', Icons.stream_rounded, AppColors.primaryLight),
                    _buildSourceChip('Local File', Icons.folder_rounded, AppColors.success),
                  ],
                ),
              ),
            ),

            // Recent Translations Header
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Lịch sử Dịch gần đây',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Xem tất cả',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.primaryLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Recent Items List
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildHistoryCard(
                    title: 'Hướng dẫn AI Video Translation bằng Whisper',
                    source: 'YouTube • 12:45',
                    status: 'Hoàn thành 100%',
                    statusColor: AppColors.success,
                    onTap: () => context.push('/pipeline'),
                  ),
                  const SizedBox(height: 10),
                  _buildHistoryCard(
                    title: 'Video TikTok công nghệ ngắn #102',
                    source: 'TikTok • 01:30',
                    status: 'Đang xử lý 68%',
                    statusColor: AppColors.cyanAccent,
                    onTap: () => context.push('/pipeline'),
                  ),
                ]),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 30),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return AppGlassCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceChip(String label, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceCardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
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
    required VoidCallback onTap,
  }) {
    return AppGlassCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.surfaceCardBorder),
            ),
            child: const Icon(
              Icons.play_circle_fill_rounded,
              color: AppColors.primaryLight,
              size: 28,
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

```

## lib/features/settings/data/model_manager_repository.dart
```dart:lib/features/settings/data/model_manager_repository.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/dio_provider.dart';
import '../../../core/utils/sha256_util.dart';
import '../domain/model_manifest.dart';

enum ModelDownloadState { notDownloaded, downloading, ready, failed }

class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.modelId,
    required this.state,
    required this.downloadedBytes,
    required this.totalBytes,
    this.currentFile,
    this.errorMessage,
  });

  final String modelId;
  final ModelDownloadState state;
  final int downloadedBytes;
  final int totalBytes;
  final String? currentFile;
  final String? errorMessage;

  double get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
}

class ModelDownloadException implements Exception {
  ModelDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ModelIntegrityException implements Exception {
  ModelIntegrityException(this.message);
  final String message;
  @override
  String toString() => 'ModelIntegrityException: $message';
}

const String _whisperBase =
    'https://huggingface.co/Xenova/whisper-tiny/resolve/e1309fbf61a10485319f046062a3b5dca5b7b9fb';
const String _opusBase =
    'https://huggingface.co/Xenova/opus-mt-en-vi/resolve/30bcd461c0d7338ad106b36314d3eedc2d4e998c';
const String _piperBase =
    'https://huggingface.co/rhasspy/piper-voices/resolve/de3dcfdf1912bb49726dc4aa11c26017ce2ac62a/vi/vi_VN/25hours_single/low';
const String _sileroBase =
    'https://raw.githubusercontent.com/snakers4/silero-vad/60b7ffa243625ebdc1070275a29f18c87843786a/src/silero_vad/data';

class ModelManagerRepository {
  ModelManagerRepository(this._dio);

  final Dio _dio;
  final _progressController =
      StreamController<ModelDownloadProgress>.broadcast();
  final Set<String> _active = <String>{};

  static const String _readyMarker = '.ready';

  Stream<ModelDownloadProgress> get progressStream =>
      _progressController.stream;

  static const List<AiModelManifest> defaultManifests = [
    AiModelManifest(
      id: 'stt_whisper_tiny_en_vi',
      type: AiModelType.stt,
      version: '1.1.0',
      languages: ['en', 'vi', 'ja', 'zh'],
      files: [
        ModelFile(
          name: 'encoder_model_quantized.onnx',
          url: '$_whisperBase/onnx/encoder_model_quantized.onnx',
          bytes: 10124910,
          sha256:
              'fd9d995b9dcb0520f0dbf6cf68651af639fc385f594d9d876e69ca2802dc438e',
        ),
        ModelFile(
          name: 'decoder_model_merged_quantized.onnx',
          url: '$_whisperBase/onnx/decoder_model_merged_quantized.onnx',
          bytes: 30727765,
          sha256:
              '6c0c125986b007d2e3734bec84c18bda0152071b90b87fadac6d7764499927a0',
        ),
        ModelFile(
          name: 'config.json',
          url: '$_whisperBase/config.json',
          bytes: 2250,
        ),
        ModelFile(
          name: 'generation_config.json',
          url: '$_whisperBase/generation_config.json',
          bytes: 3720,
        ),
        ModelFile(
          name: 'preprocessor_config.json',
          url: '$_whisperBase/preprocessor_config.json',
          bytes: 339,
        ),
        ModelFile(
          name: 'tokenizer.json',
          url: '$_whisperBase/tokenizer.json',
          bytes: 2480000,
        ),
        ModelFile(
          name: 'vocab.json',
          url: '$_whisperBase/vocab.json',
          bytes: 1040000,
        ),
        ModelFile(
          name: 'merges.txt',
          url: '$_whisperBase/merges.txt',
          bytes: 494000,
        ),
      ],
    ),
    AiModelManifest(
      id: 'translate_opus_en_vi',
      type: AiModelType.translation,
      version: '1.3.0',
      languages: ['en', 'vi'],
      files: [
        ModelFile(
          name: 'encoder_model_quantized.onnx',
          url: '$_opusBase/onnx/encoder_model_quantized.onnx',
          bytes: 47105950,
          sha256:
              'dfcd7a32be3fdd21cbcf5d354520d626f1768fd6e205ca62a6a11a4641d31f36',
        ),
        ModelFile(
          name: 'decoder_model_merged_quantized.onnx',
          url: '$_opusBase/onnx/decoder_model_merged_quantized.onnx',
          bytes: 54373748,
          sha256:
              '1cfc6a84f9c189e6928c9710b281fae3f1f42d4ffbba109e7b4ec8e31ceb06dd',
        ),
        ModelFile(
          name: 'config.json',
          url: '$_opusBase/config.json',
          bytes: 1390,
        ),
        ModelFile(
          name: 'generation_config.json',
          url: '$_opusBase/generation_config.json',
          bytes: 293,
        ),
        ModelFile(
          name: 'source.spm',
          url: '$_opusBase/source.spm',
          bytes: 809000,
        ),
        ModelFile(
          name: 'target.spm',
          url: '$_opusBase/target.spm',
          bytes: 756000,
        ),
        ModelFile(
          name: 'vocab.json',
          url: '$_opusBase/vocab.json',
          bytes: 1300000,
        ),
        ModelFile(
          name: 'tokenizer.json',
          url: '$_opusBase/tokenizer.json',
          bytes: 5160000,
        ),
      ],
    ),
    AiModelManifest(
      id: 'tts_piper_vi_female',
      type: AiModelType.tts,
      version: '1.0.0',
      languages: ['vi'],
      files: [
        ModelFile(
          name: 'vi_VN-25hours_single-low.onnx',
          url: '$_piperBase/vi_VN-25hours_single-low.onnx',
          bytes: 63104526,
          sha256:
              '266945c4a80cb3301450c8ba6fcf6ba3542c56cf952a08a8ff3d2d4ff0ab5609',
        ),
        ModelFile(
          name: 'vi_VN-25hours_single-low.onnx.json',
          url: '$_piperBase/vi_VN-25hours_single-low.onnx.json',
          bytes: 4180,
        ),
      ],
    ),
    AiModelManifest(
      id: 'vad_silero',
      type: AiModelType.vad,
      version: 'git-60b7ffa',
      languages: ['all'],
      files: [
        ModelFile(
          name: 'silero_vad.onnx',
          url: '$_sileroBase/silero_vad.onnx',
          bytes: 2327524,
          sha256:
              '1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3',
        ),
      ],
    ),
  ];

  AiModelManifest? manifestById(String modelId) {
    for (final m in defaultManifests) {
      if (m.id == modelId) return m;
    }
    return null;
  }

  Future<Directory> get _modelsDir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> getModelDir(String modelId) async {
    final root = await _modelsDir;
    final dir = Directory('${root.path}/$modelId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> getModelFile(String modelId, String fileName) async {
    final dir = await getModelDir(modelId);
    return File('${dir.path}/$fileName');
  }

  Future<bool> isModelDownloaded(String modelId) async {
    final manifest = manifestById(modelId);
    if (manifest == null) return false;

    final dir = await getModelDir(modelId);
    final marker = File('${dir.path}/$_readyMarker');
    if (!await marker.exists()) return false;

    try {
      final data = jsonDecode(await marker.readAsString());
      if (data is! Map || data['version'] != manifest.version) return false;
    } catch (_) {
      return false;
    }

    for (final f in manifest.files) {
      final file = File('${dir.path}/${f.name}');
      if (!await file.exists()) return false;
      if (f.sha256 != null && await file.length() != f.bytes) return false;
    }
    return true;
  }

  Future<void> downloadModel(AiModelManifest manifest) async {
    if (!_active.add(manifest.id)) return;

    var completedBytes = 0;
    try {
      final dir = await getModelDir(manifest.id);
      final marker = File('${dir.path}/$_readyMarker');
      if (await marker.exists()) await marker.delete();

      for (final spec in manifest.files) {
        await _downloadFile(
          manifest: manifest,
          spec: spec,
          dir: dir,
          completedBytes: completedBytes,
        );
        completedBytes += spec.bytes;
      }

      await marker.writeAsString(
        jsonEncode({
          'version': manifest.version,
          'files': manifest.files.map((f) => f.name).toList(),
        }),
      );

      _emit(
        ModelDownloadProgress(
          modelId: manifest.id,
          state: ModelDownloadState.ready,
          downloadedBytes: manifest.totalBytes,
          totalBytes: manifest.totalBytes,
        ),
      );
    } catch (e) {
      _emit(
        ModelDownloadProgress(
          modelId: manifest.id,
          state: ModelDownloadState.failed,
          downloadedBytes: completedBytes,
          totalBytes: manifest.totalBytes,
          errorMessage: e.toString(),
        ),
      );
    } finally {
      _active.remove(manifest.id);
    }
  }

  Future<void> _downloadFile({
    required AiModelManifest manifest,
    required ModelFile spec,
    required Directory dir,
    required int completedBytes,
  }) async {
    final target = File('${dir.path}/${spec.name}');
    final tmp = File('${target.path}.tmp');

    if (await target.exists()) {
      try {
        await _verify(target, spec);
        return;
      } on ModelIntegrityException {
        await target.delete();
      }
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      var existing = await tmp.exists() ? await tmp.length() : 0;

      if (spec.sha256 != null && existing > spec.bytes) {
        await tmp.delete();
        existing = 0;
      }

      try {
        final alreadyComplete = spec.sha256 != null && existing == spec.bytes;
        if (!alreadyComplete) {
          await _dio.download(
            spec.url,
            tmp.path,
            options: Options(
              headers: existing > 0 ? {'Range': 'bytes=$existing-'} : null,
              receiveTimeout: const Duration(minutes: 5),
            ),
            fileAccessMode: existing > 0
                ? FileAccessMode.append
                : FileAccessMode.write,
            deleteOnError: false,
            onReceiveProgress: (received, total) {
              _emit(
                ModelDownloadProgress(
                  modelId: manifest.id,
                  state: ModelDownloadState.downloading,
                  downloadedBytes: completedBytes + existing + received,
                  totalBytes: manifest.totalBytes,
                  currentFile: spec.name,
                ),
              );
            },
          );
        }

        await _verify(tmp, spec);

        if (await target.exists()) await target.delete();
        await tmp.rename(target.path);
        return;
      } on ModelIntegrityException {
        if (await tmp.exists()) await tmp.delete();
        if (attempt == 1) rethrow;
      } on DioException catch (e) {
        if (e.response?.statusCode == 416 && attempt == 0) {
          if (await tmp.exists()) await tmp.delete();
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _verify(File file, ModelFile spec) async {
    final length = await file.length();
    if (length == 0) {
      throw ModelIntegrityException('${spec.name}: file rỗng');
    }

    final expectedHash = spec.sha256;
    if (expectedHash != null) {
      if (length != spec.bytes) {
        throw ModelIntegrityException(
          '${spec.name}: sai kích thước ($length != ${spec.bytes})',
        );
      }
      final actual = await Sha256Util.computeFileHash(file);
      if (actual.toLowerCase() != expectedHash.toLowerCase()) {
        throw ModelIntegrityException('${spec.name}: sai SHA-256');
      }
    } else if (spec.name.endsWith('.json')) {
      try {
        jsonDecode(await file.readAsString());
      } catch (_) {
        throw ModelIntegrityException('${spec.name}: JSON không hợp lệ');
      }
    }
  }

  Future<void> deleteModel(String modelId) async {
    final root = await _modelsDir;
    final dir = Directory('${root.path}/$modelId');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _emit(
      ModelDownloadProgress(
        modelId: modelId,
        state: ModelDownloadState.notDownloaded,
        downloadedBytes: 0,
        totalBytes: 0,
      ),
    );
  }

  void _emit(ModelDownloadProgress p) {
    if (!_progressController.isClosed) _progressController.add(p);
  }

  void dispose() {
    _progressController.close();
  }
}

final modelManagerRepositoryProvider = Provider<ModelManagerRepository>((ref) {
  final repo = ModelManagerRepository(ref.watch(dioProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

```

## lib/features/settings/domain/model_manifest.dart
```dart:lib/features/settings/domain/model_manifest.dart
enum AiModelType { stt, translation, tts, vad }

/// Một file thuộc về model (một model có thể gồm nhiều file).
class ModelFile {
  const ModelFile({
    required this.name,
    required this.url,
    required this.bytes,
    this.sha256,
  });

  /// Tên file khi lưu trên máy (nằm trong thư mục models/modelId/).
  final String name;

  /// URL đã ghim theo commit để nội dung không đổi.
  final String url;

  /// Kích thước chính xác (byte) nếu có [sha256]; nếu không thì chỉ là
  /// số xấp xỉ, dùng để hiển thị tiến độ.
  final int bytes;

  /// SHA-256 (64 ký tự hex). Null với file nhỏ chưa tính hash:
  /// khi đó chỉ kiểm tra file không rỗng (và JSON hợp lệ nếu là .json).
  final String? sha256;

  Uri get uri => Uri.parse(url);
}

class AiModelManifest {
  const AiModelManifest({
    required this.id,
    required this.type,
    required this.version,
    required this.files,
    required this.languages,
  });

  final String id;
  final AiModelType type;
  final String version;
  final List<ModelFile> files;
  final List<String> languages;

  int get totalBytes => files.fold<int>(0, (sum, f) => sum + f.bytes);
}
```

## lib/features/settings/presentation/ai_settings_page.dart
```dart:lib/features/settings/presentation/ai_settings_page.dart
import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_components.dart';
import 'model_manager_page.dart';

class AiSettingsPage extends StatefulWidget {
  const AiSettingsPage({super.key});

  @override
  State<AiSettingsPage> createState() => _AiSettingsPageState();
}

class _AiSettingsPageState extends State<AiSettingsPage> {
  String _sourceLang = 'Tiếng Anh (Tự động)';
  String _targetLang = 'Tiếng Việt';
  int _qualityIndex = 1; // 0: Lite, 1: Balanced, 2: High
  bool _dualSubtitles = true;
  bool _aiDubbing = true;
  double _voiceSpeed = 1.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt AI & Ngôn ngữ'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Language Selection Card
            const Text(
              'Cặp Ngôn ngữ Dịch',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            AppGlassCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildLangSelectorTile(
                      label: 'Nguồn',
                      value: _sourceLang,
                      icon: Icons.language_rounded,
                      onTap: () {
                        _showLangPicker('Chọn Ngôn ngữ Nguồn', (selected) {
                          setState(() => _sourceLang = selected);
                        });
                      },
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: AppColors.primaryGlow,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.swap_horiz_rounded,
                      color: AppColors.primaryLight,
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: _buildLangSelectorTile(
                      label: 'Đích',
                      value: _targetLang,
                      icon: Icons.translate_rounded,
                      onTap: () {
                        _showLangPicker('Chọn Ngôn ngữ Đích', (selected) {
                          setState(() => _targetLang = selected);
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // AI Quality Selector Header
            const Text(
              'Chế độ & Chất lượng AI Engine',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: _buildQualityCard(
                    index: 0,
                    title: 'Lite (Nhanh)',
                    subtitle: 'Tiết kiệm pin',
                    icon: Icons.bolt_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildQualityCard(
                    index: 1,
                    title: 'Balanced',
                    subtitle: 'Khuyên dùng',
                    icon: Icons.auto_awesome_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildQualityCard(
                    index: 2,
                    title: 'High NPU',
                    subtitle: 'Độ chính xác cao',
                    icon: Icons.psychology_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // AI Options Toggles Card
            const Text(
              'Tùy chọn Phụ đề & Lồng tiếng',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            AppGlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SwitchListTile(
                    activeTrackColor: AppColors.primaryLight,
                    title: const Text(
                      'Phụ đề AI Song ngữ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: const Text(
                      'Hiển thị cả phụ đề gốc và phụ đề tiếng Việt',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    value: _dualSubtitles,
                    onChanged: (val) => setState(() => _dualSubtitles = val),
                  ),
                  const Divider(color: AppColors.surfaceCardBorder),
                  SwitchListTile(
                    activeTrackColor: AppColors.primaryLight,
                    title: const Text(
                      'Lồng tiếng AI (TTS Sync)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    subtitle: const Text(
                      'Tổng hợp giọng nói tiếng Việt đồng bộ theo video',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                    value: _aiDubbing,
                    onChanged: (val) => setState(() => _aiDubbing = val),
                  ),
                  if (_aiDubbing) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Tốc độ giọng đọc AI:',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        ),
                        Text(
                          '${_voiceSpeed.toStringAsFixed(1)}x',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryLight,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _voiceSpeed,
                      min: 0.8,
                      max: 1.5,
                      divisions: 7,
                      onChanged: (val) => setState(() => _voiceSpeed = val),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Storage & Offline Models Banner
            AppGlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.folder_special_rounded, color: AppColors.cyanAccent, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Bộ nhớ Model AI Offline',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ModelManagerPage(),
                            ),
                          );
                        },
                        child: const Text('Quản lý Models'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(
                    value: 0.15,
                    backgroundColor: AppColors.surfaceCardBorder,
                    color: AppColors.cyanAccent,
                  ),
                  const SizedBox(height: 6),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Đã dùng: 1.2 GB (Whisper Base + NMT)',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                      Text(
                        'Trống: 124 GB',
                        style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLangSelectorTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.surfaceCardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(icon, size: 14, color: AppColors.primaryLight),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityCard({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _qualityIndex == index;

    return AppGlassCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      backgroundColor: isSelected ? AppColors.primaryGlow : AppColors.surfaceCard,
      borderColor: isSelected ? AppColors.primaryLight : AppColors.surfaceCardBorder,
      onTap: () => setState(() => _qualityIndex = index),
      child: Column(
        children: [
          Icon(
            icon,
            color: isSelected ? AppColors.primaryLight : AppColors.textMuted,
            size: 22,
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  void _showLangPicker(String title, Function(String) onSelect) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final languages = [
          'Tiếng Anh (Tự động)',
          'Tiếng Việt',
          'Tiếng Trung (Giản thể)',
          'Tiếng Nhật',
          'Tiếng Hàn',
          'Tiếng Pháp',
          'Tiếng Đức',
        ];

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ...languages.map(
                  (lang) => ListTile(
                    title: Text(
                      lang,
                      style: const TextStyle(color: AppColors.textPrimary),
                    ),
                    onTap: () {
                      onSelect(lang);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

```

## lib/features/settings/presentation/model_manager_page.dart
```dart:lib/features/settings/presentation/model_manager_page.dart
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

```

## lib/features/subtitles/data/subtitle_language_detector.dart
```dart:lib/features/subtitles/data/subtitle_language_detector.dart
class SubtitleLanguageDetector {
  const SubtitleLanguageDetector();

  /// Detects or normalizes language code from metadata or text content heuristic.
  String detectLanguage({String? declaredLanguage, String? sampleText}) {
    if (declaredLanguage != null && declaredLanguage.trim().isNotEmpty) {
      final normalized = declaredLanguage.toLowerCase().trim();
      if (normalized.startsWith('vi') || normalized.contains('vietnamese')) {
        return 'vi';
      }
      if (normalized.startsWith('en') || normalized.contains('english')) {
        return 'en';
      }
      if (normalized.startsWith('ja') || normalized.contains('japanese')) {
        return 'ja';
      }
      if (normalized.startsWith('zh') || normalized.contains('chinese')) {
        return 'zh';
      }
      return normalized;
    }

    if (sampleText != null && sampleText.trim().isNotEmpty) {
      return _heuristicDetect(sampleText);
    }

    return 'unknown';
  }

  String _heuristicDetect(String text) {
    // Vietnamese diacritics check
    final vietnameseDiacriticsRx = RegExp(
      r'[ăâđêôơưàằầằắấẫẩẳẵẳằằặặẹẻẽéèẻẽếềểễệỉĩíìịọỏõóòỏõốồổỗộớờởỡợụủũúùủũứừửữựỳỷỹýỵ]',
      caseSensitive: false,
    );

    if (vietnameseDiacriticsRx.hasMatch(text)) {
      return 'vi';
    }

    // Default fallback assumption for foreign sample text
    return 'en';
  }
}

```

## lib/features/subtitles/data/subtitle_parser.dart
```dart:lib/features/subtitles/data/subtitle_parser.dart
import '../../pipeline/domain/ai_pipeline.dart';
import '../domain/entities/subtitle_document.dart';

class SubtitleParser {
  const SubtitleParser();

  List<TimedTextSegment> parseVtt(String content, {String? language}) {
    final doc = parseVttDocument(content, language: language);
    return doc.segments
        .map(
          (s) => TimedTextSegment(
            start: s.start,
            end: s.end,
            text: s.text,
            language: s.language,
          ),
        )
        .toList();
  }

  SubtitleDocument parseVttDocument(String content, {String? language}) {
    final lines = content.split(RegExp(r'\r?\n'));
    final segments = <SubtitleSegment>[];

    Duration? currentStart;
    Duration? currentEnd;
    final textBuffer = StringBuffer();

    final timingRx = RegExp(
      r'(\d{2}:)?(\d{2}):(\d{2})[\.,](\d{3})\s*-->\s*(\d{2}:)?(\d{2}):(\d{2})[\.,](\d{3})',
    );

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (currentStart != null &&
            currentEnd != null &&
            textBuffer.isNotEmpty) {
          final cleanText = _cleanCaptionText(textBuffer.toString());
          if (cleanText.isNotEmpty && currentEnd > currentStart) {
            segments.add(
              SubtitleSegment(
                id: 'vtt_seg_${segments.length}',
                start: currentStart,
                end: currentEnd,
                text: cleanText,
                language: language,
                source: 'WebVTT',
              ),
            );
          }
          currentStart = null;
          currentEnd = null;
          textBuffer.clear();
        }
        continue;
      }

      if (trimmed.startsWith('WEBVTT') ||
          trimmed.startsWith('NOTE') ||
          trimmed.startsWith('STYLE') ||
          trimmed.startsWith('REGION')) {
        continue;
      }

      final match = timingRx.firstMatch(trimmed);
      if (match != null) {
        try {
          currentStart = _parseTimestamp(
            hours: match.group(1),
            minutes: match.group(2)!,
            seconds: match.group(3)!,
            millis: match.group(4)!,
          );
          currentEnd = _parseTimestamp(
            hours: match.group(5),
            minutes: match.group(6)!,
            seconds: match.group(7)!,
            millis: match.group(8)!,
          );
        } catch (_) {
          // Skip malformed timing entry
          currentStart = null;
          currentEnd = null;
        }
      } else if (currentStart != null && currentEnd != null) {
        if (textBuffer.isNotEmpty) textBuffer.write('\n');
        textBuffer.write(trimmed);
      }
    }

    if (currentStart != null && currentEnd != null && textBuffer.isNotEmpty) {
      final cleanText = _cleanCaptionText(textBuffer.toString());
      if (cleanText.isNotEmpty && currentEnd > currentStart) {
        segments.add(
          SubtitleSegment(
            id: 'vtt_seg_${segments.length}',
            start: currentStart,
            end: currentEnd,
            text: cleanText,
            language: language,
            source: 'WebVTT',
          ),
        );
      }
    }

    // Sort and handle overlapping captions gracefully
    segments.sort((a, b) => a.start.compareTo(b.start));

    return SubtitleDocument(
      id: 'vtt_doc_${DateTime.now().millisecondsSinceEpoch}',
      title: 'WebVTT Document',
      language: language ?? 'unknown',
      format: 'WebVTT',
      segments: segments,
    );
  }

  List<TimedTextSegment> parseSrt(String content, {String? language}) {
    final doc = parseSrtDocument(content, language: language);
    return doc.segments
        .map(
          (s) => TimedTextSegment(
            start: s.start,
            end: s.end,
            text: s.text,
            language: s.language,
          ),
        )
        .toList();
  }

  SubtitleDocument parseSrtDocument(String content, {String? language}) {
    final lines = content.split(RegExp(r'\r?\n'));
    final segments = <SubtitleSegment>[];

    Duration? currentStart;
    Duration? currentEnd;
    final textBuffer = StringBuffer();

    final timingRx = RegExp(
      r'(\d{2}):(\d{2}):(\d{2})[\.,](\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2})[\.,](\d{3})',
    );

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (currentStart != null &&
            currentEnd != null &&
            textBuffer.isNotEmpty) {
          final cleanText = _cleanCaptionText(textBuffer.toString());
          if (cleanText.isNotEmpty && currentEnd > currentStart) {
            segments.add(
              SubtitleSegment(
                id: 'srt_seg_${segments.length}',
                start: currentStart,
                end: currentEnd,
                text: cleanText,
                language: language,
                source: 'SRT',
              ),
            );
          }
          currentStart = null;
          currentEnd = null;
          textBuffer.clear();
        }
        continue;
      }

      final match = timingRx.firstMatch(trimmed);
      if (match != null) {
        try {
          currentStart = _parseTimestamp(
            hours: match.group(1),
            minutes: match.group(2)!,
            seconds: match.group(3)!,
            millis: match.group(4)!,
          );
          currentEnd = _parseTimestamp(
            hours: match.group(5),
            minutes: match.group(6)!,
            seconds: match.group(7)!,
            millis: match.group(8)!,
          );
        } catch (_) {
          currentStart = null;
          currentEnd = null;
        }
      } else if (int.tryParse(trimmed) != null && currentStart == null) {
        // SRT sequence index number line
        continue;
      } else if (currentStart != null && currentEnd != null) {
        if (textBuffer.isNotEmpty) textBuffer.write('\n');
        textBuffer.write(trimmed);
      }
    }

    if (currentStart != null && currentEnd != null && textBuffer.isNotEmpty) {
      final cleanText = _cleanCaptionText(textBuffer.toString());
      if (cleanText.isNotEmpty && currentEnd > currentStart) {
        segments.add(
          SubtitleSegment(
            id: 'srt_seg_${segments.length}',
            start: currentStart,
            end: currentEnd,
            text: cleanText,
            language: language,
            source: 'SRT',
          ),
        );
      }
    }

    segments.sort((a, b) => a.start.compareTo(b.start));

    return SubtitleDocument(
      id: 'srt_doc_${DateTime.now().millisecondsSinceEpoch}',
      title: 'SRT Document',
      language: language ?? 'unknown',
      format: 'SRT',
      segments: segments,
    );
  }

  /// Parses TTML (XML-based timed text) format commonly used in DASH manifests.
  SubtitleDocument parseTtmlDocument(String content, {String? language}) {
    final segments = <SubtitleSegment>[];
    try {
      // Simple robust XML <p> element extractor for TTML
      final pRx = RegExp(
        r'<p\s+([^>]*?)>(.*?)<\/p>',
        caseSensitive: false,
        dotAll: true,
      );
      final beginRx = RegExp(r'begin="([^"]+)"', caseSensitive: false);
      final endRx = RegExp(r'end="([^"]+)"', caseSensitive: false);

      for (final match in pRx.allMatches(content)) {
        final attrs = match.group(1) ?? '';
        final rawText = match.group(2) ?? '';

        final beginMatch = beginRx.firstMatch(attrs);
        final endMatch = endRx.firstMatch(attrs);

        if (beginMatch != null && endMatch != null) {
          final start = _parseTtmlTimestamp(beginMatch.group(1)!);
          final end = _parseTtmlTimestamp(endMatch.group(1)!);
          final cleanText = _cleanCaptionText(rawText);

          if (cleanText.isNotEmpty && end > start) {
            segments.add(
              SubtitleSegment(
                id: 'ttml_seg_${segments.length}',
                start: start,
                end: end,
                text: cleanText,
                language: language,
                source: 'TTML',
              ),
            );
          }
        }
      }
    } catch (_) {
      // TTML parsing fallback
    }

    segments.sort((a, b) => a.start.compareTo(b.start));

    return SubtitleDocument(
      id: 'ttml_doc_${DateTime.now().millisecondsSinceEpoch}',
      title: 'TTML Document',
      language: language ?? 'unknown',
      format: 'TTML',
      segments: segments,
    );
  }

  String _cleanCaptionText(String raw) {
    // Strip HTML/WebVTT styling tags (e.g. <b>, <i>, <font>, <v Speaker>, etc.)
    var cleaned = raw.replaceAll(RegExp(r'<[^>]*>'), '');
    // Replace html entities
    cleaned = cleaned
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    // Normalize whitespace / newlines
    cleaned = cleaned.replaceAll(RegExp(r'\r?\n'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.trim();
  }

  Duration _parseTimestamp({
    required String? hours,
    required String minutes,
    required String seconds,
    required String millis,
  }) {
    final h = hours != null ? int.parse(hours.replaceAll(':', '')) : 0;
    final m = int.parse(minutes);
    final s = int.parse(seconds);
    final ms = int.parse(millis);
    return Duration(hours: h, minutes: m, seconds: s, milliseconds: ms);
  }

  Duration _parseTtmlTimestamp(String timeStr) {
    final trimmed = timeStr.trim();
    // Supports clock format HH:MM:SS.mmm or seconds format like 12.34s or 123s
    if (trimmed.endsWith('s')) {
      final secs =
          double.tryParse(trimmed.substring(0, trimmed.length - 1)) ?? 0.0;
      return Duration(milliseconds: (secs * 1000).toInt());
    }

    final parts = trimmed.split(':');
    if (parts.length >= 3) {
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final secParts = parts[2].split('.');
      final s = int.parse(secParts[0]);
      final ms = secParts.length > 1
          ? int.parse(secParts[1].padRight(3, '0').substring(0, 3))
          : 0;
      return Duration(hours: h, minutes: m, seconds: s, milliseconds: ms);
    }

    final secs = double.tryParse(trimmed) ?? 0.0;
    return Duration(milliseconds: (secs * 1000).toInt());
  }
}

```

## lib/features/subtitles/data/subtitle_repository_impl.dart
```dart:lib/features/subtitles/data/subtitle_repository_impl.dart
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/constants/app_constants.dart';
import '../../pipeline/domain/ai_pipeline.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import '../domain/entities/subtitle_document.dart';
import '../domain/entities/subtitle_track.dart';
import '../domain/subtitle_selection_policy.dart';
import 'subtitle_language_detector.dart';
import 'subtitle_parser.dart';
import '../domain/repositories/subtitle_repository.dart';

class SubtitleRepositoryImpl
    implements SubtitleRepository, SubtitleTrackProvider {
  SubtitleRepositoryImpl(
    this._dio, [
    SubtitleParser? parser,
    SubtitleLanguageDetector? languageDetector,
    SubtitleSelectionPolicy? selectionPolicy,
  ]) : _parser = parser ?? const SubtitleParser(),
       _languageDetector = languageDetector ?? const SubtitleLanguageDetector();

  final Dio _dio;
  final SubtitleParser _parser;
  final SubtitleLanguageDetector _languageDetector;

  @override
  Future<List<SubtitleTrack>> findSubtitleTracks(ResolvedSource source) async {
    final tracks = <SubtitleTrack>[];

    if (source.kind == MediaKind.hls) {
      final hlsTracks = await _extractHlsSubtitles(
        source.uri,
        source.requestContext,
      );
      tracks.addAll(hlsTracks);
    } else if (source.kind == MediaKind.dash) {
      final dashTracks = await _extractDashSubtitles(
        source.uri,
        source.requestContext,
      );
      tracks.addAll(dashTracks);
    }

    if (source.kind == MediaKind.localFile || source.uri.isScheme('file')) {
      final sidecarTracks = await _checkLocalSidecarSubtitles(source.uri);
      tracks.addAll(sidecarTracks);
    }

    return tracks;
  }

  Future<List<SubtitleTrack>> _extractHlsSubtitles(
    Uri playlistUri,
    RequestContext context,
  ) async {
    final tracks = <SubtitleTrack>[];
    try {
      final response = await _dio.get<String>(
        playlistUri.toString(),
        options: Options(headers: context.headers),
      );
      final content = response.data ?? '';

      // Improved regex for HLS subtitles to capture more attributes
      final subtitleRx = RegExp(
        r'#EXT-X-MEDIA:TYPE=SUBTITLES.*?,NAME="([^"]+)"(?:.*?,LANGUAGE="([^"]+)")?.*?URI="([^"]+)"',
        caseSensitive: false,
      );

      for (final match in subtitleRx.allMatches(content)) {
        final title = match.group(1) ?? 'Subtitle';
        final rawLang = match.group(2) ?? 'en';
        final relUri = match.group(3);

        if (relUri != null) {
          final absUri = playlistUri.resolve(relUri);
          final lang = _languageDetector.detectLanguage(
            declaredLanguage: rawLang,
          );
          final isVi = lang == AppConstants.targetLanguage;

          tracks.add(
            SubtitleTrack(
              id: 'hls_sub_${tracks.length}_$lang',
              language: lang,
              title: title,
              uri: absUri,
              format: SubtitleFormat.webvtt,
              isTargetLanguage: isVi,
              requestContext: context,
            ),
          );
        }
      }
    } catch (_) {
      // HLS subtitle discovery fallback
    }
    return tracks;
  }

  Future<List<SubtitleTrack>> _extractDashSubtitles(
    Uri mpdUri,
    RequestContext context,
  ) async {
    final tracks = <SubtitleTrack>[];
    try {
      final response = await _dio.get<String>(
        mpdUri.toString(),
        options: Options(headers: context.headers),
      );
      final content = response.data ?? '';

      // DASH parsing for subtitles is complex, we look for AdaptationSets with mimeType="text/vtt" or similar
      final adaptSetRx = RegExp(
        r'<AdaptationSet[^>]*?(?:contentType|mimeType)="text/(?:vtt|ttml|xml)"[^>]*?>(.*?)</AdaptationSet>',
        caseSensitive: false,
        dotAll: true,
      );
      final langRx = RegExp(r'lang="([^"]+)"', caseSensitive: false);
      final baseUriRx = RegExp(
        r'<BaseURL>(.*?)</BaseURL>',
        caseSensitive: false,
      );

      for (final match in adaptSetRx.allMatches(content)) {
        final setContent = match.group(1)!;
        final langMatch = langRx.firstMatch(match.group(0)!);
        final rawLang = langMatch?.group(1) ?? 'en';
        final lang = _languageDetector.detectLanguage(
          declaredLanguage: rawLang,
        );

        final baseUrlMatch = baseUriRx.firstMatch(setContent);
        final subUri = baseUrlMatch != null
            ? mpdUri.resolve(baseUrlMatch.group(1)!)
            : mpdUri;

        final isVi = lang == AppConstants.targetLanguage;

        tracks.add(
          SubtitleTrack(
            id: 'dash_sub_${tracks.length}_$lang',
            language: lang,
            title: 'DASH Subtitle ($lang)',
            uri: subUri,
            format: setContent.contains('vtt')
                ? SubtitleFormat.webvtt
                : SubtitleFormat.hlsSegment,
            isTargetLanguage: isVi,
            requestContext: context,
          ),
        );
      }
    } catch (_) {
      // DASH subtitle discovery fallback
    }
    return tracks;
  }

  Future<List<SubtitleTrack>> _checkLocalSidecarSubtitles(Uri fileUri) async {
    final tracks = <SubtitleTrack>[];
    final path = fileUri.toFilePath();
    final basePath = path.contains('.')
        ? path.substring(0, path.lastIndexOf('.'))
        : path;

    for (final ext in [
      '.vi.vtt',
      '.vi.srt',
      '.en.vtt',
      '.en.srt',
      '.vtt',
      '.srt',
      '.ttml',
    ]) {
      final subFile = File('$basePath$ext');
      try {
        if (await subFile.exists()) {
          final content = await subFile.readAsString();
          if (content.isNotEmpty) {
            final isVi =
                ext.contains('.vi.') ||
                _languageDetector.detectLanguage(sampleText: content) == 'vi';
            final lang = isVi
                ? 'vi'
                : _languageDetector.detectLanguage(
                    declaredLanguage: ext.contains('.en.') ? 'en' : 'unknown',
                  );

            tracks.add(
              SubtitleTrack(
                id: 'local_sub_${tracks.length}',
                language: lang,
                title: isVi
                    ? 'Vietnamese Sidecar Subtitle'
                    : 'Local Sidecar Subtitle ($lang)',
                uri: Uri.file(subFile.path),
                format: ext.contains('vtt')
                    ? SubtitleFormat.webvtt
                    : (ext.contains('ttml')
                          ? SubtitleFormat.hlsSegment
                          : SubtitleFormat.srt),
                isTargetLanguage: isVi,
              ),
            );
          }
        }
      } catch (_) {
        // Local subtitle file error
      }
    }
    return tracks;
  }

  Future<SubtitleDocument> fetchSubtitleDocument(SubtitleTrack track) async {
    try {
      String body;
      if (track.uri.isScheme('file')) {
        body = await File(track.uri.toFilePath()).readAsString();
      } else {
        final response = await _dio.get<String>(track.uri.toString());
        body = response.data ?? '';
      }

      final lang = _languageDetector.detectLanguage(
        declaredLanguage: track.language,
        sampleText: body.substring(0, body.length > 500 ? 500 : body.length),
      );

      if (track.uri.path.endsWith('.ttml') ||
          body.contains('<tt') ||
          body.contains('<p begin=')) {
        return _parser.parseTtmlDocument(body, language: lang);
      } else if (track.format == SubtitleFormat.webvtt ||
          body.contains('WEBVTT')) {
        return _parser.parseVttDocument(body, language: lang);
      } else {
        return _parser.parseSrtDocument(body, language: lang);
      }
    } catch (_) {
      return SubtitleDocument(
        id: track.id,
        title: track.title,
        language: track.language,
        format: 'unknown',
        segments: const [],
        sourceUri: track.uri,
      );
    }
  }

  @override
  Future<List<TimedTextSegment>> fetchSubtitleSegments(
    SubtitleTrack track,
  ) async {
    final doc = await fetchSubtitleDocument(track);
    return doc.segments
        .map(
          (s) => TimedTextSegment(
            start: s.start,
            end: s.end,
            text: s.text,
            language: s.language,
          ),
        )
        .toList();
  }

  @override
  Future<List<TimedTextSegment>> findExistingSubtitles(
    String targetLanguage,
  ) async {
    return const [];
  }
}

```

## lib/features/subtitles/domain/entities/subtitle_document.dart
```dart:lib/features/subtitles/domain/entities/subtitle_document.dart
class SubtitleSegment {
  const SubtitleSegment({
    required this.id,
    required this.start,
    required this.end,
    required this.text,
    this.language,
    this.source,
    this.confidence = 1.0,
  });

  final String id;
  final Duration start;
  final Duration end;
  final String text;
  final String? language;
  final String? source;
  final double confidence;
}

class SubtitleDocument {
  const SubtitleDocument({
    required this.id,
    required this.title,
    required this.language,
    required this.format,
    required this.segments,
    this.sourceUri,
    this.confidence = 1.0,
  });

  final String id;
  final String title;
  final String language;
  final String format;
  final List<SubtitleSegment> segments;
  final Uri? sourceUri;
  final double confidence;

  bool get isEmpty => segments.isEmpty;
  bool get isNotEmpty => segments.isNotEmpty;
}

```

## lib/features/subtitles/domain/entities/subtitle_track.dart
```dart:lib/features/subtitles/domain/entities/subtitle_track.dart
import '../../../source_resolver/domain/entities/resolved_source.dart';

enum SubtitleFormat { webvtt, srt, hlsSegment }

class SubtitleTrack {
  const SubtitleTrack({
    required this.id,
    required this.language,
    required this.title,
    required this.uri,
    required this.format,
    this.isTargetLanguage = false,
    this.isOriginal = false,
    this.requestContext,
  });

  final String id;
  final String language;
  final String title;
  final Uri uri;
  final SubtitleFormat format;
  final bool isTargetLanguage;
  final bool isOriginal;
  final RequestContext? requestContext;
}

```

## lib/features/subtitles/domain/repositories/subtitle_repository.dart
```dart:lib/features/subtitles/domain/repositories/subtitle_repository.dart
import '../../../source_resolver/domain/entities/resolved_source.dart';
import '../../../pipeline/domain/ai_pipeline.dart';
import '../entities/subtitle_track.dart';

abstract interface class SubtitleRepository {
  Future<List<SubtitleTrack>> findSubtitleTracks(ResolvedSource source);
  Future<List<TimedTextSegment>> fetchSubtitleSegments(SubtitleTrack track);
  Future<List<TimedTextSegment>> findExistingSubtitles(String targetLanguage);
}

abstract interface class SubtitleTrackProvider {
  Future<List<SubtitleTrack>> findSubtitleTracks(ResolvedSource source);
}

```

## lib/features/subtitles/domain/subtitle_selection_policy.dart
```dart:lib/features/subtitles/domain/subtitle_selection_policy.dart
import '../domain/entities/subtitle_track.dart';

enum SubtitleSelectionDecision { directVi, translateExisting, sttRequired }

class SubtitleSelectionResult {
  const SubtitleSelectionResult({
    required this.decision,
    this.selectedTrack,
    required this.reason,
  });

  final SubtitleSelectionDecision decision;
  final SubtitleTrack? selectedTrack;
  final String reason;

  bool get isDirectVi => decision == SubtitleSelectionDecision.directVi;
  bool get isTranslateExisting =>
      decision == SubtitleSelectionDecision.translateExisting;
  bool get isSttRequired => decision == SubtitleSelectionDecision.sttRequired;
}

class SubtitleSelectionPolicy {
  const SubtitleSelectionPolicy();

  SubtitleSelectionResult evaluate(List<SubtitleTrack> availableTracks) {
    if (availableTracks.isEmpty) {
      return const SubtitleSelectionResult(
        decision: SubtitleSelectionDecision.sttRequired,
        reason:
            'No subtitle tracks discovered. Speech-to-Text (STT) is required.',
      );
    }

    // Priority 1: Vietnamese subtitle -> use directly
    final viTrack = availableTracks
        .where(
          (t) =>
              t.isTargetLanguage ||
              t.language.toLowerCase() == 'vi' ||
              t.language.toLowerCase() == 'vietnamese',
        )
        .firstOrNull;

    if (viTrack != null) {
      return SubtitleSelectionResult(
        decision: SubtitleSelectionDecision.directVi,
        selectedTrack: viTrack,
        reason:
            'Found Vietnamese subtitle track [${viTrack.id}]. Using directly.',
      );
    }

    // Priority 2: Source-language / Foreign subtitle -> translate later
    final foreignTrack = availableTracks.firstOrNull;
    if (foreignTrack != null) {
      return SubtitleSelectionResult(
        decision: SubtitleSelectionDecision.translateExisting,
        selectedTrack: foreignTrack,
        reason:
            'Found foreign subtitle track [${foreignTrack.id}, lang: ${foreignTrack.language}]. Translating existing.',
      );
    }

    return const SubtitleSelectionResult(
      decision: SubtitleSelectionDecision.sttRequired,
      reason:
          'No useful subtitle tracks available. Speech-to-Text (STT) required.',
    );
  }
}

```

