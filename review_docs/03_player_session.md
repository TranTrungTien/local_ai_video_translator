# Review Module: 03. Player Session & Controls

## Included Files (17 files)

```text
lib/features/player/data/embedded_audio_capture.dart
lib/features/player/data/migration_controller.dart
lib/features/player/data/native_media_session.dart
lib/features/player/data/player_diagnostics.dart
lib/features/player/domain/embedded_capability.dart
lib/features/player/domain/entities/embedded_playback_snapshot.dart
lib/features/player/domain/entities/media_session_snapshot.dart
lib/features/player/domain/entities/media_track.dart
lib/features/player/domain/entities/migration_state.dart
lib/features/player/domain/entities/player_state.dart
lib/features/player/domain/playback_contract.dart
lib/features/player/domain/services/media_session.dart
lib/features/player/presentation/embedded_player_view.dart
lib/features/player/presentation/media_session_controller.dart
lib/features/player/presentation/native_player_view.dart
lib/features/player/presentation/player_page.dart
lib/features/player/presentation/subtitle_overlay.dart
```

## lib/features/player/data/embedded_audio_capture.dart
```dart:lib/features/player/data/embedded_audio_capture.dart
import 'dart:async';
import 'package:flutter/services.dart';

enum AudioCaptureState { idle, requestingConsent, active, denied, error }

class EmbeddedAudioCaptureManager {
  AudioCaptureState _state = AudioCaptureState.idle;
  final _stateController = StreamController<AudioCaptureState>.broadcast();
  static const _methodChannel = MethodChannel('local_ai_video_translator/native_resolver');

  AudioCaptureState get state => _state;
  Stream<AudioCaptureState> get stateStream => _stateController.stream;

  /// Requests explicit user consent for Android playback audio capture (MediaProjection / AudioPlaybackCapture).
  /// Never invoked on app startup; only on explicit user request after native migration failure.
  Future<bool> requestConsentAndStartCapture() async {
    if (_state == AudioCaptureState.active) return true;

    _updateState(AudioCaptureState.requestingConsent);

    try {
      final bool? started = await _methodChannel.invokeMethod<bool>('startAudioCapture');
      if (started == true) {
        _updateState(AudioCaptureState.active);
        return true;
      } else {
        _updateState(AudioCaptureState.denied);
        return false;
      }
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        _updateState(AudioCaptureState.denied);
      } else {
        _updateState(AudioCaptureState.error);
      }
      return false;
    } catch (_) {
      _updateState(AudioCaptureState.error);
      return false;
    }
  }

  Future<void> stopCapture() async {
    try {
      await _methodChannel.invokeMethod('stopAudioCapture');
    } finally {
      _updateState(AudioCaptureState.idle);
    }
  }

  void _updateState(AudioCaptureState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  void dispose() {
    _stateController.close();
  }
}

```

