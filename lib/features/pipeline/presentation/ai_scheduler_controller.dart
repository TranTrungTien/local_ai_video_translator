import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../audio/data/pcm_audio_extractor.dart';
import '../../audio/data/vad_engine.dart';
import '../../settings/data/model_manager_repository.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import '../../subtitles/data/subtitle_repository_impl.dart';
import '../../subtitles/domain/entities/subtitle_track.dart';
import '../../subtitles/domain/repositories/subtitle_repository.dart';
import '../data/dubbing_repository.dart';
import '../data/local_stt_engine.dart';
import '../data/local_translation_engine.dart';
import '../data/local_tts_engine.dart';
import '../data/performance_monitor.dart';
import '../domain/ai_pipeline.dart';
import '../domain/buffer_policy.dart';
import '../domain/device_capability.dart';
import '../domain/dub_segment.dart';
import '../domain/playback_gate.dart';
import '../domain/timeline_subtitle_buffer.dart';
import '../../player/presentation/media_session_controller.dart';

class _Sentinel {
  const _Sentinel();
}

const _keep = _Sentinel();

class AiSchedulerState {
  const AiSchedulerState({
    required this.playbackPosition,
    required this.subtitleReadyUntil,
    required this.dubReadyUntil,
    required this.workMode,
    required this.activeSourceStrategy,
    required this.activeSessionId,
    this.activeSegment,
    this.isBufferingForAi = false,
    this.playbackRate = 1.0,
    this.errorMessage,
    this.overallProgress = 0.0,
  });

  final Duration playbackPosition;
  final Duration subtitleReadyUntil;
  final Duration dubReadyUntil;
  final AiWorkMode workMode;
  final String activeSourceStrategy;
  final String activeSessionId;
  final TimedTextSegment? activeSegment;
  final bool isBufferingForAi;
  final double playbackRate;
  final double overallProgress;
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
    String? activeSessionId,
    Object? activeSegment = _keep,
    bool? isBufferingForAi,
    double? playbackRate,
    String? errorMessage,
    double? overallProgress,
  }) {
    return AiSchedulerState(
      playbackPosition: playbackPosition ?? this.playbackPosition,
      subtitleReadyUntil: subtitleReadyUntil ?? this.subtitleReadyUntil,
      dubReadyUntil: dubReadyUntil ?? this.dubReadyUntil,
      workMode: workMode ?? this.workMode,
      activeSourceStrategy: activeSourceStrategy ?? this.activeSourceStrategy,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      activeSegment: identical(activeSegment, _keep)
          ? this.activeSegment
          : activeSegment as TimedTextSegment?,
      isBufferingForAi: isBufferingForAi ?? this.isBufferingForAi,
      playbackRate: playbackRate ?? this.playbackRate,
      errorMessage: errorMessage ?? (identical(errorMessage, _keep) ? this.errorMessage : null),
      overallProgress: overallProgress ?? this.overallProgress,
    );
  }
}

class AiSchedulerController extends StateNotifier<AiSchedulerState> {
  AiSchedulerController({
    required Ref ref,
    required SubtitleRepository subtitleRepository,
    required SpeechToTextEngine sttEngine,
    required TranslationEngine translationEngine,
    required TextToSpeechEngine ttsEngine,
    required PcmAudioExtractor audioExtractor,
    required VoiceActivityDetector vadEngine,
    required DubbingRepository dubbingRepository,
    required DiagnosticsService diagnostics,
    DeviceCapabilityProfile? deviceProfile,
  }) : _ref = ref,
       _subtitleRepository = subtitleRepository,
       _sttEngine = sttEngine,
       _translationEngine = translationEngine,
       _ttsEngine = ttsEngine,
       _audioExtractor = audioExtractor,
       _vadEngine = vadEngine,
       _dubbingRepository = dubbingRepository,
       _diagnostics = diagnostics,
       _deviceProfile = deviceProfile ?? DeviceCapabilityProfile.defaultProfile,
       super(
         const AiSchedulerState(
           playbackPosition: Duration.zero,
           subtitleReadyUntil: Duration.zero,
           dubReadyUntil: Duration.zero,
           workMode: AiWorkMode.starting,
           activeSourceStrategy: 'Initializing...',
           activeSessionId: 'none',
           overallProgress: 0.0,
         ),
       );

