import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/network/dio_provider.dart';
import '../../audio/data/pcm_audio_extractor.dart';
import '../../audio/data/vad_engine.dart';
import '../../settings/data/model_manager_repository.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import '../../subtitles/data/subtitle_repository_impl.dart';
import '../data/local_stt_engine.dart';
import '../data/local_translation_engine.dart';
import '../data/local_tts_engine.dart';
import '../data/task_priority_queue.dart';
import '../domain/ai_pipeline.dart';
import '../domain/buffer_policy.dart';
import '../domain/device_capability.dart';
import '../domain/playback_gate.dart';
import '../domain/timeline_subtitle_buffer.dart';

class AiSchedulerState {
  const AiSchedulerState({
    required this.playbackPosition,
    required this.subtitleReadyUntil,
    required this.dubReadyUntil,
    required this.workMode,
    required this.activeSourceStrategy,
    this.activeSegment,
    this.isBufferingForAi = false,
    this.playbackRate = 1.0,
    this.errorMessage,
  });

  final Duration playbackPosition;
  final Duration subtitleReadyUntil;
  final Duration dubReadyUntil;
  final AiWorkMode workMode;
  final String activeSourceStrategy;
  final TimedTextSegment? activeSegment;
  final bool isBufferingForAi;
  final double playbackRate;
  final String? errorMessage;

  Duration get subtitleAhead => subtitleReadyUntil - playbackPosition;

  AiBufferSnapshot get snapshot => AiBufferSnapshot(
    playbackPosition: playbackPosition,
    subtitleReadyUntil: subtitleReadyUntil,
    dubReadyUntil: dubReadyUntil,
  );