## lib/features/player/data/migration_controller.dart
```dart:lib/features/player/data/migration_controller.dart
import 'dart:async';

import 'package:local_ai_video_translator/core/diagnostics/diagnostics_service.dart';
import 'package:local_ai_video_translator/core/utils/cancellation_token.dart';
import 'package:local_ai_video_translator/features/source_resolver/data/candidate_verifier.dart';
import 'package:local_ai_video_translator/features/source_resolver/domain/entities/resolved_source.dart';

import '../domain/entities/embedded_playback_snapshot.dart';
import '../domain/entities/migration_state.dart';
import '../domain/entities/player_state.dart';
import 'native_media_session.dart';

class NativeMigrationController {
  NativeMigrationController(
    this._nativeSession,
    this._verifier,
    this._diagnostics,
  );

  final NativeMediaSession _nativeSession;
  final CandidateVerifier _verifier;
  final DiagnosticsService _diagnostics;

  MigrationStatus _status = MigrationStatus.embedded;
  final _statusController = StreamController<MigrationStatus>.broadcast();

  MigrationStatus get status => _status;
  Stream<MigrationStatus> get statusStream => _statusController.stream;

  int _activeTransactionId = 0;
  CancellationToken? _activeCancellationToken;

  Future<NativeMigrationResult> attemptMigration({
    required ResolvedSource source,
    required EmbeddedPlaybackSnapshot snapshot,
  }) async {
    final transactionId = ++_activeTransactionId;
    _activeCancellationToken?.cancel();
    _activeCancellationToken = CancellationToken();
    final token = _activeCancellationToken!;

    final stopwatch = Stopwatch()..start();

    _updateStatus(MigrationStatus.validatingCandidate);
    _diagnostics.log(
      'MigrationController',
      'Beginning migration transaction #$transactionId for ${source.finalUri}',
    );

    try {
      // Step 1: Validate candidate accessibility
      final candidate =
          source.selectedCandidate ?? source.candidates.firstOrNull;

      if (candidate != null) {
        final verification = await _verifier.verify(candidate);
        if (transactionId != _activeTransactionId || token.isCancelled) {
          throw OperationCancelledException();
        }
        if (!verification.isAccessible) {
          throw NativePlayerBackendException(
            'Candidate ${candidate.uri} failed verification: ${verification.error ?? 'HTTP ${verification.statusCode}'}',
          );
        }
      }

      // Step 2: Prepare native player session
      _updateStatus(MigrationStatus.preparingNative);

      // If native session is already playing this source, don't reopen
      if (_nativeSession.currentSnapshot.mediaIdentity != source.finalUri.toString() ||
          _nativeSession.currentSnapshot.status == PlayerStatus.idle ||
          _nativeSession.currentSnapshot.status == PlayerStatus.error) {
        await _nativeSession.open(source);
      }

      if (transactionId != _activeTransactionId || token.isCancelled) {
        throw OperationCancelledException();
      }

      if (_nativeSession.currentSnapshot.status == PlayerStatus.error) {
        throw _nativeSession.currentSnapshot.error ??
            const NativePlayerBackendException(
              'Native player encountered error during preparation',
            );
      }

      // Step 3: Sync state (Seek, Rate, Volume)
      _diagnostics.log(
        'MigrationController',
        'Syncing state to native: position=${snapshot.position}, rate=${snapshot.playbackRate}',
      );

      await _nativeSession.seek(snapshot.position);
      await _nativeSession.setPlaybackRate(snapshot.playbackRate);
      await _nativeSession.setVolume(snapshot.volume);

      if (transactionId != _activeTransactionId || token.isCancelled) {
        throw OperationCancelledException();
      }

      if (snapshot.wasPlaying) {
        await _nativeSession.play();
      } else {
        await _nativeSession.pause();
      }

      if (transactionId != _activeTransactionId || token.isCancelled) {
        throw OperationCancelledException();
      }

      _updateStatus(MigrationStatus.nativeReady);

      // Step 4: Atomic cutover
      stopwatch.stop();
      _updateStatus(MigrationStatus.switchedToNative);

      return NativeMigrationResult(
        status: MigrationStatus.switchedToNative,
        attemptedCandidateUri: source.finalUri,
        capturedPosition: snapshot.position,
        prepareDuration: stopwatch.elapsed,
      );
    } on OperationCancelledException {
      _diagnostics.log('MigrationController', 'Discarding cancelled/superceded transaction #$transactionId');
      return NativeMigrationResult(
        status: MigrationStatus.nativeFailedReverted,
        attemptedCandidateUri: source.finalUri,
      );
    } catch (e) {
      if (transactionId != _activeTransactionId || token.isCancelled) {
        _diagnostics.log('MigrationController', 'Discarding failed superceded transaction #$transactionId');
        return NativeMigrationResult(
          status: MigrationStatus.nativeFailedReverted,
          attemptedCandidateUri: source.finalUri,
        );
      }

      stopwatch.stop();
      _diagnostics.log(
        'MigrationController',
        'Native migration failed: $e. Reverting to embedded WebView.',
        level: LogLevel.warning,
      );

      // Only close if it was this transaction that failed
      await _nativeSession.close();
      _updateStatus(MigrationStatus.nativeFailedReverted);

      return NativeMigrationResult(
        status: MigrationStatus.nativeFailedReverted,
        attemptedCandidateUri: source.finalUri,
        capturedPosition: snapshot.position,
        prepareDuration: stopwatch.elapsed,
        failureReason: e.toString(),
      );
    }
  }

  void _updateStatus(MigrationStatus newStatus) {
    _status = newStatus;
    if (!_statusController.isClosed) {
      _statusController.add(_status);
    }
  }

  void dispose() {
    _activeCancellationToken?.cancel();
    _statusController.close();
  }
}

```

