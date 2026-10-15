# Review Module: 01. Hạ Tầng Core, Network & UI Shell

## Included Files (18 files)

```text
lib/app/app.dart
lib/app/presentation/main_shell_page.dart
lib/app/router/app_router.dart
lib/app/theme/app_colors.dart
lib/app/theme/app_components.dart
lib/app/theme/app_theme.dart
lib/core/constants/app_constants.dart
lib/core/diagnostics/diagnostics_exporter.dart
lib/core/diagnostics/diagnostics_service.dart
lib/core/diagnostics/presentation/diagnostic_log_overlay.dart
lib/core/errors/app_exception.dart
lib/core/errors/error_ux_handler.dart
lib/core/network/dio_provider.dart
lib/core/utils/cancellation_token.dart
lib/core/utils/media_url.dart
lib/core/utils/sha256_util.dart
lib/core/utils/shared_input_parser.dart
lib/core/utils/tokenizer.dart
```

## lib/app/app.dart
```dart:lib/app/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';

class TranslatorApp extends ConsumerWidget {
  const TranslatorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Local AI Video Translator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}

```

## lib/app/presentation/main_shell_page.dart
```dart:lib/app/presentation/main_shell_page.dart
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../../features/home/presentation/home_page.dart';
import '../../features/pipeline/presentation/ai_pipeline_progress_page.dart';
import '../../features/settings/presentation/ai_settings_page.dart';

class MainShellPage extends StatefulWidget {
  const MainShellPage({super.key});

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomePage(),
      AiPipelineProgressPage(
        initialProgress: 0.68,
        title: 'Dịch Video TikTok #102',
        onNavigateToHome: () {
          setState(() {
            _currentIndex = 0;
          });
        },
      ),
      const AiSettingsPage(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(
              color: AppColors.surfaceCardBorder,
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  icon: Icons.home_rounded,
                  label: 'Trang chủ',
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.auto_awesome_rounded,
                  label: 'Tiến trình AI',
                  hasBadge: true,
                ),
                _buildNavItem(
                  index: 2,
                  icon: Icons.tune_rounded,
                  label: 'Cài đặt AI',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
    bool hasBadge = false,
  }) {
    final isSelected = _currentIndex == index;

    return InkWell(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGlow : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                Icon(
                  icon,
                  color: isSelected ? AppColors.primaryLight : AppColors.textMuted,
                  size: 24,
                ),
                if (hasBadge)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.cyanAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

```

## lib/app/router/app_router.dart
```dart:lib/app/router/app_router.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../presentation/main_shell_page.dart';
import '../../features/player/presentation/player_page.dart';
import '../../features/settings/presentation/ai_settings_page.dart';
import '../../features/settings/presentation/model_manager_page.dart';
import '../../features/source_resolver/domain/entities/resolved_source.dart';
import '../../features/source_resolver/presentation/source_analysis_page.dart';
import '../../features/pipeline/presentation/ai_pipeline_progress_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const MainShellPage(),
      ),
      GoRoute(
        path: '/analysis',
        builder: (context, state) {
          final url = state.extra as String? ?? 'https://www.youtube.com/watch?v=sample';
          return SourceAnalysisPage(inputUrl: url);
        },
      ),
      GoRoute(
        path: '/pipeline',
        builder: (context, state) => const AiPipelineProgressPage(
          initialProgress: 0.68,
          title: 'Dịch Video TikTok #102',
        ),
      ),
      GoRoute(
        path: '/player',
        builder: (context, state) =>
            PlayerPage(source: state.extra! as ResolvedSource),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const AiSettingsPage(),
      ),
      GoRoute(
        path: '/models',
        builder: (context, state) => const ModelManagerPage(),
      ),
    ],
  );
});

```

## lib/app/theme/app_colors.dart
```dart:lib/app/theme/app_colors.dart
import 'package:flutter/material.dart';

abstract class AppColors {
  // Backgrounds
  static const Color background = Color(0xFF0B0E17);
  static const Color surface = Color(0xFF131722);
  static const Color surfaceCard = Color(0xFF191E2C);
  static const Color surfaceCardBorder = Color(0xFF262C3F);
  
  // Accents & Glows
  static const Color primary = Color(0xFF6C5CE7);
  static const Color primaryLight = Color(0xFF8C7CFF);
  static const Color primaryGlow = Color(0x666C5CE7);
  
  static const Color secondary = Color(0xFFA855F7);
  static const Color cyanAccent = Color(0xFF00F2FE);
  static const Color cyanGlow = Color(0x4000F2FE);

  // Text
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);

  // Status Colors
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6C5CE7), Color(0xFF8C7CFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF0B0E17), Color(0xFF111523)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGlowGradient = LinearGradient(
    colors: [Color(0x336C5CE7), Color(0x056C5CE7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyanGradient = LinearGradient(
    colors: [Color(0xFF4FACFE), Color(0xFF00F2FE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

```