  AiSchedulerState copyWith({
    Duration? playbackPosition,
    Duration? subtitleReadyUntil,
    Duration? dubReadyUntil,
    AiWorkMode? workMode,
    String? activeSourceStrategy,
    TimedTextSegment? activeSegment,
    bool? isBufferingForAi,
    double? playbackRate,
    String? errorMessage,
  }) {
    return AiSchedulerState(
      playbackPosition: playbackPosition ?? this.playbackPosition,
      subtitleReadyUntil: subtitleReadyUntil ?? this.subtitleReadyUntil,
      dubReadyUntil: dubReadyUntil ?? this.dubReadyUntil,
      workMode: workMode ?? this.workMode,
      activeSourceStrategy: activeSourceStrategy ?? this.activeSourceStrategy,
      activeSegment: activeSegment ?? this.activeSegment,
      isBufferingForAi: isBufferingForAi ?? this.isBufferingForAi,
      playbackRate: playbackRate ?? this.playbackRate,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AiSchedulerController extends StateNotifier<AiSchedulerState> {
  AiSchedulerController(
    this._subtitleRepository,
    this._sttEngine,
    this._translationEngine,
    LocalTextToSpeechEngine ttsEngine,
    this._audioExtractor,
    this._vadEngine,
    this._diagnostics, [
    DeviceCapabilityProfile? deviceProfile,
  ]) : _deviceProfile = deviceProfile ?? DeviceCapabilityProfile.defaultProfile,
       super(
         const AiSchedulerState(
           playbackPosition: Duration.zero,
           subtitleReadyUntil: Duration.zero,
           dubReadyUntil: Duration.zero,
           workMode: AiWorkMode.normal,
           activeSourceStrategy: 'Initializing Guaranteed Subtitle Buffer...',
         ),
       );

  final SubtitleRepositoryImpl _subtitleRepository;
  final LocalSpeechToTextEngine _sttEngine;
  final LocalTranslationEngine _translationEngine;
  final DefaultPcmAudioExtractor _audioExtractor;
  final LocalVadEngine _vadEngine;
  final DiagnosticsService _diagnostics;
  final DeviceCapabilityProfile _deviceProfile;

  final TimelineSubtitleBuffer _timelineBuffer = TimelineSubtitleBuffer();
  final _policy = const AiBufferPolicy();
  final _playbackGate = const PlaybackGate();
  final TaskPriorityQueue _taskQueue = TaskPriorityQueue();

  ResolvedSource? activeSource;

  Future<void> initializeForSource(ResolvedSource source) async {
    activeSource = source;
    _timelineBuffer.clear();
    _taskQueue.clear();
    _diagnostics.log(
      'AIScheduler',
      'Initializing guaranteed subtitle buffer for source kind=${source.kind.name}',
    );

    try {
      final tracks = await _subtitleRepository.findSubtitleTracks(source);
      final viTrack = tracks
          .where((t) => t.isTargetLanguage || t.language.toLowerCase() == 'vi')
          .firstOrNull;

      if (viTrack != null) {
        state = state.copyWith(
          activeSourceStrategy: 'Existing Vietnamese Subtitle Track',
        );
        final segments = await _subtitleRepository.fetchSubtitleSegments(
          viTrack,
        );
        _timelineBuffer.addSegments(segments);
        _updateBufferState();
        return;
      }

      final foreignTrack = tracks.firstOrNull;
      if (foreignTrack != null) {
        state = state.copyWith(
          activeSourceStrategy:
              'Translating ${foreignTrack.language.toUpperCase()} Subtitles -> Vietnamese',
        );
        final rawSegments = await _subtitleRepository.fetchSubtitleSegments(
          foreignTrack,
        );
        final translated = await _translationEngine.translate(
          rawSegments,
          targetLanguage: AppConstants.targetLanguage,
        );
        _timelineBuffer.addSegments(translated);
        _updateBufferState();
        return;
      }

      state = state.copyWith(
        activeSourceStrategy:
            'Audio -> VAD -> Local STT -> Vietnamese Translation',
      );
      await _runAudioSttPipeline(source);
    } catch (e) {
      state = state.copyWith(
        errorMessage: 'Pipeline initialization failed: $e',
        workMode: AiWorkMode.blocked,
      );
    }
  }

  Future<void> _runAudioSttPipeline(ResolvedSource source) async {
    final audioStream = _audioExtractor.extractPcmStream(source);
    final speechSegments = await _vadEngine.detectSpeech(audioStream).toList();

    for (final speech in speechSegments) {
      final chunkStream = Stream<PcmChunk>.fromIterable(speech.chunks);
      final sttSegments = await _sttEngine.transcribe(chunkStream);
      final translated = await _translationEngine.translate(
        sttSegments,
        targetLanguage: AppConstants.targetLanguage,
      );
      _timelineBuffer.addSegments(translated);
      _updateBufferState();
    }
  }

  void updatePlaybackPosition(Duration pts) {
    final activeSeg = _timelineBuffer.segmentAt(pts);
    final snapshot = AiBufferSnapshot(
      playbackPosition: pts,
      subtitleReadyUntil: _timelineBuffer.subtitleReadyUntil,
      dubReadyUntil: state.dubReadyUntil,
    );

    final decision = _playbackGate.evaluate(
      snapshot: snapshot,
      playbackRate: state.playbackRate,
      isUserPaused: false,
    );

    state = state.copyWith(
      playbackPosition: pts,
      subtitleReadyUntil: _timelineBuffer.subtitleReadyUntil,
      workMode: decision.workMode,
      activeSegment: activeSeg,
      isBufferingForAi: !decision.shouldPlay,
    );

    if (!decision.shouldPlay) {
      _diagnostics.log('AIScheduler', decision.reason, level: LogLevel.warning);
    }
  }

  void handleSeek(Duration newPts) {
    _diagnostics.log(
      'AIScheduler',
      'Seek detected to $newPts. High-priority state transition executing.',
    );
    _taskQueue.cancelObsoleteTasks(newPts);
    _timelineBuffer.flushObsolete(newPts);
    updatePlaybackPosition(newPts);
  }

  void updatePlaybackRate(double rate) {
    state = state.copyWith(playbackRate: rate);
    _updateBufferState();
  }

  void _updateBufferState() {
    final readyUntil = _timelineBuffer.subtitleReadyUntil;
    final snapshot = AiBufferSnapshot(
      playbackPosition: state.playbackPosition,
      subtitleReadyUntil: readyUntil,
      dubReadyUntil: state.dubReadyUntil,
    );

    final canStart = _policy.canStart(
      snapshot,
      deviceProfile: _deviceProfile,
      playbackRate: state.playbackRate,
    );

    final mode = _policy.modeFor(snapshot, playbackRate: state.playbackRate);

    state = state.copyWith(
      subtitleReadyUntil: readyUntil,
      workMode: mode,
      isBufferingForAi: !canStart && state.playbackPosition == Duration.zero,
    );
  }
}

final aiSchedulerProvider =
    StateNotifierProvider<AiSchedulerController, AiSchedulerState>((ref) {
      final modelRepo = ref.watch(modelManagerRepositoryProvider);
      final dio = ref.watch(dioProvider);
      final diagnostics = ref.watch(diagnosticsServiceProvider);

      return AiSchedulerController(
        SubtitleRepositoryImpl(dio),
        LocalSpeechToTextEngine(modelRepo),
        LocalTranslationEngine(modelRepo),
        LocalTextToSpeechEngine(modelRepo),
        const DefaultPcmAudioExtractor(),
        LocalVadEngine(),
        diagnostics,
      );
    });