  final SubtitleRepository _subtitleRepository;
  final Ref _ref;
  final SpeechToTextEngine _sttEngine;
  final TranslationEngine _translationEngine;
  final TextToSpeechEngine _ttsEngine;
  final PcmAudioExtractor _audioExtractor;
  final VoiceActivityDetector _vadEngine;
  final DubbingRepository _dubbingRepository;
  final DiagnosticsService _diagnostics;
  final DeviceCapabilityProfile _deviceProfile;

  final TimelineSubtitleBuffer _timelineBuffer = TimelineSubtitleBuffer();
  final _policy = const AiBufferPolicy();
  final _playbackGate = const PlaybackGate();

  int _generation = 0;
  CancellationToken? _activeToken;
  ResolvedSource? activeSource;

  SubtitleTrack? _activeTrack;
  bool _isTranslatingCues = false;

  int _consecutiveFailures = 0;
  bool _gatePaused = false;

  int get generation => _generation;

  String get activeSessionId => _activeToken?.hashCode.toString() ?? 'none';

  void attachPlayback({required VoidCallback pause, required VoidCallback play}) {
    // Currently relying on MediaSessionController to avoid circular dependency
    // and ensure single source of truth for playback state.
  }

  void stop() {
    _activeToken?.cancel();
    _generation++;
    _timelineBuffer.clear();
    _dubbingRepository.clear();
    _activeTrack = null;
    _consecutiveFailures = 0;
    _gatePaused = false;
    state = state.copyWith(
      errorMessage: null,
      workMode: AiWorkMode.starting,
      activeSegment: null,
      subtitleReadyUntil: Duration.zero,
      dubReadyUntil: Duration.zero,
    );
  }

  Future<void> initializeForSource(ResolvedSource source) async {
    final gen = _beginNewSession();
    activeSource = source;
    _timelineBuffer.clear();
    _dubbingRepository.clear();
    state = state.copyWith(errorMessage: null);

    _diagnostics.log(
      'AIScheduler',
      'Initializing for source: ${source.kind.name}',
    );

    try {
      if (source.manualSubtitlePath != null) {
        state = state.copyWith(
          activeSourceStrategy: 'Using Manual Subtitle File',
        );
        final manualTrack = SubtitleTrack(
          id: 'manual_sub',
          language: 'unknown',
          title: 'Manual Subtitle',
          uri: Uri.file(source.manualSubtitlePath!),
          format: source.manualSubtitlePath!.toLowerCase().endsWith('.vtt')
              ? SubtitleFormat.webvtt
              : SubtitleFormat.srt,
          isTargetLanguage: false,
        );
        await _loadSubtitleTrack(manualTrack, gen, translate: true);
        return;
      }

      final tracks = await _subtitleRepository.findSubtitleTracks(source);
      if (_isStale(gen)) return;

      final viTrack = tracks
          .where((t) => t.isTargetLanguage || t.language.toLowerCase() == 'vi')
          .firstOrNull;

      if (viTrack != null) {
        state = state.copyWith(
          activeSourceStrategy: 'Using Existing Vietnamese Subtitles',
        );
        _isTranslatingCues = false;
        await _loadSubtitleTrack(viTrack, gen, translate: false);
        return;
      }

      final foreignTrack = tracks.firstOrNull;
      if (foreignTrack != null) {
        state = state.copyWith(
          activeSourceStrategy:
              'Translating ${foreignTrack.language.toUpperCase()} Subtitles',
        );
        _isTranslatingCues = true;
        await _loadSubtitleTrack(foreignTrack, gen, translate: true);
        return;
      }

      // Check models before starting AI pipeline
      await _checkModelsReady();

      state = state.copyWith(
        activeSourceStrategy: 'AI Pipeline (VAD -> STT -> Translation)',
      );
      await _runAudioSttPipeline(source, gen, startAt: state.playbackPosition);
    } on OperationCancelledException {
      _diagnostics.log('AIScheduler', 'Pipeline cancelled for gen $gen');
    } catch (e, st) {
      if (_isStale(gen)) return;

      final errorStr = e.toString().toLowerCase();
      final isModelError = errorStr.contains('missing') ||
                          errorStr.contains('not found') ||
                          e is ModelDownloadException;

      final msg = isModelError
          ? (e is ModelDownloadException ? e.message : 'Lỗi: Thiếu model AI. Vui lòng tải xuống trong Cài đặt.')
          : 'Không thể khởi tạo phụ đề tự động: $e';

      _diagnostics.log(
        'AIScheduler',
        'Init failed: $e\n$st',
        level: LogLevel.error,
      );
      state = state.copyWith(errorMessage: msg, workMode: AiWorkMode.blocked);
    }
  }