## lib/features/player/data/native_media_session.dart
```dart:lib/features/player/data/native_media_session.dart
import 'dart:async';

import 'package:media_kit/media_kit.dart' as mk;

import '../../source_resolver/domain/entities/resolved_source.dart';
import '../domain/entities/media_session_snapshot.dart';
import '../domain/entities/media_track.dart';
import '../domain/entities/player_state.dart';
import '../domain/services/media_session.dart';
import 'player_diagnostics.dart';

class NativeMediaSession implements MediaSession {
  NativeMediaSession([PlayerDiagnostics? diagnostics])
    : _diagnostics = diagnostics ?? PlayerDiagnostics();

  final PlayerDiagnostics _diagnostics;
  mk.Player? _player;

  MediaSessionSnapshot _snapshot = MediaSessionSnapshot.idle;
  final _snapshotController =
      StreamController<MediaSessionSnapshot>.broadcast();

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  mk.Player? get player => _player;

  @override
  MediaSessionSnapshot get currentSnapshot => _snapshot;

  @override
  Stream<MediaSessionSnapshot> get snapshotStream => _snapshotController.stream;

  PlayerDiagnostics get diagnostics => _diagnostics;

  @override
  Future<void> open(ResolvedSource source) async {
    final prepareStopwatch = Stopwatch()..start();
    await close();

    _player = mk.Player();

    _updateSnapshot(
      MediaSessionSnapshot.idle.copyWith(
        mediaIdentity: source.finalUri.toString(),
        status: PlayerStatus.initializing,
        requestContext: source.requestContext,
      ),
    );

    // Bind player event streams
    _subscriptions.addAll([
      _player!.stream.position.listen((pos) {
        _updateSnapshot(_snapshot.copyWith(position: pos));
      }),
      _player!.stream.duration.listen((dur) {
        _updateSnapshot(_snapshot.copyWith(duration: dur));
      }),
      _player!.stream.buffer.listen((buf) {
        _updateSnapshot(_snapshot.copyWith(buffered: buf));
      }),
      _player!.stream.playing.listen((playing) {
        _updateSnapshot(
          _snapshot.copyWith(
            status: playing ? PlayerStatus.playing : PlayerStatus.paused,
          ),
        );
      }),
      _player!.stream.buffering.listen((buffering) {
        if (buffering) {
          _diagnostics.incrementBufferEvents();
          _updateSnapshot(_snapshot.copyWith(status: PlayerStatus.buffering));
        }
      }),
      _player!.stream.completed.listen((completed) {
        if (completed) {
          _updateSnapshot(_snapshot.copyWith(status: PlayerStatus.ended));
        }
      }),
      _player!.stream.rate.listen((rate) {
        _updateSnapshot(_snapshot.copyWith(playbackRate: rate));
      }),
      _player!.stream.tracks.listen((tracks) {
        _enumerateTracks(tracks);
      }),
      _player!.stream.error.listen((errorStr) {
        if (errorStr.isNotEmpty) {
          final err = NativePlayerBackendException('MediaKit error: $errorStr');
          _diagnostics.recordError(err.toString());
          _updateSnapshot(
            _snapshot.copyWith(status: PlayerStatus.error, error: err),
          );
        }
      }),
    ]);

    try {
      // Pass isolated request context headers to media_kit
      final media = mk.Media(
        source.finalUri.toString(),
        httpHeaders: source.requestContext.headers,
      );

      await _player!.open(media, play: false);

      prepareStopwatch.stop();
      _diagnostics.recordPrepareDuration(prepareStopwatch.elapsed);

      _updateSnapshot(
        _snapshot.copyWith(
          status: PlayerStatus.ready,
          duration: _player!.state.duration,
        ),
      );
    } catch (e) {
      prepareStopwatch.stop();
      final err = PlaybackInitializationException(
        'Could not initialize native media playback',
        e,
      );
      _diagnostics.recordError(err.toString());
      _updateSnapshot(
        _snapshot.copyWith(status: PlayerStatus.error, error: err),
      );
      rethrow;
    }
  }

  void _enumerateTracks(mk.Tracks tracks) {
    final videoList = <VideoTrack>[];
    final audioList = <AudioTrack>[];
    final subtitleList = <PlayerSubtitleTrack>[];

    for (var i = 0; i < tracks.video.length; i++) {
      final vt = tracks.video[i];
      videoList.add(
        VideoTrack(
          id: vt.id,
          label: vt.title ?? 'Video Stream #${i + 1}',
          language: vt.language,
          codec: vt.codec,
        ),
      );
    }

    for (var i = 0; i < tracks.audio.length; i++) {
      final at = tracks.audio[i];
      final channelCount = int.tryParse(at.channels ?? '');
      audioList.add(
        AudioTrack(
          id: at.id,
          label: at.title ?? 'Audio Stream #${i + 1}',
          language: at.language,
          channels: channelCount,
          codec: at.codec,
          isDefault: i == 0,
        ),
      );
    }

    for (var i = 0; i < tracks.subtitle.length; i++) {
      final st = tracks.subtitle[i];
      final lang = st.language ?? 'unknown';
      subtitleList.add(
        PlayerSubtitleTrack(
          id: st.id,
          label: st.title ?? 'Subtitle #${i + 1} ($lang)',
          language: lang,
          isEmbedded: true,
          classification: PlayerSubtitleTrack.classify(lang),
        ),
      );
    }

    final trackSet = MediaTrackSet(
      videoTracks: List.unmodifiable(videoList),
      audioTracks: List.unmodifiable(audioList),
      subtitleTracks: List.unmodifiable(subtitleList),
    );

    _updateSnapshot(_snapshot.copyWith(trackSet: trackSet));
  }

  @override
  Future<void> play() async {
    if (_player == null) return;
    await _player!.play();
  }

  @override
  Future<void> pause() async {
    if (_player == null) return;
    await _player!.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_player == null) return;
    _updateSnapshot(_snapshot.copyWith(status: PlayerStatus.seeking));
    await _player!.seek(position);
  }

  @override
  Future<void> setPlaybackRate(double rate) async {
    if (_player == null) return;
    await _player!.setRate(rate);
  }

  @override
  Future<void> selectVideoTrack(VideoTrack track) async {
    if (_player == null) return;
    final mkTrack = _player!.state.tracks.video.firstWhere(
      (t) => t.id == track.id,
      orElse: () => _player!.state.tracks.video.first,
    );
    await _player!.setVideoTrack(mkTrack);
    _updateSnapshot(_snapshot.copyWith(activeVideoTrack: track));
  }

  @override
  Future<void> selectAudioTrack(AudioTrack track) async {
    if (_player == null) return;
    final mkTrack = _player!.state.tracks.audio.firstWhere(
      (t) => t.id == track.id,
      orElse: () => _player!.state.tracks.audio.first,
    );
    await _player!.setAudioTrack(mkTrack);
    _updateSnapshot(_snapshot.copyWith(activeAudioTrack: track));
  }

  @override
  Future<void> selectSubtitleTrack(PlayerSubtitleTrack? track) async {
    if (_player == null) return;
    if (track == null) {
      await _player!.setSubtitleTrack(mk.SubtitleTrack.no());
      _updateSnapshot(_snapshot.copyWith(activeSubtitleTrack: null));
    } else {
      final mkTrack = _player!.state.tracks.subtitle.firstWhere(
        (t) => t.id == track.id,
        orElse: () => _player!.state.tracks.subtitle.first,
      );
      await _player!.setSubtitleTrack(mkTrack);
      _updateSnapshot(_snapshot.copyWith(activeSubtitleTrack: track));
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    if (_player == null) return;
    await _player!.setVolume(volume);
    _updateSnapshot(_snapshot.copyWith(volume: volume));
  }

  @override
  Future<void> close() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    if (_player != null) {
      await _player!.dispose();
      _player = null;
    }

    _diagnostics.reset();
    _updateSnapshot(MediaSessionSnapshot.idle);
  }

  void _updateSnapshot(MediaSessionSnapshot newSnapshot) {
    _snapshot = newSnapshot;
    if (!_snapshotController.isClosed) {
      _snapshotController.add(_snapshot);
    }
  }
}

```

