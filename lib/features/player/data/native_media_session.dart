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
