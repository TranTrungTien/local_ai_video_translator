import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../pipeline/presentation/ai_scheduler_controller.dart';
import '../../source_resolver/data/android_media_observer.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import '../../../core/utils/sha256_util.dart';
import '../data/embedded_audio_capture.dart';
import '../domain/embedded_capability.dart';
import '../domain/entities/embedded_playback_snapshot.dart';
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
  bool _isMigratedToNative = false;
  late final WebViewController _controller;
  final String _nonce = Sha256Util.generateNonce();
  final List<String> _runtimeCandidates = [];
  late final AndroidMediaObserver _mediaObserver;
  StreamSubscription? _observerSub;

  final EmbeddedAudioCaptureManager _audioCaptureManager =
      EmbeddedAudioCaptureManager();
  EmbeddedCapabilityProbe _capabilityProbe =
      EmbeddedCapabilityProbe.standardWeb;

  ResolvedSource? _migratedSource;
  bool _isMigrating = false;
  String? _migrationErrorMessage;
  bool _aiSubtitlesEnabled = false;
  Timer? _positionUpdateTimer;

  Duration _lastPosition = Duration.zero;
  bool _lastIsPlaying = false;
  double _lastPlaybackRate = 1.0;

  @override
  void initState() {
    super.initState();
    _mediaObserver = AndroidMediaObserver()..startObserving();
    _observerSub = _mediaObserver.candidates.listen((candidate) {
      if (!mounted || _isMigratedToNative) return;
      setState(() {
        final uriStr = candidate.uri.toString();
        if (!_runtimeCandidates.contains(uriStr)) {
          _runtimeCandidates.insert(0, uriStr); // Prioritize new candidates
        }
      });
    });

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'MediaObserver',
        onMessageReceived: (message) {
          if (!mounted || _isMigratedToNative) return;
          final data = message.message;
          if (data.startsWith('pos:')) {
            final parts = data.substring(4).split(',');
            final seconds = double.tryParse(parts[0]) ?? 0.0;
            _lastIsPlaying = parts.length > 1 ? parts[1] == 'true' : false;
            _lastPlaybackRate = parts.length > 2 ? double.tryParse(parts[2]) ?? 1.0 : 1.0;

            _lastPosition = Duration(milliseconds: (seconds * 1000).toInt());

            ref
                .read(aiSchedulerProvider.notifier)
                .updatePlaybackPosition(_lastPosition);

            // Update native audio anchor for PTS interpolation if capture is active
            if (_aiSubtitlesEnabled) {
               ref.read(mediaSessionControllerProvider.notifier).updateNativeAudioAnchor(
                 position: _lastPosition,
                 isPlaying: _lastIsPlaying,
                 playbackRate: _lastPlaybackRate,
                 timelineEpoch: 0,
                 playbackSessionId: ref.read(aiSchedulerProvider.notifier).activeSessionId,
                 seekGeneration: ref.read(aiSchedulerProvider.notifier).generation,
               );
            }
          } else {
            setState(() {
              if (!_runtimeCandidates.contains(data)) {
                _runtimeCandidates.insert(0, data);
              }
            });
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _injectObserver();
            _startPositionPolling();
          },
          onNavigationRequest: (request) {
            // Prevent navigation to non-http(s) schemes
            if (!request.url.startsWith('http')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(widget.source.uri);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(aiSchedulerProvider.notifier).initializeForSource(widget.source);
    });
  }

  void _startPositionPolling() {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      if (!mounted || _isMigratedToNative) {
        timer.cancel();
        return;
      }
      _controller.runJavaScript(r'''
        (function() {
          var v = document.querySelector('video');
          if (v) {
            MediaObserver.postMessage('pos:' + v.currentTime + ',' + !v.paused + ',' + v.playbackRate);
          }
        })();
      ''');
    });
  }

  Future<void> _injectObserver() async {
    final js = '''
      (() => {
        // Nonce validation for the injected observer
        const expectedNonce = '$_nonce';

        const send = (value) => {
          if (typeof value !== 'string' || value.length < 10) return;
           if (RegExp('\\.(m3u8|mpd|mp4|webm|mkv|mov|m4v)', 'i').test(value)) {
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
      kind: _inferKind(targetCandidateUri),
      playbackMode: PlaybackMode.native,
      discoveryMethod: DiscoveryMethod.runtime,
      capability: SourceCapability.full,
      requestContext: widget.source.requestContext,
      iframeChain: widget.source.iframeChain,
    );

    final snapshot = EmbeddedPlaybackSnapshot(
      source: widget.source.uri,
      position: _lastPosition,
      playbackRate: _lastPlaybackRate,
      wasPlaying: _lastIsPlaying,
      volume: 100.0,
      playbackSessionId: ref.read(aiSchedulerProvider).activeSessionId,
      timelineEpoch: 0,
      requestHeaders: widget.source.requestContext.headers,
    );

    final success = await ref
        .read(mediaSessionControllerProvider.notifier)
        .attemptMigrationToNative(
          source: candidateSource,
          snapshot: snapshot,
        );

    if (!mounted) return;

    if (success) {
      _cleanupEmbeddedResources();
      setState(() {
        _isMigratedToNative = true;
        _migratedSource = candidateSource;
        _isMigrating = false;
      });
    } else {
      final migrationStatus = ref.read(migrationControllerProvider).status;
      setState(() {
        _isMigrating = false;
        _migrationErrorMessage =
            'Migration failed (status: ${migrationStatus.name}). Retaining Embedded WebView.';
      });
    }
  }

  void _cleanupEmbeddedResources() {
    _isMigratedToNative = true;
    _positionUpdateTimer?.cancel();
    _observerSub?.cancel();
    _controller.runJavaScript("var v = document.querySelector('video'); if(v) v.pause();");
    _audioCaptureManager.dispose();
  }

  MediaKind _inferKind(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.endsWith('.m3u8')) return MediaKind.hls;
    if (path.endsWith('.mpd')) return MediaKind.dash;
    return MediaKind.progressive;
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
      // Start AI Pipeline
      unawaited(ref.read(aiSchedulerProvider.notifier).startAiPipelineForEmbedded());
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
    _positionUpdateTimer?.cancel();
    _observerSub?.cancel();
    _mediaObserver.dispose();
    _audioCaptureManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_migratedSource != null) {
      return NativePlayerView(source: _migratedSource!);
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