  Future<void> _checkModelsReady() async {
    final repo = _ref.read(modelManagerRepositoryProvider);
    final missing = <String>[];

    if (!await repo.isModelDownloaded(LocalSpeechToTextEngine.modelId)) {
      missing.add('STT');
    }
    if (!await repo.isModelDownloaded(LocalTranslationEngine.modelId)) {
      missing.add('Translation');
    }
    // TTS model is temporarily not required as dubbing is disabled.
    /*
    if (!await repo.isModelDownloaded(LocalTextToSpeechEngine.modelId)) {
      missing.add('TTS');
    }
    */
    if (!await repo.isModelDownloaded(LocalVadEngine.modelId)) {
      missing.add('VAD');
    }

    if (missing.isNotEmpty) {
      throw ModelDownloadException(
        'Thiếu model AI: ${missing.join(", ")}. Vui lòng tải xuống trong Cài đặt.',
      );
    }
  }

  Future<void> _loadSubtitleTrack(
    SubtitleTrack track,
    int gen, {
    required bool translate,
  }) async {
    _activeTrack = track;
    final raw = await _subtitleRepository.fetchSubtitleSegments(track);
    if (_isStale(gen)) return;

    final startIndex = raw.indexWhere((s) => s.end >= state.playbackPosition);
    final startAt = startIndex < 0 ? 0 : startIndex;

    for (var i = startAt; i < raw.length; i += 20) {
      if (_isStale(gen)) return;
      await _waitUntilBufferNeeded(gen);
      if (_isStale(gen)) return;

      final batch = raw.skip(i).take(20).toList();
      final processedBatch = translate
          ? await _translationEngine.translate(
              batch,
              targetLanguage: AppConstants.targetLanguage,
              cancellationToken: _activeToken,
            )
          : batch;

      if (_isStale(gen)) return;
      _timelineBuffer.addSegments(processedBatch);

      final nextStart = i + 20 < raw.length ? raw[i + 20].start : const Duration(days: 1);
      _timelineBuffer.markSubtitleDocumentComplete(nextStart);

      unawaited(_synthesizeBatch(processedBatch, gen, _activeToken!));
      _updateBufferState();
    }
  }

  Future<void> _synthesizeBatch(
    List<TimedTextSegment> segments,
    int gen,
    CancellationToken token,
  ) async {
    for (final seg in segments) {
      if (_isStale(gen) || token.isCancelled) return;
      final targetDuration = seg.end - seg.start;
      try {
        final audio = await _ttsEngine.synthesizeWithCancellation(
          seg.text,
          targetDuration: targetDuration,
          cancellationToken: token,
        );
        if (_isStale(gen) || token.isCancelled) return;

        final dubSeg = DubSegment(
          id: 'dub_${seg.start.inMilliseconds}',
          startPts: seg.start,
          endPts: seg.end,
          sourceText: '',
          translatedText: seg.text,
          generatedAudio: audio,
          generatedDuration: targetDuration,
          targetDuration: targetDuration,
          voiceId: 'vi_female',
          modelVersion: '1.0',
        );

        _dubbingRepository.addSegment(dubSeg);
        _updateBufferState();
      } catch (e) {
        _diagnostics.log('AIScheduler', 'TTS failed for segment: $e');
      }
    }
  }

