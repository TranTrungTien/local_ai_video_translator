import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../audio/data/web_audio_extractor.dart';
import '../../audio/data/ffmpeg_audio_extractor.dart';
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
    this.isSrtLogged = false,
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
  final bool isSrtLogged;

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
    Object? errorMessage = _keep,
    double? overallProgress,
    bool? isSrtLogged,
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
      // FIX: dùng sentinel; trước đây mọi copyWith không truyền errorMessage đều xóa lỗi.
      errorMessage: identical(errorMessage, _keep)
          ? this.errorMessage
          : errorMessage as String?,
      overallProgress: overallProgress ?? this.overallProgress,
      isSrtLogged: isSrtLogged ?? this.isSrtLogged,
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
       ) {
    _initTimelineBuffer();
  }

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

  late final TimelineSubtitleBuffer _timelineBuffer;
  final _policy = const AiBufferPolicy();

  int _generation = 0;
  CancellationToken? _activeToken;
  ResolvedSource? activeSource;

  SubtitleTrack? _activeTrack;
  bool _isTranslatingCues = false;

  int _consecutiveFailures = 0;
  bool _gatePaused = false;

  int get generation => _generation;

  String get activeSessionId => _activeToken?.hashCode.toString() ?? 'none';

  void _initTimelineBuffer() {
    _timelineBuffer = TimelineSubtitleBuffer(_diagnostics);
  }

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
    _playbackPosSub?.cancel();
    _playbackPosSub = null;
    state = state.copyWith(
      errorMessage: null,
      workMode: AiWorkMode.starting,
      activeSegment: null,
      subtitleReadyUntil: Duration.zero,
      dubReadyUntil: Duration.zero,
    );
  }

  StreamSubscription? _playbackPosSub;

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

    // Bắt đầu lắng nghe position ngay lập tức cho mọi loại source để Gate và Export hoạt động
    _playbackPosSub?.cancel();
    _playbackPosSub = _ref.read(nativeMediaSessionProvider).snapshotStream.listen((s) {
      updatePlaybackPosition(s.position);
      if (s.isCompleted && !state.isSrtLogged) {
        state = state.copyWith(isSrtLogged: true);
        _logFullSrt();
      }
    });

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
        final manualOk =
            await _loadSubtitleTrack(manualTrack, gen, translate: true);
        if (!manualOk && !_isStale(gen)) {
          state = state.copyWith(
            errorMessage: 'Tệp phụ đề thủ công không có nội dung hợp lệ.',
            workMode: AiWorkMode.blocked,
          );
        }
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
        final viOk = await _loadSubtitleTrack(viTrack, gen, translate: false);
        if (viOk || _isStale(gen)) return;
        // FIX: track 0 cue không được phép làm treo gate -> thử chiến lược kế tiếp.
        _diagnostics.log(
          'AIScheduler',
          'Vietnamese track "${viTrack.title}" has no usable cues, falling back',
          level: LogLevel.warning,
        );
      }

      for (final foreignTrack in tracks.where((t) => t != viTrack)) {
        state = state.copyWith(
          activeSourceStrategy:
              'Translating ${foreignTrack.language.toUpperCase()} Subtitles',
        );
        _isTranslatingCues = true;
        final ok = await _loadSubtitleTrack(foreignTrack, gen, translate: true);
        if (ok || _isStale(gen)) return;
        _diagnostics.log(
          'AIScheduler',
          'Subtitle track "${foreignTrack.title}" has no usable cues, trying next',
          level: LogLevel.warning,
        );
      }
      _isTranslatingCues = false;
      _activeTrack = null;

      if (source.kind == MediaKind.embedded) {
        state = state.copyWith(
          activeSourceStrategy: 'Ready (Enable AI to start)',
        );
        return;
      }

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
    // TTS is optional: subtitles must work even when the dubbing model is absent.
    if (!await repo.isModelDownloaded(LocalVadEngine.modelId)) {
      missing.add('VAD');
    }

    if (missing.isNotEmpty) {
      throw ModelDownloadException(
        'Thiếu model AI: ${missing.join(", ")}. Vui lòng tải xuống trong Cài đặt.',
      );
    }
  }

  /// Trả về true nếu track có cue và đã được nạp (hoặc phiên đã stale);
  /// false nếu track rỗng để caller fallback.
  Future<bool> _loadSubtitleTrack(
    SubtitleTrack track,
    int gen, {
    required bool translate,
  }) async {
    _activeTrack = track;
    final raw = await _subtitleRepository.fetchSubtitleSegments(track);
    if (_isStale(gen)) return true;
    if (raw.isEmpty) {
      _activeTrack = null;
      return false;
    }

    final startIndex = raw.indexWhere((s) => s.end >= state.playbackPosition);
    final startAt = startIndex < 0 ? 0 : startIndex;

    for (var i = startAt; i < raw.length; i += 20) {
      if (_isStale(gen)) return true;
      await _waitUntilBufferNeeded(gen);
      if (_isStale(gen)) return true;

      final batch = raw.skip(i).take(20).toList();
      final processedBatch = translate
          ? await _translationEngine.translate(
              batch,
              targetLanguage: AppConstants.targetLanguage,
              cancellationToken: _activeToken,
            )
          : batch;

      if (_isStale(gen)) return true;
      _timelineBuffer.addSegments(processedBatch);

      final nextStart = i + 20 < raw.length ? raw[i + 20].start : const Duration(days: 1);
      _timelineBuffer.markSubtitleDocumentComplete(nextStart);

      if (await repoIsTtsReady()) {
        unawaited(_synthesizeBatch(processedBatch, gen, _activeToken!));
      }
      _updateBufferState();
    }
    return true;
  }

  Future<bool> repoIsTtsReady() async {
    return _ref.read(modelManagerRepositoryProvider).isModelDownloaded(
      LocalTextToSpeechEngine.modelId,
    );
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

    final speechSegments = <SpeechSegment>[];
    bool processing = false;

    Future<void> worker() async {
      if (processing) return;
      processing = true;
      try {
        while (speechSegments.isNotEmpty && !_isStale(gen) && !token.isCancelled) {
          final speech = speechSegments.removeAt(0);
          await _processSpeechSegment(speech, gen, token);
        }
      } finally {
        processing = false;
      }
    }

    try {
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
        if (_isStale(gen) || token.isCancelled) break;

        // Giới hạn việc VAD chạy quá xa để tiết kiệm tài nguyên
        await _waitUntilBufferNeeded(gen);
        if (_isStale(gen) || token.isCancelled) break;

        if (speech.chunks.isNotEmpty) {
          final firstChunk = speech.chunks.first;
          if (firstChunk.playbackSessionId != activeSessionId ||
              firstChunk.seekGeneration != gen) {
            continue;
          }
        }

        _timelineBuffer.registerPendingRange(speech.start, speech.end);
        _updateBufferState();

        speechSegments.add(speech);
        unawaited(worker());
      }
    } on OperationCancelledException {
      rethrow;
    } catch (e, st) {
      _diagnostics.log('AIScheduler', 'VAD Pipeline Error: $e',
          level: LogLevel.error, details: st.toString());
    }
  }

  Future<void> _processSpeechSegment(
    SpeechSegment speech,
    int gen,
    CancellationToken token,
  ) async {
    if (_isStale(gen) || token.isCancelled) return;

    try {
      final sttStartTime = DateTime.now();
      final sttSegments = await _sttEngine.transcribeWithCancellation(
        Stream.fromIterable(speech.chunks),
        cancellationToken: token,
      );
      final sttDuration = DateTime.now().difference(sttStartTime);

      final audioDurationMs =
          speech.end.inMilliseconds - speech.start.inMilliseconds;
      _diagnostics.log('AIScheduler',
          'STT finished in ${sttDuration.inMilliseconds}ms for ${audioDurationMs}ms audio');

      if (sttSegments.isNotEmpty) {
        _diagnostics.log('AIScheduler',
            'STT Result: "${sttSegments.map((s) => s.text).join(" ")}"');
      }

      final splitStt = _splitIntoSentences(sttSegments);

      final translated = splitStt.isEmpty
          ? const <TimedTextSegment>[]
          : await _translationEngine.translate(
              splitStt,
              targetLanguage: AppConstants.targetLanguage,
              cancellationToken: token,
            );

      if (translated.isNotEmpty) {
        _diagnostics.log('AIScheduler',
            'Translation Result: "${translated.map((s) => s.text).join(" ")}"');
      }

      _timelineBuffer.addSegments(translated, metadata: speech.start);

      if (await repoIsTtsReady()) {
        unawaited(_synthesizeBatch(translated, gen, token));
      }

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
      _diagnostics.log('AIScheduler', 'Segment processing failed: $e',
          level: LogLevel.error, details: st.toString());

      if (++_consecutiveFailures >= 3) {
        state = state.copyWith(
          errorMessage: 'AI Pipeline failed multiple times: $e',
          workMode: AiWorkMode.blocked,
        );
      }
    }
    _updateBufferState();
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

    _diagnostics.log('AIScheduler', 'New session started: $newSessionId.');

    state = state.copyWith(
      activeSessionId: newSessionId,
      isSrtLogged: false,
      errorMessage: null,
      activeSegment: null,
    );
    return _generation;
  }

  bool _isStale(int gen) => !mounted || gen != _generation;

  String _formatSrtDuration(Duration d) {
    final hh = d.inHours.toString().padLeft(2, '0');
    final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    final ms = (d.inMilliseconds % 1000).toString().padLeft(3, '0');
    return '$hh:$mm:$ss,$ms';
  }

  void _logFullSrt() {
    final allSegments = _timelineBuffer.segments;
    if (allSegments.isEmpty) {
      _diagnostics.log('AIScheduler', 'SRT Export: No segments in buffer to log');
      return;
    }

    // Đảm bảo các segment được sắp xếp theo thời gian
    final segments = List<TimedTextSegment>.from(allSegments)
      ..sort((a, b) => a.start.compareTo(b.start));

    final buffer = StringBuffer();
    for (int i = 0; i < segments.length; i++) {
      final s = segments[i];
      buffer.writeln('${i + 1}');
      buffer.writeln('${_formatSrtDuration(s.start)} --> ${_formatSrtDuration(s.end)}');
      buffer.writeln(s.text);
      buffer.writeln(); // Dòng trống giữa các cue theo chuẩn SRT
    }

    // Log dưới dạng một khối văn bản duy nhất để dễ dàng copy-paste
    _diagnostics.log(
      'AIScheduler',
      '--- BEGIN FULL SRT ---\n${buffer.toString()}--- END FULL SRT ---',
      level: LogLevel.info,
    );

    _diagnostics.log('AIScheduler', 'Đã log toàn bộ file SRT vào diagnostics (${segments.length} segments).');
  }

  void updatePlaybackPosition(Duration pts) {
    // _timelineBuffer.pruneObsolete(pts); // Tắt prune để giữ toàn bộ lịch sử cho việc export
    _dubbingRepository.prune(pts);

    // Trong chế độ Capture (Luồng 3), chúng ta hiển thị segment mới nhất vừa nhận được
    // thay vì dựa trên PTS chính xác của player, vì audio thu từ loa luôn trễ.
    final bool isCaptureMode = activeSource?.kind == MediaKind.embedded;

    final activeSeg = isCaptureMode
        ? (_timelineBuffer.lastProcessedSegment ?? _timelineBuffer.segmentAt(pts))
        : _timelineBuffer.segmentAt(pts);

    // Xóa log spam ở mức DEBUG mỗi khi vị trí phát thay đổi (thường là 16-33ms)
    // Chỉ log khi segment thực sự thay đổi
    if (activeSeg != state.activeSegment && activeSeg != null) {
      if (!isCaptureMode) {
         _diagnostics.log('AIScheduler', 'Active Segment changed: "${activeSeg.text}"', level: LogLevel.debug);
      }
    }

    final dubSeg = _dubbingRepository.getSegmentAt(pts);
    if (dubSeg != null) {
      _dubbingRepository.markAsActive(dubSeg.id);
    }

    state = state.copyWith(
      playbackPosition: pts,
      activeSegment: activeSeg,
    );

    _updateBufferState();
  }

  void handleSeek(Duration newPts) {
    final gen = _beginNewSession();
    // Seek = cơ hội thử lại: xóa lỗi cũ (errorMessage giờ không còn tự bị xóa).
    state = state.copyWith(errorMessage: null);
    _timelineBuffer.handleSeek(newPts);
    _dubbingRepository.clear();
    _consecutiveFailures = 0;
    _gatePaused = false;
    updatePlaybackPosition(newPts);

    final source = activeSource;
    if (source != null) {
      if (state.activeSourceStrategy.contains('AI Pipeline')) {
        unawaited(_guardPipeline(
          gen,
          _runAudioSttPipeline(source, gen, startAt: newPts),
        ));
      } else if (_activeTrack != null) {
        unawaited(_guardPipeline(
          gen,
          _loadSubtitleTrack(_activeTrack!, gen, translate: _isTranslatingCues),
        ));
      }
    }
  }

  /// FIX: pipeline khởi động từ handleSeek chạy unawaited, trước đây lỗi/hủy
  /// không được bắt (unhandled async error, lỗi thật không lên UI).
  Future<void> _guardPipeline(int gen, Future<Object?> run) async {
    try {
      await run;
    } on OperationCancelledException {
      // Bị thay thế bởi seek mới / stop: bình thường.
    } catch (e, st) {
      if (_isStale(gen)) return;
      _diagnostics.log(
        'AIScheduler',
        'Pipeline after seek failed: $e',
        level: LogLevel.error,
        details: st.toString(),
      );
      state = state.copyWith(
        errorMessage: 'Không thể tiếp tục tạo phụ đề: $e',
        workMode: AiWorkMode.blocked,
      );
    }
  }

  void updatePlaybackRate(double rate) {
    state = state.copyWith(playbackRate: rate);
    _updateBufferState();
  }

  Future<void> startAiPipelineForEmbedded() async {
    final source = activeSource;
    if (source == null || source.kind != MediaKind.embedded) return;
    if (state.activeSourceStrategy == 'AI Pipeline (VAD -> STT -> Translation)') {
      return;
    }

    final gen = activeSessionId.hashCode; // Keep current session
    try {
      await _checkModelsReady();

      state = state.copyWith(
        activeSourceStrategy: 'AI Pipeline (VAD -> STT -> Translation)',
      );

      await _runAudioSttPipeline(source, gen, startAt: state.playbackPosition);
    } catch (e) {
      // Re-handle in initializeForSource style if needed,
      // but here we just want to allow manual start.
      state = state.copyWith(
        errorMessage: 'Không thể khởi động AI: $e',
        workMode: AiWorkMode.blocked,
      );
    }
  }

  void _updateBufferState() {
    final readyUntil = _timelineBuffer.subtitleReadyUntil;
    final dubReadyUntil = _dubbingRepository.dubReadyUntil;

    final snapshot = AiBufferSnapshot(
      playbackPosition: state.playbackPosition,
      subtitleReadyUntil: readyUntil,
      dubReadyUntil: dubReadyUntil,
    );

    final ahead = readyUntil - state.playbackPosition;
    final resumeAt = _policy.dynamicStartupThreshold(
      deviceProfile: _deviceProfile,
      sttRtf: PerformanceMonitor.instance.current.sttRtf,
      translationThroughput: 100,
      playbackRate: state.playbackRate,
    );

    final bool isCaptureMode = activeSource?.kind == MediaKind.embedded;

    if (!isCaptureMode && !_gatePaused && ahead <= Duration.zero && state.playbackPosition > Duration.zero) {
      _gatePaused = true;
      _diagnostics.log('AIScheduler', 'Gate: Pausing video (buffer empty)');
      unawaited(_ref.read(mediaSessionControllerProvider.notifier).pause());
    } else if (_gatePaused && (ahead >= resumeAt || isCaptureMode)) {
      _gatePaused = false;
      _diagnostics.log('AIScheduler', 'Gate: Resuming video (buffer ready: ${ahead.inSeconds}s)');
      unawaited(_ref.read(mediaSessionControllerProvider.notifier).play());
    }

    final canStart = _policy.canStart(
      snapshot,
      deviceProfile: _deviceProfile,
      playbackRate: state.playbackRate,
    );

    final mode = state.errorMessage != null
        ? AiWorkMode.blocked
        : _policy.modeFor(snapshot, playbackRate: state.playbackRate);

    // Cập nhật segment đang hiển thị
    final activeSeg = _timelineBuffer.segmentAt(state.playbackPosition);

    state = state.copyWith(
      subtitleReadyUntil: readyUntil,
      dubReadyUntil: dubReadyUntil,
      workMode: mode,
      activeSegment: activeSeg,
      isBufferingForAi: state.errorMessage == null && (_gatePaused || (!canStart && state.playbackPosition == Duration.zero)),
    );

    // Tự động log SRT khi video kết thúc (đã xử lý xong toàn bộ duration)
    if (state.errorMessage == null && mode != AiWorkMode.starting) {
      final duration = activeSource?.capability.duration;
      if (duration != null && duration.inMilliseconds > 0) {
        if (readyUntil >= duration - const Duration(milliseconds: 500) && !state.isSrtLogged) {
          _logFullSrt();
          state = state.copyWith(isSrtLogged: true);
        }
      }
    }
  }

  @override
  void dispose() {
    _activeToken?.cancel();
    _playbackPosSub?.cancel();
    _generation++;
    super.dispose();
  }

  List<TimedTextSegment> _splitIntoSentences(List<TimedTextSegment> segments) {
    final result = <TimedTextSegment>[];
    final sentenceEnd = RegExp(r'(?<=[.!?])\s+');

    for (final seg in segments) {
      final sentences = seg.text.split(sentenceEnd).where((s) => s.trim().isNotEmpty).toList();
      if (sentences.isEmpty) continue;

      final totalChars = sentences.fold(0, (sum, s) => sum + s.trim().length);
      final totalDurationMs = (seg.end - seg.start).inMilliseconds;

      // Theo dõi thời điểm kết thúc thực tế của segment trước đó để tránh overlap
      var currentStartMs = seg.start.inMilliseconds;

      for (var i = 0; i < sentences.length; i++) {
        final cleanS = sentences[i].trim();
        final charRatio = cleanS.length / totalChars;

        // Phân bổ thời gian dựa trên tỷ lệ ký tự
        final allocatedMs = (totalDurationMs * charRatio).round();

        // Tính thời gian hiển thị tự nhiên
        final naturalMs = (cleanS.length * 70) + 600;

        // Cải tiến: Nếu là câu đầu tiên trong một đoạn VAD dài (>3s),
        // dịch chuyển điểm bắt đầu vào trong một chút (đệm silence đầu)
        var startOffset = 0;
        if (i == 0 && totalDurationMs > 3000 && sentences.length > 1) {
            startOffset = 300; // Đệm 300ms
        }

        final start = Duration(milliseconds: currentStartMs + startOffset);
        // Tăng thời gian hiển thị tối thiểu lên 1s để người dùng kịp đọc
        final activeMs = naturalMs.clamp(1000, math.max(1200, allocatedMs));
        var end = Duration(milliseconds: start.inMilliseconds + activeMs.toInt());

        if (end > seg.end) end = seg.end;
        if (end <= start) end = start + const Duration(milliseconds: 500);

        result.add(TimedTextSegment(
          start: start,
          end: end,
          text: cleanS,
          language: seg.language,
        ));

        currentStartMs += allocatedMs;
        if (currentStartMs < end.inMilliseconds) {
            currentStartMs = end.inMilliseconds + 80; // Nghỉ 80ms giữa các câu
        }
      }
    }
    return result;
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
  final diagnostics = ref.watch(diagnosticsServiceProvider);

  if (kIsWeb) {
    return WebPcmAudioExtractor(diagnostics);
  }

  // Đối với video/file, FFmpeg là lựa chọn tốt nhất nhờ bộ lọc xử lý âm thanh mạnh mẽ.
  // NativePcmAudioExtractor chỉ nên dùng cho capture hệ thống (Embedded).
  return FfmpegPcmAudioExtractor(diagnostics);
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