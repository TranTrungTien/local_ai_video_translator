import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../pipeline/presentation/ai_scheduler_controller.dart';
import '../../source_resolver/data/android_media_observer.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import '../data/embedded_audio_capture.dart';
import '../domain/embedded_capability.dart';
import 'media_session_controller.dart';
import 'native_player_view.dart';
import 'subtitle_overlay.dart';

class EmbeddedPlayerView extends ConsumerStatefulWidget {
  const EmbeddedPlayerView({required this.source, super.key});
  final ResolvedSource source;

  @override
  ConsumerState<EmbeddedPlayerView> createState() => _EmbeddedPlayerViewState();
}

class _EmbeddedPlayerViewState extends ConsumerState<EmbeddedPlayerView> {
  late final WebViewController _controller;
  final List<String> _runtimeCandidates = [];
  late final AndroidMediaObserver _mediaObserver;
  StreamSubscription? _observerSub;

  final EmbeddedAudioCaptureManager _audioCaptureManager =
      EmbeddedAudioCaptureManager();
  EmbeddedCapabilityProbe _capabilityProbe =
      EmbeddedCapabilityProbe.standardWeb;

  bool _isMigratedToNative = false;
  bool _isMigrating = false;
  String? _migrationErrorMessage;
  bool _aiSubtitlesEnabled = false;

  @override
  void initState() {
    super.initState();
    _mediaObserver = AndroidMediaObserver()..startObserving();
    _observerSub = _mediaObserver.candidates.listen((candidate) {
      if (!mounted) return;
      setState(() {
        final uriStr = candidate.uri.toString();
        if (!_runtimeCandidates.contains(uriStr)) {
          _runtimeCandidates.add(uriStr);
        }
      });
    });

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'MediaObserver',
        onMessageReceived: (message) {
          if (!mounted) return;
          setState(() {
            if (!_runtimeCandidates.contains(message.message)) {
              _runtimeCandidates.add(message.message);
            }
          });
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => _injectObserver()),
      )
      ..loadRequest(widget.source.uri);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(aiSchedulerProvider.notifier).initializeForSource(widget.source);
    });
  }

  Future<void> _injectObserver() async {
    const js = r'''
      (() => {
        const send = (value) => {
          if (typeof value !== 'string') return;
          if (/\.m3u8|\.mpd|\.mp4|\.webm/i.test(value)) {
            MediaObserver.postMessage(value);
          }
        };
        document.querySelectorAll('video,source,iframe').forEach(el => send(el.src));
        const oldFetch = window.fetch;
        window.fetch = function(...args) { send(String(args[0])); return oldFetch.apply(this, args); };
        const oldOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url, ...rest) {
          send(String(url));
          return oldOpen.call(this, method, url, ...rest);
        };
        new PerformanceObserver(list => list.getEntries().forEach(e => send(e.name)))
          .observe({entryTypes: ['resource']});
      })();
    ''';
    await _controller.runJavaScript(js);
  }

  Future<void> _startNativeMigration() async {
    setState(() {
      _isMigrating = true;
      _migrationErrorMessage = null;
    });

    final targetCandidateUri = _runtimeCandidates.isNotEmpty
        ? Uri.tryParse(_runtimeCandidates.first) ?? widget.source.finalUri
        : widget.source.finalUri;

    final candidateSource = ResolvedSource(
      input: widget.source.input,
      normalizedUri: targetCandidateUri,
      finalUri: targetCandidateUri,
      kind: MediaKind.hls,
      playbackMode: PlaybackMode.native,
      discoveryMethod: DiscoveryMethod.runtime,
      capability: SourceCapability.full,
      requestContext: widget.source.requestContext,
      iframeChain: widget.source.iframeChain,
    );

    final success = await ref
        .read(mediaSessionControllerProvider.notifier)
        .attemptMigrationToNative(source: candidateSource);

    if (!mounted) return;

    if (success) {
      setState(() {
        _isMigratedToNative = true;
        _isMigrating = false;
      });
    } else {
      final migrationStatus = ref.read(migrationControllerProvider).status;
      setState(() {
        _isMigrating = false;
        _migrationErrorMessage =
            'Migration failed (status: ${migrationStatus.name}). Retaining Embedded WebView.';
        // Probe capabilities for embedded AI fallback
        _capabilityProbe = const EmbeddedCapabilityProbe(
          canPlay: true,
          canPause: true,
          canReadPosition: true,
          canObserveSeek: true,
          canAccessAudio: false, // Requires explicit user audio capture consent
        );
      });
    }
  }

  /// Explicit user action to request audio capture consent for embedded AI subtitles.
  /// Never requested on app startup.
  Future<void> _requestEmbeddedAiConsent() async {
    final granted = await _audioCaptureManager.requestConsentAndStartCapture();
    if (!mounted) return;

    if (granted) {
      setState(() {
        _aiSubtitlesEnabled = true;
        _capabilityProbe = const EmbeddedCapabilityProbe(
          canPlay: true,
          canPause: true,
          canReadPosition: true,
          canObserveSeek: true,
          canAccessAudio: true,
        );
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Audio capture permission denied. Embedded AI subtitles degraded gracefully.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _observerSub?.cancel();
    _mediaObserver.dispose();
    _audioCaptureManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isMigratedToNative) {
      return NativePlayerView(source: widget.source);
    }

    final aiState = ref.watch(aiSchedulerProvider);

    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_aiSubtitlesEnabled && _capabilityProbe.canAccessAudio)
          SubtitleOverlay(segment: aiState.activeSegment),

        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Card(
            color: Colors.black.withValues(alpha: 0.9),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        color: Color(0xFF7C5CFC),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _migrationErrorMessage != null
                              ? 'Embedded Fallback Mode (Capabilities: Play=${_capabilityProbe.canPlay}, Audio=${_capabilityProbe.canAccessAudio})'
                              : 'Runtime Media Candidates (${_runtimeCandidates.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (!_isMigrating &&
                          !_isMigratedToNative &&
                          _migrationErrorMessage == null)
                        FilledButton.icon(
                          onPressed: _startNativeMigration,
                          icon: const Icon(Icons.play_circle_fill, size: 16),
                          label: const Text('Migrate Native'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      if (_migrationErrorMessage != null &&
                          !_aiSubtitlesEnabled)
                        FilledButton.icon(
                          onPressed: _requestEmbeddedAiConsent,
                          icon: const Icon(Icons.mic, size: 16),
                          label: const Text('Enable AI Subtitles'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF7C5CFC),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                  if (_isMigrating) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(color: Color(0xFF7C5CFC)),
                    const SizedBox(height: 4),
                    const Text(
                      'Verifying candidate accessibility and preparing native player...',
                      style: TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                  if (_migrationErrorMessage != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _migrationErrorMessage!,
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 11,
                      ),
                    ),
                  ],
                  if (_aiSubtitlesEnabled) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Embedded AI audio capture active. Synchronizing Vietnamese subtitles.',
                      style: TextStyle(color: Colors.greenAccent, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
