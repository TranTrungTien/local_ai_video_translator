import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../../pipeline/domain/ai_pipeline.dart';

class SpeechSegment {
  const SpeechSegment({
    required this.start,
    required this.end,
    required this.chunks,
    this.speechRatio = 1.0,
  });

  final Duration start;
  final Duration end;
  final List<PcmChunk> chunks;
  final double speechRatio;
}

abstract interface class VoiceActivityDetector {
  bool get installed;
  Stream<SpeechSegment> detectSpeech(Stream<PcmChunk> audioStream);
}

class LocalVadEngine implements VoiceActivityDetector {
  LocalVadEngine({
    this.energyThreshold = 250.0,
    this.minSpeechDuration = const Duration(milliseconds: 400),
    this.maxMergeGap = const Duration(milliseconds: 300),
  });

  final double energyThreshold;
  final Duration minSpeechDuration;
  final Duration maxMergeGap;

  @override
  bool get installed => true;

  @override
  Stream<SpeechSegment> detectSpeech(Stream<PcmChunk> audioStream) async* {
    final rawSegments = <_RawSpeechRange>[];

    Duration? currentStart;
    Duration? currentEnd;
    var currentChunks = <PcmChunk>[];

    await for (final chunk in audioStream) {
      final isSpeech = _isSpeechChunk(chunk);
      final chunkDuration = const Duration(
        milliseconds: 500,
      ); // 500ms per chunk

      if (isSpeech) {
        currentStart ??= chunk.pts;
        currentEnd = chunk.pts + chunkDuration;
        currentChunks.add(chunk);
      } else {
        if (currentStart != null && currentEnd != null) {
          // Check if gap before silence is small enough to merge
          rawSegments.add(
            _RawSpeechRange(
              start: currentStart,
              end: currentEnd,
              chunks: List.unmodifiable(currentChunks),
            ),
          );
          currentStart = null;
          currentEnd = null;
          currentChunks = [];
        }
      }
    }

    if (currentStart != null &&
        currentEnd != null &&
        currentChunks.isNotEmpty) {
      rawSegments.add(
        _RawSpeechRange(
          start: currentStart,
          end: currentEnd,
          chunks: List.unmodifiable(currentChunks),
        ),
      );
    }

    // Apply Merge-Small-Gap policy & Minimum Speech Length filter
    final mergedSegments = _applyMergeAndFilterPolicy(rawSegments);

    for (final seg in mergedSegments) {
      yield SpeechSegment(start: seg.start, end: seg.end, chunks: seg.chunks);
    }
  }

  bool _isSpeechChunk(PcmChunk chunk) {
    if (chunk.bytes.isEmpty) return false;
    final buffer = Uint8List.fromList(chunk.bytes).buffer;
    final samples = Int16List.view(buffer);

    if (samples.isEmpty) return false;

    double sumSquare = 0;
    for (var i = 0; i < samples.length; i++) {
      sumSquare += samples[i] * samples[i];
    }
    final rms = sqrt(sumSquare / samples.length);
    // Best-effort filtering: extreme RMS or silence vs dialogue
    return rms >= energyThreshold;
  }

  List<_RawSpeechRange> _applyMergeAndFilterPolicy(
    List<_RawSpeechRange> input,
  ) {
    if (input.isEmpty) return [];

    final merged = <_RawSpeechRange>[];
    var active = input.first;

    for (var i = 1; i < input.length; i++) {
      final next = input[i];
      final gap = next.start - active.end;

      if (gap <= maxMergeGap) {
        // Merge small gap
        final combinedChunks = <PcmChunk>[...active.chunks, ...next.chunks];
        active = _RawSpeechRange(
          start: active.start,
          end: next.end,
          chunks: List.unmodifiable(combinedChunks),
        );
      } else {
        merged.add(active);
        active = next;
      }
    }
    merged.add(active);

    // Filter out segments shorter than minSpeechDuration
    return merged.where((seg) {
      final duration = seg.end - seg.start;
      return duration >= minSpeechDuration;
    }).toList();
  }
}

class _RawSpeechRange {
  const _RawSpeechRange({
    required this.start,
    required this.end,
    required this.chunks,
  });

  final Duration start;
  final Duration end;
  final List<PcmChunk> chunks;
}