## lib/features/player/data/player_diagnostics.dart
```dart:lib/features/player/data/player_diagnostics.dart
import 'dart:async';

class PlayerDiagnosticsMetrics {
  const PlayerDiagnosticsMetrics({
    this.prepareDuration = Duration.zero,
    this.bufferEventCount = 0,
    this.droppedFrameCount = 0,
    this.decoderInfo = 'Software/Hardware Default',
    this.bandwidthEstimate = 0,
    this.lastError,
  });

  final Duration prepareDuration;
  final int bufferEventCount;
  final int droppedFrameCount;
  final String decoderInfo;
  final int bandwidthEstimate; // bits per second
  final String? lastError;

  PlayerDiagnosticsMetrics copyWith({
    Duration? prepareDuration,
    int? bufferEventCount,
    int? droppedFrameCount,
    String? decoderInfo,
    int? bandwidthEstimate,
    String? lastError,
  }) {
    return PlayerDiagnosticsMetrics(
      prepareDuration: prepareDuration ?? this.prepareDuration,
      bufferEventCount: bufferEventCount ?? this.bufferEventCount,
      droppedFrameCount: droppedFrameCount ?? this.droppedFrameCount,
      decoderInfo: decoderInfo ?? this.decoderInfo,
      bandwidthEstimate: bandwidthEstimate ?? this.bandwidthEstimate,
      lastError: lastError ?? this.lastError,
    );
  }
}

class PlayerDiagnostics {
  PlayerDiagnosticsMetrics _metrics = const PlayerDiagnosticsMetrics();
  final _controller = StreamController<PlayerDiagnosticsMetrics>.broadcast();

  PlayerDiagnosticsMetrics get metrics => _metrics;
  Stream<PlayerDiagnosticsMetrics> get stream => _controller.stream;

  void recordPrepareDuration(Duration duration) {
    _metrics = _metrics.copyWith(prepareDuration: duration);
    _controller.add(_metrics);
  }

  void incrementBufferEvents() {
    _metrics = _metrics.copyWith(
      bufferEventCount: _metrics.bufferEventCount + 1,
    );
    _controller.add(_metrics);
  }

  void updateDroppedFrames(int count) {
    _metrics = _metrics.copyWith(droppedFrameCount: count);
    _controller.add(_metrics);
  }

  void updateDecoderInfo(String info) {
    _metrics = _metrics.copyWith(decoderInfo: info);
    _controller.add(_metrics);
  }

  void updateBandwidthEstimate(int bps) {
    _metrics = _metrics.copyWith(bandwidthEstimate: bps);
    _controller.add(_metrics);
  }

  void recordError(String error) {
    _metrics = _metrics.copyWith(lastError: error);
    _controller.add(_metrics);
  }

  void reset() {
    _metrics = const PlayerDiagnosticsMetrics();
    _controller.add(_metrics);
  }

  void dispose() {
    _controller.close();
  }
}

```

## lib/features/player/domain/embedded_capability.dart
```dart:lib/features/player/domain/embedded_capability.dart
class EmbeddedCapabilityProbe {
  const EmbeddedCapabilityProbe({
    required this.canPlay,
    required this.canPause,
    required this.canReadPosition,
    required this.canObserveSeek,
    required this.canAccessAudio,
  });

  final bool canPlay;
  final bool canPause;
  final bool canReadPosition;
  final bool canObserveSeek;
  final bool canAccessAudio;

  bool get isEmbeddedAiSupported =>
      canPlay &&
      canPause &&
      canReadPosition &&
      canObserveSeek &&
      canAccessAudio;

  static const unsupported = EmbeddedCapabilityProbe(
    canPlay: false,
    canPause: false,
    canReadPosition: false,
    canObserveSeek: false,
    canAccessAudio: false,
  );

  static const standardWeb = EmbeddedCapabilityProbe(
    canPlay: true,
    canPause: true,
    canReadPosition: true,
    canObserveSeek: true,
    canAccessAudio:
        false, // Requires explicit user audio capture permission consent
  );
}

```

## lib/features/player/domain/entities/embedded_playback_snapshot.dart
```dart:lib/features/player/domain/entities/embedded_playback_snapshot.dart

class EmbeddedPlaybackSnapshot {
  const EmbeddedPlaybackSnapshot({
    required this.source,
    required this.position,
    this.duration,
    required this.playbackRate,
    required this.wasPlaying,
    required this.volume,
    required this.playbackSessionId,
    required this.timelineEpoch,
    required this.requestHeaders,
  });

  final Uri source;
  final Duration position;
  final Duration? duration;
  final double playbackRate;
  final bool wasPlaying;
  final double volume;
  final String playbackSessionId;
  final int timelineEpoch;
  final Map<String, String> requestHeaders;

  @override
  String toString() {
    return 'EmbeddedPlaybackSnapshot(position: $position, wasPlaying: $wasPlaying, playbackRate: $playbackRate)';
  }
}

```