## lib/app/theme/app_components.dart
```dart:lib/app/theme/app_components.dart
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
                ),
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
            Icon(icon, size: 14, color: textColor ?? AppColors.textPrimary),
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
      return GestureDetector(onTap: onTap, child: badge);
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
      colors: [AppColors.primary, AppColors.primaryLight, AppColors.cyanAccent],
      startAngle: -math.pi * 0.75,
      endAngle: math.pi * 0.75,
    );

    final progressPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = math.pi * 1.5 * progress.clamp(0.0, 1.0);

    canvas.drawArc(rect, -math.pi * 0.75, sweepAngle, false, progressPaint);
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
                  ?trailing,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

```

## lib/app/theme/app_theme.dart
```dart:lib/app/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
      ),
      scaffoldBackgroundColor: AppColors.background,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceCard,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.surfaceCardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.surfaceCardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.5),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primaryLight,
        inactiveTrackColor: AppColors.surfaceCardBorder,
        thumbColor: AppColors.primaryLight,
        overlayColor: AppColors.primaryGlow,
        trackHeight: 4,
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surfaceCard,
        margin: EdgeInsets.zero,
        elevation: 0,
      ),
    );
  }
}


```

## lib/core/constants/app_constants.dart
```dart:lib/core/constants/app_constants.dart
abstract final class AppConstants {
  static const targetLanguage = 'vi';
  static const maxIframeDepth = 4;
  static const initialSubtitleBuffer = Duration(seconds: 7);
  static const targetSubtitleLookahead = Duration(minutes: 1);
  static const dangerBuffer = Duration(seconds: 3);
  static const networkTimeout = Duration(seconds: 15);
  static const defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36';
}

```

## lib/core/diagnostics/diagnostics_exporter.dart
```dart:lib/core/diagnostics/diagnostics_exporter.dart
class DiagnosticsExporter {
  const DiagnosticsExporter();

  /// Exports local diagnostics report with sensitive values (cookies, auth headers, tokens) strictly redacted.
  String exportRedactedReport({
    required String sourceUri,
    required Map<String, String> headers,
    required List<String> logEvents,
  }) {
    final sanitizedUri = _redactUriTokens(sourceUri);
    final sanitizedHeaders = _redactHeaders(headers);
    final sanitizedLogs = logEvents.map(_redactLogMessage).toList();

    return '''
=== LOCAL AI VIDEO TRANSLATOR DIAGNOSTICS EXPORT ===
Source URI: $sanitizedUri
Headers: $sanitizedHeaders
-----------------------------------------------------
Logs:
${sanitizedLogs.join('\n')}
=====================================================
''';
  }

  String _redactUriTokens(String uriStr) {
    try {
      final uri = Uri.parse(uriStr);
      final queryParams = Map<String, String>.from(uri.queryParameters);
      for (final key in queryParams.keys) {
        if (key.toLowerCase().contains('token') ||
            key.toLowerCase().contains('auth') ||
            key.toLowerCase().contains('sig') ||
            key.toLowerCase().contains('key')) {
          queryParams[key] = '[REDACTED]';
        }
      }
      return uri
          .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null)
          .toString();
    } catch (_) {
      return '[REDACTED_URI]';
    }
  }

  Map<String, String> _redactHeaders(Map<String, String> headers) {
    final redacted = <String, String>{};
    for (final entry in headers.entries) {
      final keyLower = entry.key.toLowerCase();
      if (keyLower.contains('authorization') ||
          keyLower.contains('cookie') ||
          keyLower.contains('token') ||
          keyLower.contains('api-key')) {
        redacted[entry.key] = '[REDACTED]';
      } else {
        redacted[entry.key] = entry.value;
      }
    }
    return redacted;
  }

  String _redactLogMessage(String message) {
    // Redact potential tokens or passwords in log lines
    var sanitized = message.replaceAll(
      RegExp(r'token=[^&\s]+', caseSensitive: false),
      'token=[REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'authorization:[^\s]+', caseSensitive: false),
      'authorization:[REDACTED]',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'key=[^&\s]+', caseSensitive: false),
      'key=[REDACTED]',
    );
    return sanitized;
  }
}

```