  Future<void> _runAudioSttPipeline(
    ResolvedSource source,
    int gen, {
    required Duration startAt,
  }) async {
    final token = _activeToken!;
    final audioStream = _audioExtractor.extractPcmStream(
      source,
      startPosition: startAt,
      playbackSessionId: activeSessionId,
      seekGeneration: gen,
      cancellationToken: token,
    );

    await for (final speech in _vadEngine.detectSpeech(
      audioStream,
      onProgress: (pts, activeSpeechStart) {
        if (_isStale(gen)) return;
        _timelineBuffer.reportProgress(
          pts,
          activeSpeechStart: activeSpeechStart,
        );
        _updateBufferState();
      },
    )) {
      token.throwIfCancelled();
      if (_isStale(gen)) return;

      if (speech.chunks.isNotEmpty) {
        final firstChunk = speech.chunks.first;
        if (firstChunk.playbackSessionId != activeSessionId ||
            firstChunk.seekGeneration != gen) {
          _diagnostics.log(
            'AIScheduler',
            'Discarding stale VAD segment from old session',
          );
          continue;
        }
      }

      await _waitUntilBufferNeeded(gen);
      if (_isStale(gen)) return;

      _timelineBuffer.registerPendingRange(speech.start, speech.end);
      _updateBufferState();

      try {
        final sttSegments = await _sttEngine.transcribeWithCancellation(
          Stream.fromIterable(speech.chunks),
          cancellationToken: token,
        );

        final translated = sttSegments.isEmpty
            ? const <TimedTextSegment>[]
            : await _translationEngine.translate(
                sttSegments,
                targetLanguage: AppConstants.targetLanguage,
                cancellationToken: token,
              );

        _timelineBuffer.addSegments(translated, metadata: speech.start);
        // Dubbing is temporarily disabled as per request, only subtitles are processed.
        // unawaited(_synthesizeBatch(translated, gen, token));
        _consecutiveFailures = 0;

        final duration = activeSource?.capability.duration;
        if (duration != null && duration.inMilliseconds > 0) {
          final progress = speech.end.inMilliseconds / duration.inMilliseconds;
          state = state.copyWith(overallProgress: progress.clamp(0.0, 1.0));
        }
      } on OperationCancelledException {
        rethrow;
      } catch (e, st) {
        _timelineBuffer.failPendingRange(speech.start);
        _diagnostics.log('AIScheduler', 'Segment failed: $e',
            level: LogLevel.error, details: st.toString());
        if (++_consecutiveFailures >= 3) {
          state = state.copyWith(
              errorMessage: 'AI Pipeline failed multiple times: $e',
              workMode: AiWorkMode.blocked);
          return;
        }
      }
      _updateBufferState();
    }
  }

