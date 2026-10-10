import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/network/dio_provider.dart';
import '../../audio/data/pcm_audio_extractor.dart';
import '../../audio/data/vad_engine.dart';
import '../data/dubbing_repository.dart';
import '../../settings/data/model_manager_repository.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import '../../subtitles/domain/repositories/subtitle_repository.dart';
import '../../subtitles/data/subtitle_repository_impl.dart';
import '../../subtitles/domain/entities/subtitle_track.dart';
import '../../../core/utils/cancellation_token.dart';
import '../data/local_stt_engine.dart';
import '../data/local_translation_engine.dart';
import '../data/local_tts_engine.dart';
import '../domain/ai_pipeline.dart';
import '../domain/dub_segment.dart';
import '../domain/buffer_policy.dart';
import '../domain/device_capability.dart';
import '../domain/playback_gate.dart';
import '../domain/timeline_subtitle_buffer.dart';

/// Sentinel class to distinguish between "not provided" and "provided as null" in copyWith.
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
    Object? activeSegment = _keep,
    bool? isBufferingForAi,
    double? playbackRate,
    Object? errorMessage = _keep,
  }) {
    return AiSchedulerState(
      playbackPosition: playbackPosition ?? this.playbackPosition,
      subtitleReadyUntil: subtitleReadyUntil ?? this.subtitleReadyUntil,
      dubReadyUntil: dubReadyUntil ?? this.dubReadyUntil,
      workMode: workMode ?? this.workMode,
      activeSourceStrategy: activeSourceStrategy ?? this.activeSourceStrategy,
      activeSegment: identical(activeSegment, _keep)
          ? this.activeSegment
          : activeSegment as TimedTextSegment?,
      isBufferingForAi: isBufferingForAi ?? this.isBufferingForAi,
      playbackRate: playbackRate ?? this.playbackRate,
      errorMessage: identical(errorMessage, _keep)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class AiSchedulerController extends StateNotifier<AiSchedulerState> {
  AiSchedulerController({
    required SubtitleRepository subtitleRepository,
    required SpeechToTextEngine sttEngine,
    required TranslationEngine translationEngine,
    required TextToSpeechEngine ttsEngine,
    required PcmAudioExtractor audioExtractor,
    required VoiceActivityDetector vadEngine,
    required DubbingRepository dubbingRepository,
    required DiagnosticsService diagnostics,
    DeviceCapabilityProfile? deviceProfile,
  }) : _subtitleRepository = subtitleRepository,
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
           workMode: AiWorkMode.normal,
           activeSourceStrategy: 'Initializing...',
         ),
       );

  final SubtitleRepository _subtitleRepository;
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
        state = state.copyWith(activeSourceStrategy: 'Using Manual Subtitle File');
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
        await _loadSubtitleTrack(viTrack, gen, translate: false);
        return;
      }

      final foreignTrack = tracks.firstOrNull;
      if (foreignTrack != null) {
        state = state.copyWith(
          activeSourceStrategy: 'Translating ${foreignTrack.language.toUpperCase()} Subtitles',
        );
        await _loadSubtitleTrack(foreignTrack, gen, translate: true);
        return;
      }

      state = state.copyWith(
        activeSourceStrategy: 'AI Pipeline (VAD -> STT -> Translation)',
      );
      await _runAudioSttPipeline(source, gen, startAt: state.playbackPosition);
    } on OperationCancelledException {
      _diagnostics.log('AIScheduler', 'Pipeline cancelled for gen $gen');
    } catch (e, st) {
      if (_isStale(gen)) return;
      _diagnostics.log('AIScheduler', 'Init failed: $e\n$st', level: LogLevel.error);
      state = state.copyWith(
        errorMessage: 'Không thể khởi tạo phụ đề tự động.',
        workMode: AiWorkMode.blocked,
      );
    }
  }

  Future<void> _loadSubtitleTrack(
    SubtitleTrack track,
    int gen, {
    required bool translate,
  }) async {
    final raw = await _subtitleRepository.fetchSubtitleSegments(track);
    if (_isStale(gen)) return;

    final segments = translate
        ? await _translationEngine.translate(raw, targetLanguage: AppConstants.targetLanguage)
        : raw;

    if (_isStale(gen)) return;
    _timelineBuffer.addSegments(segments);

    // Background synthesize for dubbing
    _synthesizeBatch(segments, gen);

    _updateBufferState();
  }

  Future<void> _synthesizeBatch(List<TimedTextSegment> segments, int gen) async {
    for (final seg in segments) {
      if (_isStale(gen)) return;

      final targetDuration = seg.end - seg.start;
      try {
        final audio = await _ttsEngine.synthesize(
          seg.text,
          targetDuration: targetDuration,
        );

        if (_isStale(gen)) return;

        final dubSeg = DubSegment(
          id: 'dub_${seg.start.inMilliseconds}',
          startPts: seg.start,
          endPts: seg.end,
          sourceText: '', // Optional: original text if available
          translatedText: seg.text,
          generatedAudio: audio,
          generatedDuration: targetDuration, // Logic in TTS engine ensures fit
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
    final audioStream = _audioExtractor.extractPcmStream(source, startPosition: startAt);

    await for (final speech in _vadEngine.detectSpeech(audioStream)) {
      token.throwIfCancelled();
      if (_isStale(gen)) return;

      // Back-pressure: Don't process too far ahead of playhead
      await _waitUntilBufferNeeded(gen);
      if (_isStale(gen)) return;

      final chunkStream = Stream<PcmChunk>.fromIterable(speech.chunks);
      final sttSegments = await _sttEngine.transcribe(chunkStream);

      final translated = await _translationEngine.translate(
        sttSegments,
        targetLanguage: AppConstants.targetLanguage,
      );

      if (_isStale(gen)) return;
      _timelineBuffer.addSegments(translated);

      // Synthesize for dubbing
      unawaited(_synthesizeBatch(translated, gen));

      _updateBufferState();
    }
  }

  Future<void> _waitUntilBufferNeeded(int gen) async {
    while (!_isStale(gen) &&
        (_timelineBuffer.subtitleReadyUntil - state.playbackPosition) > const Duration(minutes: 2)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  int _beginNewSession() {
    _activeToken?.cancel();
    _activeToken = CancellationToken();
    return ++_generation;
  }

  bool _isStale(int gen) => !mounted || gen != _generation;

  void updatePlaybackPosition(Duration pts) {
    final activeSeg = _timelineBuffer.segmentAt(pts);
    final snapshot = AiBufferSnapshot(
      playbackPosition: pts,
      subtitleReadyUntil: _timelineBuffer.subtitleReadyUntil,
      dubReadyUntil: _dubbingRepository.dubReadyUntil,
    );

    final decision = _playbackGate.evaluate(
      snapshot: snapshot,
      playbackRate: state.playbackRate,
      isUserPaused: false,
    );

    state = state.copyWith(
      playbackPosition: pts,
      subtitleReadyUntil: _timelineBuffer.subtitleReadyUntil,
      dubReadyUntil: _dubbingRepository.dubReadyUntil,
      workMode: decision.workMode,
      activeSegment: activeSeg,
      isBufferingForAi: !decision.shouldPlay,
    );
  }

  void handleSeek(Duration newPts) {
    _diagnostics.log('AIScheduler', 'Seek to $newPts, re-initializing pipeline');
    final gen = _beginNewSession();
    _timelineBuffer.flushObsolete(newPts);
    _dubbingRepository.clear(); // Simple flush for dubbing on seek
    updatePlaybackPosition(newPts);

    final source = activeSource;
    if (source != null) {
      unawaited(_runAudioSttPipeline(source, gen, startAt: newPts));
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

    final mode = _policy.modeFor(snapshot, playbackRate: state.playbackRate);

    state = state.copyWith(
      subtitleReadyUntil: readyUntil,
      dubReadyUntil: dubReadyUntil,
      workMode: mode,
      isBufferingForAi: !canStart && state.playbackPosition == Duration.zero,
    );
  }

  @override
  void dispose() {
    _activeToken?.cancel();
    _generation++;
    super.dispose();
  }
}

// Separate providers for DIP
final subtitleRepositoryProvider = Provider<SubtitleRepository>((ref) {
  return SubtitleRepositoryImpl(ref.watch(dioProvider));
});

final sttEngineProvider = Provider<SpeechToTextEngine>((ref) {
  return LocalSpeechToTextEngine(ref.watch(modelManagerRepositoryProvider));
});

final translationEngineProvider = Provider<TranslationEngine>((ref) {
  return LocalTranslationEngine(ref.watch(modelManagerRepositoryProvider));
});

final ttsEngineProvider = Provider<TextToSpeechEngine>((ref) {
  return LocalTextToSpeechEngine(ref.watch(modelManagerRepositoryProvider));
});

final pcmAudioExtractorProvider = Provider<PcmAudioExtractor>((ref) {
  if (Platform.isAndroid) {
    return NativePcmAudioExtractor();
  }
  return const DefaultPcmAudioExtractor();
});

final vadEngineProvider = Provider<VoiceActivityDetector>((ref) {
  return LocalVadEngine(ref.watch(modelManagerRepositoryProvider));
});

final dubbingRepositoryProvider = Provider<DubbingRepository>((ref) {
  return DubbingRepository();
});

final aiSchedulerProvider =
    StateNotifierProvider.autoDispose<AiSchedulerController, AiSchedulerState>((ref) {
      return AiSchedulerController(
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

