import 'dart:async';
import 'package:flutter/services.dart';

import 'media_candidate.dart';
import '../domain/entities/resolved_source.dart';

class AndroidMediaObserver {
  AndroidMediaObserver();

  static const _eventChannel = EventChannel(
    'local_ai_video_translator/media_events',
  );
  StreamSubscription<dynamic>? _subscription;
  final _candidateController = StreamController<MediaCandidate>.broadcast();

  Stream<MediaCandidate> get candidates => _candidateController.stream;

  void startObserving() {
    _subscription?.cancel();
    try {
      _subscription = _eventChannel.receiveBroadcastStream().listen(
        _onEvent,
        onError: (error) {
          // Event channel error ignored gracefully
        },
      );
    } catch (_) {
      // Platform channel not available in non-Android environment
    }
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final urlStr = event['url'] as String?;
    if (urlStr == null || urlStr.isEmpty) return;

    final uri = Uri.tryParse(urlStr);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return;

    final path = uri.path.toLowerCase();
    MediaKind? kind;
    if (path.endsWith('.m3u8')) {
      kind = MediaKind.hls;
    } else if (path.endsWith('.mpd')) {
      kind = MediaKind.dash;
    } else if (['.mp4', '.webm', '.mkv', '.m4v', '.mov'].any(path.endsWith)) {
      kind = MediaKind.progressive;
    }

    if (kind != null) {
      _candidateController.add(
        MediaCandidate(
          uri: uri,
          kind: kind,
          method: DiscoveryMethod.runtime,
          score: 80,
        ),
      );
    }
  }

  void stopObserving() {
    _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    stopObserving();
    _candidateController.close();
  }
}