## lib/core/diagnostics/diagnostics_service.dart
```dart:lib/core/diagnostics/diagnostics_service.dart
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LogLevel { debug, info, warning, error }

class DiagnosticEntry {
  const DiagnosticEntry({
    required this.timestamp,
    required this.subsystem,
    required this.message,
    required this.level,
    this.details,
  });

  final DateTime timestamp;
  final String subsystem;
  final String message;
  final LogLevel level;
  final Object? details;

  @override
  String toString() {
    final timeStr = timestamp.toIso8601String().substring(11, 19);
    final detailStr = details != null ? ' | $details' : '';
    return '[$timeStr] [${level.name.toUpperCase()}] [$subsystem] $message$detailStr';
  }
}

class DiagnosticsService {
  final _logs = <DiagnosticEntry>[];
  final _controller = StreamController<DiagnosticEntry>.broadcast();

  List<DiagnosticEntry> get logs => List.unmodifiable(_logs);
  Stream<DiagnosticEntry> get stream => _controller.stream;

  void log(
    String subsystem,
    String message, {
    LogLevel level = LogLevel.info,
    Object? details,
  }) {
    final entry = DiagnosticEntry(
      timestamp: DateTime.now(),
      subsystem: subsystem,
      message: message,
      level: level,
      details: details,
    );
    _logs.add(entry);
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }
    _controller.add(entry);
  }

  void clear() {
    _logs.clear();
  }

  void dispose() {
    _controller.close();
  }
}

final diagnosticsServiceProvider = Provider<DiagnosticsService>((ref) {
  final service = DiagnosticsService();
  ref.onDispose(service.dispose);
  return service;
});

```

## lib/core/diagnostics/presentation/diagnostic_log_overlay.dart
```dart:lib/core/diagnostics/presentation/diagnostic_log_overlay.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../diagnostics_service.dart';

class DiagnosticLogOverlay extends ConsumerWidget {
  const DiagnosticLogOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnostics = ref.watch(diagnosticsServiceProvider);

    return Container(
      color: Colors.black.withValues(alpha: 0.9),
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SYSTEM DIAGNOSTICS LOG',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.white),
                      onPressed: () {
                        final allLogs = diagnostics.logs.join('\n');
                        Clipboard.setData(ClipboardData(text: allLogs));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Logs copied to clipboard')),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep, color: Colors.white),
                      onPressed: () => diagnostics.clear(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white24),
          Expanded(
            child: StreamBuilder<DiagnosticEntry>(
              stream: diagnostics.stream,
              builder: (context, snapshot) {
                final logs = diagnostics.logs.reversed.toList();
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: logs.length,
                  separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final entry = logs[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: SelectableText(
                        entry.toString(),
                        style: TextStyle(
                          color: _getColor(entry.level),
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _getColor(LogLevel level) {
    switch (level) {
      case LogLevel.error: return Colors.redAccent;
      case LogLevel.warning: return Colors.orangeAccent;
      case LogLevel.debug: return Colors.grey;
      case LogLevel.info: return Colors.white70;
    }
  }
}

```

## lib/core/errors/app_exception.dart
```dart:lib/core/errors/app_exception.dart
sealed class AppException implements Exception {
  const AppException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

final class InvalidInputException extends AppException {
  const InvalidInputException(super.message);
}

final class ResolutionException extends AppException {
  const ResolutionException(super.message, [super.cause]);
}

final class PlaybackException extends AppException {
  const PlaybackException(super.message, [super.cause]);
}

```

