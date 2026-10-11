import 'dart:async';

import 'package:flutter/services.dart';

import '../../../core/diagnostics/diagnostics_service.dart';
import '../../pipeline/domain/ai_pipeline.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import 'ffmpeg_audio_extractor.dart';

abstract interface class PcmAudioExtractor {
  bool get isAvailable;
  Stream<PcmChunk> extractPcmStream(
    ResolvedSource source, {
    Duration? startPosition,
  });
}

class NativePcmAudioExtractor implements PcmAudioExtractor {
  NativePcmAudioExtractor(this._diagnostics);

  final DiagnosticsService _diagnostics;
  static const _methodChannel = MethodChannel('local_ai_video_translator/native_resolver');
  static const _eventChannel = EventChannel('local_ai_video_translator/media_events');

  @override
  bool get isAvailable => true;

  @override
  Stream<PcmChunk> extractPcmStream(
    ResolvedSource source, {
    Duration? startPosition,
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
      // Use FFmpeg for local files or direct streams
      yield* FfmpegPcmAudioExtractor(_diagnostics).extractPcmStream(
        source,
        startPosition: startPosition,
      );
      return;
    }

    // 2. Listen to audio chunks from EventChannel (dành cho MediaProjection)
    int? firstTimestamp;

    final subscription = _eventChannel.receiveBroadcastStream().listen((event) {
      if (event is Map && event['type'] == 'audio_chunk') {
        final data = event['data'] as Uint8List;
        final sampleRate = event['sampleRate'] as int;
        final channels = event['channels'] as int;
        final timestamp = event['timestamp'] as int;

        // Calculate PTS based on native timestamp comparison
        firstTimestamp ??= timestamp;
        final elapsedMs = timestamp - firstTimestamp!;
        final currentPts = (startPosition ?? Duration.zero) + Duration(milliseconds: elapsedMs);

        controller.add(PcmChunk(
          pts: currentPts,
          sampleRate: sampleRate,
          channels: channels,
          bytes: data,
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