## lib/features/player/domain/entities/media_session_snapshot.dart
```dart:lib/features/player/domain/entities/media_session_snapshot.dart
import '../../../source_resolver/domain/entities/resolved_source.dart';
import 'media_track.dart';
import 'migration_state.dart';
import 'player_state.dart';

class MediaSessionSnapshot {
  static const Object _notProvided = Object();
  const MediaSessionSnapshot({
    required this.mediaIdentity,
    required this.duration,
    required this.position,
    required this.buffered,
    required this.status,
    required this.playbackRate,
    this.volume = 100.0,
    this.activeVideoTrack,
    this.activeAudioTrack,
    this.activeSubtitleTrack,
    this.trackSet = MediaTrackSet.empty,
    this.requestContext = RequestContext.defaultContext,
    this.error,
    this.migrationStatus = MigrationStatus.embedded,
  });

  final String mediaIdentity;
  final Duration duration;
  final Duration position;
  final Duration buffered;
  final PlayerStatus status;
  final double playbackRate;
  final double volume;
  final VideoTrack? activeVideoTrack;
  final AudioTrack? activeAudioTrack;
  final PlayerSubtitleTrack? activeSubtitleTrack;
  final MediaTrackSet trackSet;
  final RequestContext requestContext;
  final PlayerError? error;
  final MigrationStatus migrationStatus;

  bool get isPlaying => status == PlayerStatus.playing;
  bool get isPaused => status == PlayerStatus.paused;
  bool get isBuffering => status == PlayerStatus.buffering;
  bool get isCompleted => status == PlayerStatus.ended;
  bool get isReady =>
      status == PlayerStatus.ready ||
      status == PlayerStatus.playing ||
      status == PlayerStatus.paused;

  MediaSessionSnapshot copyWith({
    String? mediaIdentity,
    Duration? duration,
    Duration? position,
    Duration? buffered,
    PlayerStatus? status,
    double? playbackRate,
    double? volume,
    VideoTrack? activeVideoTrack,
    AudioTrack? activeAudioTrack,
    Object? activeSubtitleTrack = _notProvided,
    MediaTrackSet? trackSet,
    RequestContext? requestContext,
    Object? error = _notProvided,
    MigrationStatus? migrationStatus,
  }) {
    return MediaSessionSnapshot(
      mediaIdentity: mediaIdentity ?? this.mediaIdentity,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      buffered: buffered ?? this.buffered,
      status: status ?? this.status,
      playbackRate: playbackRate ?? this.playbackRate,
      volume: volume ?? this.volume,
      activeVideoTrack: activeVideoTrack ?? this.activeVideoTrack,
      activeAudioTrack: activeAudioTrack ?? this.activeAudioTrack,
      activeSubtitleTrack: identical(activeSubtitleTrack, _notProvided)
          ? this.activeSubtitleTrack
          : activeSubtitleTrack as PlayerSubtitleTrack?,
      trackSet: trackSet ?? this.trackSet,
      requestContext: requestContext ?? this.requestContext,
      error: identical(error, _notProvided) ? this.error : error as PlayerError?,
      migrationStatus: migrationStatus ?? this.migrationStatus,
    );
  }

  static const idle = MediaSessionSnapshot(
    mediaIdentity: '',
    duration: Duration.zero,
    position: Duration.zero,
    buffered: Duration.zero,
    status: PlayerStatus.idle,
    playbackRate: 1.0,
    volume: 100.0,
  );
}


```

## lib/features/player/domain/entities/media_track.dart
```dart:lib/features/player/domain/entities/media_track.dart
enum SubtitleClassification { vietnamese, sourceLanguage, unknownOther }

class VideoTrack {
  const VideoTrack({
    required this.id,
    required this.label,
    this.language,
    this.width,
    this.height,
    this.bitrate,
    this.codec,
    this.isSelected = false,
  });

  final String id;
  final String label;
  final String? language;
  final int? width;
  final int? height;
  final int? bitrate;
  final String? codec;
  final bool isSelected;

  VideoTrack copyWith({bool? isSelected}) {
    return VideoTrack(
      id: id,
      label: label,
      language: language,
      width: width,
      height: height,
      bitrate: bitrate,
      codec: codec,
      isSelected: isSelected ?? this.isSelected,
    );
  }
}

class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.label,
    this.language,
    this.channels,
    this.sampleRate,
    this.codec,
    this.isSelected = false,
    this.isDefault = false,
  });

  final String id;
  final String label;
  final String? language;
  final int? channels;
  final int? sampleRate;
  final String? codec;
  final bool isSelected;
  final bool isDefault;

  AudioTrack copyWith({bool? isSelected}) {
    return AudioTrack(
      id: id,
      label: label,
      language: language,
      channels: channels,
      sampleRate: sampleRate,
      codec: codec,
      isSelected: isSelected ?? this.isSelected,
      isDefault: isDefault,
    );
  }
}

class PlayerSubtitleTrack {
  const PlayerSubtitleTrack({
    required this.id,
    required this.label,
    required this.language,
    this.format,
    this.uri,
    this.isEmbedded = false,
    this.isSelected = false,
    required this.classification,
  });

  final String id;
  final String label;
  final String language;
  final String? format;
  final Uri? uri;
  final bool isEmbedded;
  final bool isSelected;
  final SubtitleClassification classification;

  static SubtitleClassification classify(String lang) {
    final lower = lang.toLowerCase().trim();
    if (lower == 'vi' || lower == 'vietnamese' || lower == 'vie') {
      return SubtitleClassification.vietnamese;
    }
    if (lower == 'en' ||
        lower == 'english' ||
        lower == 'ja' ||
        lower == 'japanese' ||
        lower == 'zh' ||
        lower == 'chinese') {
      return SubtitleClassification.sourceLanguage;
    }
    return SubtitleClassification.unknownOther;
  }

  PlayerSubtitleTrack copyWith({bool? isSelected}) {
    return PlayerSubtitleTrack(
      id: id,
      label: label,
      language: language,
      format: format,
      uri: uri,
      isEmbedded: isEmbedded,
      isSelected: isSelected ?? this.isSelected,
      classification: classification,
    );
  }
}

class MediaTrackSet {
  const MediaTrackSet({
    this.videoTracks = const [],
    this.audioTracks = const [],
    this.subtitleTracks = const [],
  });

  final List<VideoTrack> videoTracks;
  final List<AudioTrack> audioTracks;
  final List<PlayerSubtitleTrack> subtitleTracks;

  static const empty = MediaTrackSet();
}

```