## lib/core/errors/error_ux_handler.dart
```dart:lib/core/errors/error_ux_handler.dart
enum AppErrorType {
  invalidUrl,
  unsupportedMedia,
  networkFailure,
  sourceGone,
  codecUnsupported,
  modelMissing,
  modelCorrupted,
  aiOom,
  aiTooSlow,
  embeddedAudioUnavailable,
  permissionDenied,
  translationError,
  storageFull,
  unknown,
}

class UserFriendlyError {
  const UserFriendlyError({
    required this.type,
    required this.title,
    required this.message,
    required this.actionLabel,
  });

  final AppErrorType type;
  final String title;
  final String message;
  final String actionLabel;

  static UserFriendlyError handle(Object error) {
    final str = error.toString().toLowerCase();

    if (str.contains('url') || str.contains('invalid')) {
      return const UserFriendlyError(
        type: AppErrorType.invalidUrl,
        title: 'Invalid URL',
        message:
            'The provided media link is invalid or malformed. Please check and try again.',
        actionLabel: 'Edit URL',
      );
    }
    if (str.contains('codec') || str.contains('unsupported')) {
      return const UserFriendlyError(
        type: AppErrorType.codecUnsupported,
        title: 'Codec Unsupported',
        message:
            'The media format or codec is not supported by the playback backend.',
        actionLabel: 'Switch Mode',
      );
    }
    if (str.contains('network') ||
        str.contains('socket') ||
        str.contains('dioexception')) {
      return const UserFriendlyError(
        type: AppErrorType.networkFailure,
        title: 'Network Connection Error',
        message:
            'Unable to connect to media source. Please check your internet connection.',
        actionLabel: 'Retry Connection',
      );
    }
    if (str.contains('model') &&
        (str.contains('missing') || str.contains('not found'))) {
      return const UserFriendlyError(
        type: AppErrorType.modelMissing,
        title: 'AI Model Required',
        message:
            'Required local AI models are not downloaded. Please download them in Settings.',
        actionLabel: 'Open Model Manager',
      );
    }
    if (str.contains('storage') || str.contains('space')) {
      return const UserFriendlyError(
        type: AppErrorType.storageFull,
        title: 'Storage Full',
        message:
            'Device storage is nearly full. Please clear cache or free up space.',
        actionLabel: 'Clear Cache',
      );
    }
    if (str.contains('permission') || str.contains('denied')) {
      return const UserFriendlyError(
        type: AppErrorType.permissionDenied,
        title: 'Permission Denied',
        message:
            'Required audio capture permission was denied. AI subtitles will remain disabled.',
        actionLabel: 'Open Settings',
      );
    }

    return const UserFriendlyError(
      type: AppErrorType.unknown,
      title: 'Playback Error',
      message: 'An unexpected error occurred during playback or AI processing.',
      actionLabel: 'Retry',
    );
  }
}

```

## lib/core/network/dio_provider.dart
```dart:lib/core/network/dio_provider.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';

final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      connectTimeout: AppConstants.networkTimeout,
      receiveTimeout: AppConstants.networkTimeout,
      followRedirects: true,
      maxRedirects: 5,
      headers: const {'User-Agent': 'LocalAIVideoTranslator/0.1'},
    ),
  );
});

```

## lib/core/utils/cancellation_token.dart
```dart:lib/core/utils/cancellation_token.dart
class OperationCancelledException implements Exception {
  const OperationCancelledException([this.message = 'Operation was cancelled']);
  final String message;

  @override
  String toString() => 'OperationCancelledException: $message';
}

class CancellationToken {
  bool _isCancelled = false;
  final List<VoidCallback> _listeners = [];

  bool get isCancelled => _isCancelled;

  void addListener(VoidCallback listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in _listeners) {
      listener();
    }
    _listeners.clear();
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const OperationCancelledException();
    }
  }
}

typedef VoidCallback = void Function();

```

## lib/core/utils/media_url.dart
```dart:lib/core/utils/media_url.dart
enum MediaUrlKind { hls, dash, progressive, webPage, localFile, unknown }

abstract final class MediaUrl {
  static MediaUrlKind classify(String input) {
    final value = input.trim();
    if (value.startsWith('file://') ||
        value.startsWith('content://') ||
        value.startsWith('/')) {
      return MediaUrlKind.localFile;
    }
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      return MediaUrlKind.unknown;
    }
    final path = uri.path.toLowerCase();
    if (path.endsWith('.m3u8')) {
      return MediaUrlKind.hls;
    }
    if (path.endsWith('.mpd')) {
      return MediaUrlKind.dash;
    }
    if (['.mp4', '.mkv', '.webm', '.mov', '.m4v'].any(path.endsWith)) {
      return MediaUrlKind.progressive;
    }
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return MediaUrlKind.webPage;
    }
    return MediaUrlKind.unknown;
  }
}

```

## lib/core/utils/sha256_util.dart
```dart:lib/core/utils/sha256_util.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';

abstract final class Sha256Util {
  static Future<String> computeFileHash(File file) async {
    if (!await file.exists()) return '';
    final stream = file.openRead();
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  }

  static String computeBytesHash(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Generates a cryptographically secure random nonce for WebView security.
  static String generateNonce([int length = 32]) {
    final random = Random.secure();
    final values = List<int>.generate(length, (i) => random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '');
  }
}

```

