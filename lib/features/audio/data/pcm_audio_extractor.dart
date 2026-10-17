import 'dart:async';

import 'package:flutter/services.dart';

import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../pipeline/domain/ai_pipeline.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import 'ffmpeg_audio_extractor.dart';
import 'resilient_pcm_audio_extractor.dart';

abstract interface class PcmAudioExtractor {
  bool get isAvailable;
  Stream<PcmChunk> extractPcmStream(
    ResolvedSource source, {
    Duration? startPosition,
    String playbackSessionId = '',
    int timelineEpoch = 0,
    int seekGeneration = 0,
    CancellationToken? cancellationToken,
  });
}

class NativePcmAudioExtractor implements PcmAudioExtractor {
  NativePcmAudioExtractor(this._diagnostics, {this.durationProvider});

  final DiagnosticsService _diagnostics;
  final Duration? Function()? durationProvider;
  static const _methodChannel = MethodChannel('local_ai_video_translator/native_resolver');
  static const _eventChannel = EventChannel('local_ai_video_translator/audio_pcm');

  @override
  bool get isAvailable => true;

  @override
  Stream<PcmChunk> extractPcmStream(
    ResolvedSource source, {
    Duration? startPosition,
    String playbackSessionId = '',
    int timelineEpoch = 0,
    int seekGeneration = 0,
    CancellationToken? cancellationToken,
  }) async* {
    // Chỉ yêu cầu MediaProjection (Share Screen) nếu là nguồn nhúng (Webview)
    // Nguồn local hoặc direct stream thì không cần.
    final needsMediaProjection = source.kind == MediaKind.embedded ||
                                source.playbackMode == PlaybackMode.embedded;

    if (needsMediaProjection) {
      _diagnostics.log('NativeAudio', 'Requesting MediaProjection for embedded source');
      final started = await _methodChannel.invokeMethod<bool>('startAudioCapture');
      if (started != true) {
        _diagnostics.log('NativeAudio', 'MediaProjection denied or failed', level: LogLevel.error);
        throw Exception('Could not start native audio capture for web source');
      }
    }

    final controller = StreamController<PcmChunk>();

    if (!needsMediaProjection) {
      _diagnostics.log('NativeAudio', 'Local/Direct source detected. Using FFmpeg for extraction.');
      // Local: giữ nguyên đường FFmpeg cũ. Remote (http/https): bọc thêm lớp tự phục hồi.
      final ffmpeg = FfmpegPcmAudioExtractor(_diagnostics);
      final isRemote = source.uri.scheme == 'http' || source.uri.scheme == 'https';
      final PcmAudioExtractor extractor = isRemote
          ? ResilientPcmAudioExtractor(
              ffmpeg,
              _diagnostics,
              durationProvider: durationProvider,
            )
          : ffmpeg;
      yield* extractor.extractPcmStream(
        source,
        startPosition: startPosition,
        playbackSessionId: playbackSessionId,
        timelineEpoch: timelineEpoch,
        seekGeneration: seekGeneration,
        cancellationToken: cancellationToken,
      );
      return;
    }

    cancellationToken?.addListener(() {
      _methodChannel.invokeMethod('stopAudioCapture');
      if (!controller.isClosed) {
        controller.close();
      }
    });

    // 2. Listen to audio chunks from EventChannel (dành cho MediaProjection)
    final subscription = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map && event['type'] == 'audio_chunk') {
        final data = event['pcmBytes'] as Uint8List;
        final sampleRate = event['sampleRate'] as int;
        final channels = event['channelCount'] as int;
        final mediaPtsUs = event['mediaPtsUs'] as int;
        final playbackSessionId = event['playbackSessionId'] as String? ?? '';
        final timelineEpoch = event['timelineEpoch'] as int? ?? 0;
        final seekGeneration = event['seekGeneration'] as int? ?? 0;

        controller.add(PcmChunk(
          pts: Duration(microseconds: mediaPtsUs),
          sampleRate: sampleRate,
          channels: channels,
          bytes: data,
          playbackSessionId: playbackSessionId,
          timelineEpoch: timelineEpoch,
          seekGeneration: seekGeneration,
        ));
      }
    });

    try {
      yield* controller.stream;
    } finally {
      await subscription.cancel();
      await _methodChannel.invokeMethod('stopAudioCapture');
      await controller.close();
    }
  }
}

class DefaultPcmAudioExtractor implements PcmAudioExtractor {
  const DefaultPcmAudioExtractor();

  @override
  bool get isAvailable => true;

  @override
  Stream<PcmChunk> extractPcmStream(
    ResolvedSource source, {
    Duration? startPosition,
    String playbackSessionId = '',
    int timelineEpoch = 0,
    int seekGeneration = 0,
    CancellationToken? cancellationToken,
  }) async* {
    // Media PTS audio stream generator
    // Generates 16kHz mono PCM chunks annotated with media Presentation Timestamps (PTS)
    const sampleRate = 16000;
    const channels = 1;
    const chunkDurationMs = 500; // 500ms chunks
    const samplesPerChunk = (sampleRate * chunkDurationMs) ~/ 1000;
    const bytesPerSample = 2; // 16-bit PCM
    const chunkByteLength = samplesPerChunk * bytesPerSample * channels;

    var currentPts = startPosition ?? Duration.zero;

    // Simulated/Real media stream reader generating PCM audio data bound to PTS
    for (var i = 0; i < 120; i++) {
      final pcmBytes = Uint8List(chunkByteLength);
      yield PcmChunk(
        pts: currentPts,
        sampleRate: sampleRate,
        channels: channels,
        bytes: pcmBytes,
      );
      currentPts += const Duration(milliseconds: chunkDurationMs);
    }
  }
}