## lib/features/player/domain/entities/migration_state.dart
```dart:lib/features/player/domain/entities/migration_state.dart
enum MigrationStatus {
  embedded,
  validatingCandidate,
  preparingNative,
  nativeReady,
  switchedToNative,
  nativeFailedReverted,
}

class NativeMigrationResult {
  const NativeMigrationResult({
    required this.status,
    required this.attemptedCandidateUri,
    this.capturedPosition = Duration.zero,
    this.prepareDuration = Duration.zero,
    this.failureReason,
  });

  final MigrationStatus status;
  final Uri attemptedCandidateUri;
  final Duration capturedPosition;
  final Duration prepareDuration;
  final String? failureReason;

  bool get isSuccess =>
      status == MigrationStatus.switchedToNative ||
      status == MigrationStatus.nativeReady;
}

```

## lib/features/player/domain/entities/player_state.dart
```dart:lib/features/player/domain/entities/player_state.dart
enum PlayerStatus {
  idle,
  initializing,
  ready,
  playing,
  paused,
  buffering,
  seeking,
  ended,
  error,
}

sealed class PlayerError implements Exception {
  const PlayerError(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() =>
      '$runtimeType: $message${cause != null ? ' ($cause)' : ''}';
}

final class PlaybackInitializationException extends PlayerError {
  const PlaybackInitializationException(super.message, [super.cause]);
}

final class MediaFormatUnsupportedException extends PlayerError {
  const MediaFormatUnsupportedException(super.message, [super.cause]);
}

final class NetworkStreamException extends PlayerError {
  const NetworkStreamException(super.message, [super.cause]);
}

final class NativePlayerBackendException extends PlayerError {
  const NativePlayerBackendException(super.message, [super.cause]);
}

```

## lib/features/player/domain/playback_contract.dart
```dart:lib/features/player/domain/playback_contract.dart
import '../../source_resolver/domain/entities/resolved_source.dart';

abstract interface class PlaybackGateway {
  Future<void> open(ResolvedSource source);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Stream<Duration> get position;
  Stream<Duration> get buffered;
}

```

## lib/features/player/domain/services/media_session.dart
```dart:lib/features/player/domain/services/media_session.dart
import '../../../source_resolver/domain/entities/resolved_source.dart';
import '../entities/media_session_snapshot.dart';
import '../entities/media_track.dart';

abstract interface class MediaSession {
  MediaSessionSnapshot get currentSnapshot;
  Stream<MediaSessionSnapshot> get snapshotStream;

  Future<void> open(ResolvedSource source);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setPlaybackRate(double rate);
  Future<void> setVolume(double volume);
  Future<void> selectVideoTrack(VideoTrack track);
  Future<void> selectAudioTrack(AudioTrack track);
  Future<void> selectSubtitleTrack(PlayerSubtitleTrack? track);
  Future<void> close();
}

```

## lib/features/player/presentation/embedded_player_view.dart
```dart:lib/features/player/presentation/embedded_player_view.dart
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
          if (/\.m3u8|\\.mpd|\\.mp4|\\.webm/i.test(value)) {
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

```

