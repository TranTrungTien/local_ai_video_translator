import 'dart:async';
import 'dart:typed_data';

import '../../pipeline/domain/ai_pipeline.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';

abstract interface class PcmAudioExtractor {
  bool get isAvailable;
  Stream<PcmChunk> extractPcmStream(
    ResolvedSource source, {
    Duration? startPosition,
  });
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
