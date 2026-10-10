import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../pipeline/domain/ai_pipeline.dart';

class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({required this.segment, super.key});

  final TimedTextSegment? segment;

  @override
  Widget build(BuildContext context) {
    if (segment == null || segment!.text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 16,
      right: 16,
      bottom: 80,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xE60B0E17),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.primaryLight.withValues(alpha: 0.6),
              width: 1.5,
            ),
            boxShadow: const [
              BoxShadow(
                color: AppColors.primaryGlow,
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                segment!.text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 2),
                      blurRadius: 4,
                      color: Colors.black,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