## lib/core/utils/shared_input_parser.dart
```dart:lib/core/utils/shared_input_parser.dart
/// Tiện ích phân tách URL http(s) hoặc đường dẫn tệp cục bộ từ input của người dùng.
abstract final class SharedInputParser {
  /// Pattern URL tập trung vào http/https với xác thực host cơ bản.
  /// Loại bỏ các ký tự dấu câu thừa ở cuối chuỗi thường gặp khi dán link.
  static final RegExp _urlPattern = RegExp(
    r'https?://(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
    caseSensitive: false,
  );

  /// Whitelist of allowed schemes for local/content files.
  static const _allowedLocalSchemes = ['content://', 'file://'];

  /// Returns the first usable source, or null if none found.
  static String? extract(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    // 1. Check for URLs embedded in text ("Check this out https://...")
    final match = _urlPattern.firstMatch(text);
    if (match != null) {
      final url = match.group(0)!;
      // Clean up common trailing punctuation from sharing apps if the regex missed it
      return url.replaceFirst(RegExp(r'[)\].,;!?]+$'), '');
    }

    // 2. Local file or content provider path
    for (final scheme in _allowedLocalSchemes) {
      if (text.startsWith(scheme)) {
        return text;
      }
    }

    // Support absolute Unix-style paths (common in Android/Linux)
    if (text.startsWith('/')) {
      return text;
    }

    // 3. Fallback for raw domains (e.g. "youtube.com/watch...")
    // Only if it looks like a domain and has no spaces (strict validation)
    if (RegExp(r'^(?:www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&//=]*)$').hasMatch(text)) {
       return 'https://$text';
    }

    return null;
  }
}

```

## lib/core/utils/tokenizer.dart
```dart:lib/core/utils/tokenizer.dart
import 'dart:convert';

/// A simplified BPE/WordPiece tokenizer for local ONNX models.
class SimpleTokenizer {
  SimpleTokenizer._(this._vocab, this._specialTokens);

  final Map<String, int> _vocab;
  final Map<String, int> _specialTokens;
  final Map<int, String> _invVocab = {};

  static Future<SimpleTokenizer> load(String vocabJson) async {
    final Map<String, dynamic> data = jsonDecode(vocabJson);
    final vocab = <String, int>{};
    final special = <String, int>{};

    data.forEach((key, value) {
      // Nhận diện các định dạng token đặc biệt phổ biến: <|...|>, [CLS], </s>, >>lang<<, etc.
      final isSpecial = (key.startsWith('<|') && key.endsWith('|>')) ||
          (key.startsWith('[') && key.endsWith(']')) ||
          (key.startsWith('>>') && key.endsWith('<<')) ||
          (key.startsWith('<') && key.endsWith('>') && key.length <= 6) ||
          key == '</s>' ||
          key == '<mask>';

      if (isSpecial) {
        special[key] = value;
      }
      vocab[key] = value;
    });

    final tokenizer = SimpleTokenizer._(vocab, special);
    vocab.forEach((key, value) {
      tokenizer._invVocab[value] = key;
    });
    return tokenizer;
  }

  /// Encodes text using greedy longest-match (essential for BPE/SentencePiece).
  List<int> encode(String text, {bool addWhisperTokens = false, String? lang}) {
    final tokens = <int>[];

    // Prepend Whisper special tokens if required
    if (addWhisperTokens) {
      tokens.add(_specialTokens['<|startoftranscript|>'] ?? 50257);
      if (lang == 'vi') tokens.add(_specialTokens['<|vi|>'] ?? 50275);
      tokens.add(_specialTokens['<|transcribe|>'] ?? 50359);
      tokens.add(_specialTokens['<|notimestamps|>'] ?? 50362);
    }

    // Normalizing space to the special meta-character ' ' (U+2581)
    final normalized = text.toLowerCase().replaceAll(' ', ' ');
    int start = 0;
    while (start < normalized.length) {
      bool found = false;
      for (int end = normalized.length; end > start; end--) {
        final sub = normalized.substring(start, end);
        if (_vocab.containsKey(sub)) {
          tokens.add(_vocab[sub]!);
          start = end;
          found = true;
          break;
        }
      }
      if (!found) {
        final char = normalized[start];
        tokens.add(_vocab[char] ?? _specialTokens['<|unk|>'] ?? 3);
        start++;
      }
    }

    if (addWhisperTokens) {
      tokens.add(_specialTokens['<|endoftranscript|>'] ?? 50256);
    }
    return tokens;
  }

  String decode(List<int> tokens) {
    return tokens
        .map((t) => _invVocab[t] ?? '')
        .where((s) => !s.startsWith('<|')) // Filter special tokens
        .join('')
        .replaceAll(' ', ' ')
        .trim();
  }
}

```

