import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_components.dart';
import '../domain/entities/resolved_source.dart';
import 'source_resolver_controller.dart';

class SourceAnalysisPage extends ConsumerStatefulWidget {
  final String inputUrl;

  const SourceAnalysisPage({
    super.key,
    required this.inputUrl,
  });

  @override
  ConsumerState<SourceAnalysisPage> createState() => _SourceAnalysisPageState();
}

class _SourceAnalysisPageState extends ConsumerState<SourceAnalysisPage> {
  int _currentStep = 0;
  ResolvedSource? _resolvedSource;
  bool _isFailed = false;

  @override
  void initState() {
    super.initState();
    _startAnalysis();
  }

  Future<void> _startAnalysis() async {
    try {
      // Step 1: Validating URL
      if (mounted) setState(() => _currentStep = 0);
      await Future.delayed(const Duration(milliseconds: 600));

      // Step 2: Extracting Media
      if (mounted) setState(() => _currentStep = 1);
      await Future.delayed(const Duration(milliseconds: 800));

      // Step 3: Verifying HTTP Candidates
      if (mounted) setState(() => _currentStep = 2);

      final resolved = await ref
          .read(sourceResolverControllerProvider.notifier)
          .resolve(widget.inputUrl);

      if (mounted) {
        if (resolved == null || (resolved.failureReason != null && resolved.candidates.isEmpty)) {
          setState(() {
            _isFailed = true;
            _resolvedSource = resolved;
          });
          return;
        }

        setState(() {
          _currentStep = 3;
          _resolvedSource = resolved;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isFailed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phân tích Nguồn Video'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Target URL Header Card
            AppGlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ĐƯỜNG DẪN MỤC TIÊU',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryLight,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.inputUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Timeline Header
            const Text(
              'Tiến trình Phân tích & Xác minh Stream',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // Step Timeline List
            AppGlassCard(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                children: [
                  StepTimelineTile(
                    title: '1. Kiểm tra URL & Phân tích Trang Web',
                    subtitle: 'Xác nhận giao thức https & quét iframe embed',
                    stepState: _getStepState(0),
                  ),
                  StepTimelineTile(
                    title: '2. Trích xuất Luồng Media Candidates',
                    subtitle: 'Phân lập URL HLS (.m3u8), DASH (.mpd) hoặc MP4',
                    stepState: _getStepState(1),
                  ),
                  StepTimelineTile(
                    title: '3. Xác thực HTTP HEAD & Băng thông Stream',
                    subtitle: 'Kiểm tra Content-Type, CORS & Byte Range Support',
                    stepState: _getStepState(2),
                  ),
                  StepTimelineTile(
                    title: '4. Khởi tạo Luồng Phát Trực tiếp',
                    subtitle: 'Sẵn sàng truyền sang Player & Bộ đệm AI',
                    stepState: _getStepState(3),
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Error Card
            if (_isFailed) ...[
              AppGlassCard(
                padding: const EdgeInsets.all(24),
                borderColor: AppColors.error.withValues(alpha: 0.5),
                child: Column(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.error, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Phân tích thất bại',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _resolvedSource?.failureReason ??
                          'Không thể tìm thấy hoặc trích xuất luồng video hợp lệ từ địa chỉ này.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    GlowButton(
                      label: 'Thử lại',
                      icon: Icons.refresh_rounded,
                      color: AppColors.error,
                      onPressed: () {
                        setState(() {
                          _isFailed = false;
                          _currentStep = 0;
                          _resolvedSource = null;
                        });
                        _startAnalysis();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Media Candidate Spec Card (Shown when Step 3 Complete)
            if (_currentStep >= 3 && !_isFailed) ...[
              AppGlassCard(
                padding: const EdgeInsets.all(20),
                borderColor: AppColors.primaryLight.withValues(alpha: 0.5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.verified_rounded,
                                color: AppColors.success, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Đã xác thực Luồng Stream',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                        PillBadge(
                          label: _resolvedSource?.kind.name.toUpperCase() ?? 'VIDEO',
                          backgroundColor: const Color(0x3310B981),
                          textColor: AppColors.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSpecRow(
                      'Định dạng:',
                      _resolvedSource?.kind == MediaKind.hls
                          ? 'm3u8 (HLS Adaptive Stream)'
                          : _resolvedSource?.kind.name ?? 'Unknown',
                    ),
                    if (_resolvedSource?.manualSubtitlePath != null)
                      _buildSpecRow(
                        'Phụ đề:',
                        'Tệp thủ công (${_resolvedSource!.manualSubtitlePath!.split(RegExp(r'[/\\]')).last})',
                      ),
                    _buildSpecRow(
                      'Khả năng AI:',
                      _resolvedSource?.supportsFullAi == true
                          ? 'Hỗ trợ đầy đủ (Audio + Seek)'
                          : 'Hạn chế (Chỉ phát lồng tiếng)',
                    ),
                    _buildSpecRow(
                      'Phương thức:',
                      _resolvedSource?.discoveryMethod.name ?? 'Auto',
                    ),
                    if (_resolvedSource?.requestContext.referer != null)
                      _buildSpecRow(
                        'Referer:',
                        _resolvedSource!.requestContext.referer!,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Action Button to Player
              GlowButton(
                label: 'Bắt đầu Phát & Dịch AI',
                icon: Icons.play_arrow_rounded,
                onPressed: () {
                  if (_resolvedSource != null) {
                    context.push('/player', extra: _resolvedSource);
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  AppStepState _getStepState(int stepIndex) {
    if (_isFailed && _currentStep == stepIndex) return AppStepState.failed;
    if (_currentStep > stepIndex) return AppStepState.completed;
    if (_currentStep == stepIndex) return AppStepState.active;
    return AppStepState.pending;
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
