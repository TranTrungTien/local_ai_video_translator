import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../pipeline/domain/ai_pipeline.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import 'pcm_audio_extractor.dart';

class WebPcmAudioExtractor implements PcmAudioExtractor {
  WebPcmAudioExtractor(this._diagnostics);

  final DiagnosticsService _diagnostics;

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
    _diagnostics.log('WebAudio', 'Starting web extraction for: ${source.uri}');

    final controller = StreamController<PcmChunk>();

    // Web Audio API extraction strategy:
    // 1. Create a hidden <video> element
    // 2. Route its audio to a MediaElementAudioSourceNode
    // 3. Use AudioWorklet to capture and resample to 16kHz Mono

    web.HTMLVideoElement? video;
    web.AudioContext? audioCtx;

    try {
      video = web.document.createElement('video') as web.HTMLVideoElement;
      video.src = source.uri.toString();
      video.crossOrigin = 'anonymous';
      video.muted = true; // Extract without audible playback

      if (startPosition != null) {
        video.currentTime = startPosition.inMilliseconds / 1000.0;
      }

      audioCtx = web.AudioContext();

      // Ensure AudioContext is resumed (browsers might start it in 'suspended' state)
      if (audioCtx.state == 'suspended') {
        await audioCtx.resume().toDart;
      }

      final sourceNode = audioCtx.createMediaElementSource(video);

      // Load the processor script
      await audioCtx.audioWorklet.addModule('scripts/audio_processor.js').toDart;

      final processorNode = web.AudioWorkletNode(audioCtx, 'audio-processor');

      processorNode.port.onmessage = (web.MessageEvent event) {
        final buffer = event.data as JSArrayBuffer;
        final pcmBytes = buffer.toDart.asUint8List();

        if (!controller.isClosed) {
          controller.add(PcmChunk(
            pts: Duration(milliseconds: (video!.currentTime * 1000).toInt()),
            sampleRate: 16000,
            channels: 1,
            bytes: pcmBytes,
            playbackSessionId: playbackSessionId,
            timelineEpoch: timelineEpoch,
            seekGeneration: seekGeneration,
          ));
        }
      }.toJS;

      sourceNode.connect(processorNode);
      // We don't connect to destination to keep it silent

      await video.play().toDart;

      cancellationToken?.addListener(() {
        video?.pause();
        if (!controller.isClosed) controller.close();
      });

      yield* controller.stream;
    } catch (e) {
      _diagnostics.log('WebAudio', 'Extraction failed: $e', level: LogLevel.error);
      rethrow;
    } finally {
      video?.pause();
      video?.remove();
      await audioCtx?.close().toDart;
      if (!controller.isClosed) await controller.close();
    }
  }
}