  Future<void> _waitUntilBufferNeeded(int gen) async {
    while (!_isStale(gen) &&
        (_timelineBuffer.subtitleReadyUntil - state.playbackPosition) >
            const Duration(minutes: 2)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  int _beginNewSession() {
    _activeToken?.cancel();
    _activeToken = CancellationToken();
    _generation++;
    final newSessionId = _activeToken.hashCode.toString();
    state = state.copyWith(activeSessionId: newSessionId);
    return _generation;
  }

  bool _isStale(int gen) => !mounted || gen != _generation;

  void updatePlaybackPosition(Duration pts) {
    _timelineBuffer.pruneObsolete(pts);
    _dubbingRepository.prune(pts);

    final activeSeg = _timelineBuffer.segmentAt(pts);
    final dubSeg = _dubbingRepository.getSegmentAt(pts);
    if (dubSeg != null) {
      _dubbingRepository.markAsActive(dubSeg.id);
    }

    final readyUntil = _timelineBuffer.subtitleReadyUntil;
    final dubReadyUntil = _dubbingRepository.dubReadyUntil;

    final snapshot = AiBufferSnapshot(
      playbackPosition: pts,
      subtitleReadyUntil: readyUntil,
      dubReadyUntil: dubReadyUntil,
    );

    final decision = _playbackGate.evaluate(
      snapshot: snapshot,
      playbackRate: state.playbackRate,
      isUserPaused: false,
    );

    final ahead = readyUntil - pts;
    final resumeAt = _policy.dynamicStartupThreshold(
      deviceProfile: _deviceProfile,
      sttRtf: PerformanceMonitor.instance.current.sttRtf,
      translationThroughput: 100,
      playbackRate: state.playbackRate,
    );

    if (!_gatePaused && ahead <= Duration.zero) {
      _gatePaused = true;
      unawaited(_ref.read(mediaSessionControllerProvider.notifier).pause());
    } else if (_gatePaused && ahead >= resumeAt) {
      _gatePaused = false;
      unawaited(_ref.read(mediaSessionControllerProvider.notifier).play());
    }

    state = state.copyWith(
      playbackPosition: pts,
      subtitleReadyUntil: readyUntil,
      dubReadyUntil: dubReadyUntil,
      workMode: decision.workMode,
      activeSegment: activeSeg,
      isBufferingForAi: _gatePaused,
    );
  }

  void handleSeek(Duration newPts) {
    final gen = _beginNewSession();
    _timelineBuffer.flushObsolete(newPts);
    _dubbingRepository.clear();
    _consecutiveFailures = 0;
    _gatePaused = false;
    updatePlaybackPosition(newPts);

    final source = activeSource;
    if (source != null) {
      if (state.activeSourceStrategy.contains('AI Pipeline')) {
        unawaited(_runAudioSttPipeline(source, gen, startAt: newPts));
      } else if (_activeTrack != null) {
        unawaited(_loadSubtitleTrack(_activeTrack!, gen,
            translate: _isTranslatingCues));
      }
    }
  }

  void updatePlaybackRate(double rate) {
    state = state.copyWith(playbackRate: rate);
    _updateBufferState();
  }

  void _updateBufferState() {
    final readyUntil = _timelineBuffer.subtitleReadyUntil;
    final dubReadyUntil = _dubbingRepository.dubReadyUntil;

    final snapshot = AiBufferSnapshot(
      playbackPosition: state.playbackPosition,
      subtitleReadyUntil: readyUntil,
      dubReadyUntil: dubReadyUntil,
    );

    final canStart = _policy.canStart(
      snapshot,
      deviceProfile: _deviceProfile,
      playbackRate: state.playbackRate,
    );

    final mode = state.errorMessage != null
        ? AiWorkMode.blocked
        : _policy.modeFor(snapshot, playbackRate: state.playbackRate);

    state = state.copyWith(
      subtitleReadyUntil: readyUntil,
      dubReadyUntil: dubReadyUntil,
      workMode: mode,
      isBufferingForAi:
          !canStart &&
          (state.playbackPosition == Duration.zero || state.isBufferingForAi),
    );
  }

  @override
  void dispose() {
    _activeToken?.cancel();
    _generation++;
    super.dispose();
  }
}

// Providers
final subtitleRepositoryProvider = Provider<SubtitleRepository>((ref) {
  return SubtitleRepositoryImpl(ref.watch(dioProvider));
});

final sttEngineProvider = Provider<SpeechToTextEngine>((ref) {
  final engine = LocalSpeechToTextEngine(
    ref.watch(modelManagerRepositoryProvider),
    ref.watch(diagnosticsServiceProvider),
  );

  ref.onDispose(() {
    unawaited(engine.dispose());
  });

  return engine;
});

final translationEngineProvider = Provider<TranslationEngine>((ref) {
  final engine = LocalTranslationEngine(
    ref.watch(modelManagerRepositoryProvider),
    ref.watch(diagnosticsServiceProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

final ttsEngineProvider = Provider<TextToSpeechEngine>((ref) {
  final engine = LocalTextToSpeechEngine(
    ref.watch(modelManagerRepositoryProvider),
    ref.watch(diagnosticsServiceProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

final pcmAudioExtractorProvider = Provider<PcmAudioExtractor>((ref) {
  if (Platform.isAndroid) {
    return NativePcmAudioExtractor(ref.watch(diagnosticsServiceProvider));
  }
  return const DefaultPcmAudioExtractor();
});

final vadEngineProvider = Provider<VoiceActivityDetector>((ref) {
  final engine = LocalVadEngine(
    ref.watch(modelManagerRepositoryProvider),
    ref.watch(diagnosticsServiceProvider),
  );
  ref.onDispose(engine.dispose);
  return engine;
});

final dubbingRepositoryProvider = Provider<DubbingRepository>((ref) {
  return DubbingRepository();
});

final activeDubIdProvider = StreamProvider.autoDispose<String?>((ref) {
  return ref.watch(dubbingRepositoryProvider).activeIdStream;
});

final aiSchedulerProvider =
    StateNotifierProvider.autoDispose<AiSchedulerController, AiSchedulerState>((
      ref,
    ) {
      return AiSchedulerController(
        ref: ref,
        subtitleRepository: ref.watch(subtitleRepositoryProvider),
        sttEngine: ref.watch(sttEngineProvider),
        translationEngine: ref.watch(translationEngineProvider),
        ttsEngine: ref.watch(ttsEngineProvider),
        audioExtractor: ref.watch(pcmAudioExtractorProvider),
        vadEngine: ref.watch(vadEngineProvider),
        dubbingRepository: ref.watch(dubbingRepositoryProvider),
        diagnostics: ref.watch(diagnosticsServiceProvider),
      );
    });