## lib/features/player/presentation/media_session_controller.dart
```dart:lib/features/player/presentation/media_session_controller.dart
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/network/dio_provider.dart';
import '../../pipeline/data/dubbing_player_service.dart';
import '../../pipeline/presentation/ai_scheduler_controller.dart';
import '../../source_resolver/data/candidate_verifier.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import '../data/migration_controller.dart';
import '../data/native_media_session.dart';
import '../domain/entities/embedded_playback_snapshot.dart';
import '../domain/entities/media_session_snapshot.dart';
import '../domain/entities/media_track.dart';

final nativeMediaSessionProvider = Provider<NativeMediaSession>((ref) {
  final session = NativeMediaSession();
  ref.onDispose(() => unawaited(session.close()));
  return session;
});

final migrationControllerProvider = Provider<NativeMigrationController>((ref) {
  final session = ref.watch(nativeMediaSessionProvider);
  final dio = ref.watch(dioProvider);
  final verifier = CandidateVerifier(dio);
  final diagnostics = ref.watch(diagnosticsServiceProvider);

  final controller = NativeMigrationController(session, verifier, diagnostics);
  ref.onDispose(controller.dispose);
  return controller;
});

final dubbingPlayerServiceProvider = Provider<DubbingPlayerService>((ref) {
  final repo = ref.watch(dubbingRepositoryProvider);
  final service = DubbingPlayerService(repo);
  ref.onDispose(service.dispose);
  return service;
});

final mediaSessionControllerProvider =
    NotifierProvider<MediaSessionController, MediaSessionSnapshot>(
      MediaSessionController.new,
    );

class MediaSessionController extends Notifier<MediaSessionSnapshot> {
  Timer? _fadeTimer;

  // Sử dụng getter để truy cập các provider ổn định, tránh rủi ro late init trong suốt vòng đời của phương thức build()
  NativeMediaSession get _session => ref.read(nativeMediaSessionProvider);
  NativeMigrationController get _migration => ref.read(migrationControllerProvider);

  @override
  MediaSessionSnapshot build() {
    final session = ref.watch(nativeMediaSessionProvider);
    final dubbing = ref.watch(dubbingPlayerServiceProvider);

    final sub = session.snapshotStream.listen((snapshot) {
      state = snapshot;
      dubbing.syncWithPlayback(snapshot.position, snapshot.isPlaying);
    });

    final duckSub = dubbing.duckingStream.listen((shouldDuck) {
      _fadeVolume(shouldDuck ? 20.0 : 100.0);
    });

    ref.onDispose(() {
      sub.cancel();
      duckSub.cancel();
      _fadeTimer?.cancel();
    });

    return MediaSessionSnapshot.idle;
  }

  void _fadeVolume(double targetVolume) {
    _fadeTimer?.cancel();
    final startVolume = state.volume;
    const steps = 10;
    const duration = Duration(milliseconds: 200);
    final stepDuration = Duration(milliseconds: duration.inMilliseconds ~/ steps);
    final volumeDelta = (targetVolume - startVolume) / steps;

    int currentStep = 0;
    _fadeTimer = Timer.periodic(stepDuration, (timer) {
      currentStep++;
      final nextVolume = startVolume + (volumeDelta * currentStep);
      _session.setVolume(nextVolume.clamp(0.0, 100.0));
      if (currentStep >= steps) timer.cancel();
    });
  }

  Future<void> openSource(ResolvedSource source) => _session.open(source);
  Future<void> play() => _session.play();
  Future<void> pause() => _session.pause();
  Future<void> seek(Duration position) => _session.seek(position);
  Future<void> setPlaybackRate(double rate) => _session.setPlaybackRate(rate);

  Future<void> selectVideoTrack(VideoTrack track) => _session.selectVideoTrack(track);
  Future<void> selectAudioTrack(AudioTrack track) => _session.selectAudioTrack(track);
  Future<void> selectSubtitleTrack(PlayerSubtitleTrack? track) => _session.selectSubtitleTrack(track);

  /// Đã khớp chữ ký với UI trong EmbeddedPlayerView (Critical #2)
  Future<bool> attemptMigrationToNative({
    required ResolvedSource source,
    required EmbeddedPlaybackSnapshot snapshot,
  }) async {
    final result = await _migration.attemptMigration(
      source: source,
      snapshot: snapshot,
    );
    return result.isSuccess;
  }

  Future<void> updateNativeAudioAnchor({
    required Duration position,
    required bool isPlaying,
    required double playbackRate,
    required int timelineEpoch,
    required String playbackSessionId,
    required int seekGeneration,
  }) async {
    const channel = MethodChannel('local_ai_video_translator/native_resolver');
    final anchorMonotonicUs = await channel.invokeMethod<int>('getMonotonicUs') ??
        DateTime.now().microsecondsSinceEpoch;

    await channel.invokeMethod('updateAudioAnchor', {
      'mediaPositionUs': position.inMicroseconds,
      'anchorMonotonicUs': anchorMonotonicUs,
      'playbackRate': playbackRate,
      'isPlaying': isPlaying,
      'isBuffering': false,
      'timelineEpoch': timelineEpoch,
      'playbackSessionId': playbackSessionId,
      'seekGeneration': seekGeneration,
    });
  }
}

```

