import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderRadius;
  final VoidCallback? onTap;

  const AppGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius = 16,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? AppColors.surfaceCardBorder,
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: card,
      );
    }
    return card;
  }
}

class GlowButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Gradient? gradient;
  final Color? color;
  final bool isLoading;
  final double height;

  const GlowButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.gradient,
    this.color,
    this.isLoading = false,
    this.height = 50,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveGradient = gradient ?? AppColors.primaryGradient;

    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: onPressed != null ? effectiveGradient : null,
        color: onPressed == null ? AppColors.surfaceCardBorder : null,
        borderRadius: BorderRadius.circular(14),
        boxShadow: onPressed != null
            ? [
                BoxShadow(
                  color: (color ?? AppColors.primary).withValues(alpha: 0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading) ...[
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PillBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? borderColor;
  final VoidCallback? onTap;

  const PillBadge({
    super.key,
    required this.label,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor ?? AppColors.surfaceCardBorder,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: textColor ?? AppColors.textPrimary,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: badge,
      );
    }
    return badge;
  }
}

class ProgressGauge extends StatelessWidget {
  final double progress; // 0.0 to 1.0
  final String title;
  final String? subtitle;
  final double size;

  const ProgressGauge({
    super.key,
    required this.progress,
    required this.title,
    this.subtitle,
    this.size = 180,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (progress.clamp(0.0, 1.0) * 100).toInt();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _GaugePainter(progress: progress),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$percent%',
                style: TextStyle(
                  fontSize: size * 0.22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -1,
                ),
              ),
              Text(
                title,
                style: TextStyle(
                  fontSize: size * 0.08,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryLight,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: size * 0.065,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double progress;

  _GaugePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 20) / 2;
    const strokeWidth = 12.0;

    // Track Paint
    final trackPaint = Paint()
      ..color = AppColors.surfaceCardBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * 0.75,
      math.pi * 1.5,
      false,
      trackPaint,
    );

    // Progress Paint with Gradient
    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = const SweepGradient(
      colors: [
        AppColors.primary,
        AppColors.primaryLight,
        AppColors.cyanAccent,
      ],
      startAngle: -math.pi * 0.75,
      endAngle: math.pi * 0.75,
    );

    final progressPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = math.pi * 1.5 * progress.clamp(0.0, 1.0);

    canvas.drawArc(
      rect,
      -math.pi * 0.75,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

enum AppStepState { pending, active, completed, failed }

class StepTimelineTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final AppStepState stepState;
  final bool isLast;
  final Widget? trailing;

  const StepTimelineTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.stepState,
    this.isLast = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    Color iconBg;
    Widget iconChild;

    switch (stepState) {
      case AppStepState.completed:
        iconBg = AppColors.success.withValues(alpha: 0.2);
        iconChild = const Icon(Icons.check, size: 16, color: AppColors.success);
        break;
      case AppStepState.active:
        iconBg = AppColors.primary.withValues(alpha: 0.25);
        iconChild = const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primaryLight,
          ),
        );
        break;
      case AppStepState.failed:
        iconBg = AppColors.error.withValues(alpha: 0.2);
        iconChild = const Icon(Icons.close, size: 16, color: AppColors.error);
        break;
      case AppStepState.pending:
        iconBg = AppColors.surfaceCardBorder;
        iconChild = Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: AppColors.textMuted,
            shape: BoxShape.circle,
          ),
        );
        break;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: stepState == AppStepState.active
                        ? AppColors.primaryLight
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Center(child: iconChild),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: stepState == AppStepState.completed
                        ? AppColors.success.withValues(alpha: 0.5)
                        : AppColors.surfaceCardBorder,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: stepState == AppStepState.active
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: stepState == AppStepState.pending
                                ? AppColors.textMuted
                                : AppColors.textPrimary,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
