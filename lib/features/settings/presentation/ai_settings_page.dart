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