## lib/features/player/presentation/native_player_view.dart
```dart:lib/features/player/presentation/native_player_view.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/diagnostics/presentation/diagnostic_log_overlay.dart';
import '../../pipeline/presentation/ai_scheduler_controller.dart';
import '../../pipeline/presentation/dubbing_controller.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import '../domain/entities/media_session_snapshot.dart';
import '../domain/entities/media_track.dart';
import '../domain/entities/player_state.dart';
import 'media_session_controller.dart';
import 'subtitle_overlay.dart';

class NativePlayerView extends ConsumerStatefulWidget {
  const NativePlayerView({required this.source, super.key});
  final ResolvedSource source;

  @override
  ConsumerState<NativePlayerView> createState() => _NativePlayerViewState();
}

class _NativePlayerViewState extends ConsumerState<NativePlayerView> {
  VideoController? _videoController;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctrl = ref.read(mediaSessionControllerProvider.notifier);
      await ctrl.openSource(widget.source);

      final session = ref.read(nativeMediaSessionProvider);
      final p = session.player;

      if (p != null && mounted) {
        final controller = VideoController(p);
        if (mounted) {
          setState(() {
            _videoController = controller;
          });
        }
      }

      ref.read(aiSchedulerProvider.notifier).initializeForSource(widget.source);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_videoController == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFF7C5CFC)),
        ),
      );
    }

    final aiState = ref.watch(aiSchedulerProvider);
    final sessionSnapshot = ref.watch(mediaSessionControllerProvider);
    final player = ref.read(nativeMediaSessionProvider).player;

    ref.listen<AiSchedulerState>(aiSchedulerProvider, (previous, next) {
      if (player == null) return;

      if (next.isBufferingForAi && player.state.playing) {
        ref.read(mediaSessionControllerProvider.notifier).pause();
      } else if (!next.isBufferingForAi && previous?.isBufferingForAi == true) {
        ref.read(mediaSessionControllerProvider.notifier).play();
      }
    });

    if (sessionSnapshot.status == PlayerStatus.error) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Card(
            color: Colors.red.withValues(alpha: 0.2),
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Native Player Error',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    sessionSnapshot.error?.message ?? 'Unknown playback error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => ref
                        .read(mediaSessionControllerProvider.notifier)
                        .openSource(widget.source),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry Playback'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: Video(controller: _videoController!)),
          SubtitleOverlay(segment: aiState.activeSegment),
          _TrackSelectorOverlay(sessionSnapshot: sessionSnapshot),
          if (kDebugMode)
            Positioned(
              bottom: 80,
              right: 16,
              child: FloatingActionButton.small(
                backgroundColor: Colors.black54,
                child: const Icon(Icons.bug_report, color: Colors.redAccent),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => const DiagnosticLogOverlay(),
                  );
                },
              ),
            ),
          if (aiState.isBufferingForAi)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF7C5CFC)),
                    const SizedBox(height: 16),
                    Text(
                      'Refilling Subtitle Buffer (${aiState.subtitleAhead.inSeconds}s / ${AppConstants.initialSubtitleBuffer.inSeconds}s)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Video paused to guarantee synchronized Vietnamese subtitles',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackSelectorOverlay extends ConsumerWidget {
  const _TrackSelectorOverlay({required this.sessionSnapshot});
  final MediaSessionSnapshot sessionSnapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioTracks = sessionSnapshot.trackSet.audioTracks;
    final subtitleTracks = sessionSnapshot.trackSet.subtitleTracks;

    if (audioTracks.length <= 1 && subtitleTracks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 12,
      right: 12,
      child: Material(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (audioTracks.length > 1) ...[
                PopupMenuButton<AudioTrack>(
                  icon: const Icon(
                    Icons.audiotrack,
                    size: 18,
                    color: Colors.white,
                  ),
                  tooltip: 'Select Audio Track',
                  onSelected: (track) {
                    ref
                        .read(mediaSessionControllerProvider.notifier)
                        .selectAudioTrack(track);
                  },
                  itemBuilder: (context) {
                    return audioTracks.map((a) {
                      return PopupMenuItem<AudioTrack>(
                        value: a,
                        child: Text('${a.label} (${a.language ?? 'unknown'})'),
                      );
                    }).toList();
                  },
                ),
              ],
              IconButton(
                icon: Icon(
                  ref.watch(dubbingControllerProvider)
                      ? Icons.record_voice_over
                      : Icons.voice_over_off,
                  size: 18,
                  color: ref.watch(dubbingControllerProvider)
                      ? const Color(0xFF7C5CFC)
                      : Colors.white,
                ),
                tooltip: 'AI Vietnamese Dubbing',
                onPressed: () => ref
                    .read(dubbingControllerProvider.notifier)
                    .toggleDubbing(),
              ),
              if (subtitleTracks.isNotEmpty) ...[
                PopupMenuButton<PlayerSubtitleTrack?>(
                  icon: const Icon(
                    Icons.subtitles,
                    size: 18,
                    color: Colors.white,
                  ),
                  tooltip: 'Select Subtitle Track',
                  onSelected: (track) {
                    ref
                        .read(mediaSessionControllerProvider.notifier)
                        .selectSubtitleTrack(track);
                  },
                  itemBuilder: (context) {
                    return [
                      const PopupMenuItem<PlayerSubtitleTrack?>(
                        value: null,
                        child: Text('Off / AI Pipeline Default'),
                      ),
                      ...subtitleTracks.map((s) {
                        return PopupMenuItem<PlayerSubtitleTrack?>(
                          value: s,
                          child: Text('${s.label} [${s.classification.name}]'),
                        );
                      }),
                    ];
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

```

## lib/features/player/presentation/player_page.dart
```dart:lib/features/player/presentation/player_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../pipeline/presentation/ai_buffer_panel.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import '../../source_resolver/presentation/source_inspector_page.dart';
import 'embedded_player_view.dart';
import 'native_player_view.dart';

class PlayerPage extends StatelessWidget {
  const PlayerPage({required this.source, super.key});
  final ResolvedSource source;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              source.input.isNotEmpty ? source.input : 'AI Video Stream Player',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${source.kind.name.toUpperCase()} • ${source.playbackMode.name.toUpperCase()}',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, color: Colors.white),
            tooltip: 'Nguồn & Inspector',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SourceInspectorPage(source: source),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            tooltip: 'Cài đặt AI',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: source.playbackMode == PlaybackMode.native
                  ? NativePlayerView(source: source)
                  : EmbeddedPlayerView(source: source),
            ),
            AiBufferPanel(source: source),
          ],
        ),
      ),
    );
  }
}

```

## lib/features/player/presentation/subtitle_overlay.dart
```dart:lib/features/player/presentation/subtitle_overlay.dart
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

```

