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

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _controller = TextEditingController();
  StreamSubscription<List<SharedMediaFile>>? _shareSubscription;

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
    final value = items.first.path.trim();
    if (value.isNotEmpty) {
      _controller.text = value;
      unawaited(_resolve(value));
    }
    ReceiveSharingIntent.instance.reset();
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
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.firstOrNull?.path;
    if (path != null) await _resolve(path);
  }

  Future<void> _pickSubtitle() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt', 'ass'],
    );
    final path = result?.files.firstOrNull?.path;
    if (path != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã chọn phụ đề: ${result?.files.first.name}'),
        ),
      );
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
