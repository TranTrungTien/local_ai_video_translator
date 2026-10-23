import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../presentation/main_shell_page.dart';
import '../../features/player/presentation/player_page.dart';
import '../../features/settings/presentation/ai_settings_page.dart';
import '../../features/settings/presentation/model_manager_page.dart';
import '../../features/source_resolver/domain/entities/resolved_source.dart';
import '../../features/source_resolver/presentation/source_analysis_page.dart';
import '../../features/pipeline/presentation/ai_pipeline_progress_page.dart';
import '../../features/debug/presentation/web_ai_test_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text('Page not found: ${state.uri}')),
    ),
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const MainShellPage(),
      ),
      GoRoute(
        path: '/debug',
        builder: (context, state) => const WebAiTestScreen(),
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
          title: 'Dịch Video',
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
