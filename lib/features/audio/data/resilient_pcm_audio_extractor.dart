import 'dart:async';
import 'dart:math' as math;

import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../pipeline/domain/ai_pipeline.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import 'pcm_audio_extractor.dart';

/// Extractor không thể tiếp tục sau khi đã thử lại.
class PcmExtractionException implements Exception {
  const PcmExtractionException(this.message);
  final String message;

  @override
  String toString() => 'PcmExtractionException: $message';
}

/// Bọc một [PcmAudioExtractor] cho nguồn REMOTE (HLS/HTTP):
///  1. Stream kết thúc sớm / lỗi giữa chừng -> mở lại từ PTS cuối (có backoff).
///  2. Consumer đứng chờ lâu (buffer AI đầy) -> chủ động đóng và mở lại, để
///     kết nối HTTP không bị treo hàng phút rồi bị CDN cắt.
///  3. Hết số lần thử -> ném [PcmExtractionException] (không còn kết thúc im lặng).
///
/// Không dùng cho file local (giữ nguyên hành vi cũ).
class ResilientPcmAudioExtractor implements PcmAudioExtractor {
  ResilientPcmAudioExtractor(
    this._inner,
    this._diagnostics, {
    this.durationProvider,
    this.maxRetries = 4,
    this.idleReopenAfter = const Duration(seconds: 12),
    this.endTolerance = const Duration(seconds: 8),
    this.retryBaseDelay = const Duration(seconds: 1),
  });

  final PcmAudioExtractor _inner;
  final DiagnosticsService _diagnostics;
  final Duration? Function()? durationProvider;
  final int maxRetries;
  final Duration idleReopenAfter;
  final Duration endTolerance;
  final Duration retryBaseDelay;

  @override
  bool get isAvailable => _inner.isAvailable;

  Duration _chunkDuration(PcmChunk c) {
    final bytesPerSecond = c.sampleRate * c.channels * 2;
    if (bytesPerSecond <= 0) return Duration.zero;
    return Duration(microseconds: c.bytes.length * 1000000 ~/ bytesPerSecond);
  }

  @override
  Stream<PcmChunk> extractPcmStream(
    ResolvedSource source, {
    Duration? startPosition,
    String playbackSessionId = '',
    int timelineEpoch = 0,
    int seekGeneration = 0,
    CancellationToken? cancellationToken,
  }) async* {
    var resumeAt = startPosition ?? Duration.zero;
    var failures = 0;
    var everReceived = false;

    while (true) {
      cancellationToken?.throwIfCancelled();

      final it = StreamIterator<PcmChunk>(
        _inner.extractPcmStream(
          source,
          startPosition: resumeAt,
          playbackSessionId: playbackSessionId,
          timelineEpoch: timelineEpoch,
          seekGeneration: seekGeneration,
          cancellationToken: cancellationToken,
        ),
      );

      var received = 0;
      var reopenForIdle = false;
      try {
        while (await it.moveNext()) {
          final chunk = it.current;
          received++;
          everReceived = true;
          failures = 0;
          resumeAt = chunk.pts + _chunkDuration(chunk);

          final waited = Stopwatch()..start();
          yield chunk;
          // Consumer chờ quá lâu (đang đợi buffer cần thêm) => kết nối nhiều khả
          // năng đã chết/treo. Đóng và mở lại từ resumeAt.
          if (waited.elapsed > idleReopenAfter) {
            reopenForIdle = true;
            break;
          }
        }
      } finally {
        await it.cancel();
      }

      if (cancellationToken?.isCancelled ?? false) return;

      if (reopenForIdle) {
        _diagnostics.log(
          'ResilientPcm',
          'Consumer idle > ${idleReopenAfter.inSeconds}s, reopening at ${resumeAt.inMilliseconds}ms',
        );
        continue;
      }

      // Stream đã kết thúc: EOF thật hay bị cắt?
      final duration = durationProvider?.call();
      final knownDuration = duration != null && duration > Duration.zero;

      if (knownDuration && resumeAt >= duration - endTolerance) {
        _diagnostics.log('ResilientPcm', 'Reached end of media at ${resumeAt.inMilliseconds}ms');
        return;
      }

      if (received > 0) {
        // Có tiến triển nhưng stream đứt sớm -> mở lại ngay.
        _diagnostics.log(
          'ResilientPcm',
          'Stream ended early at ${resumeAt.inMilliseconds}ms, reopening',
          level: LogLevel.warning,
        );
        continue;
      }

      // Lần thử này không nhận được chunk nào.
      if (!knownDuration && everReceived) {
        // Không biết duration và mở lại không ra thêm gì => coi là EOF.
        _diagnostics.log('ResilientPcm', 'No more audio after ${resumeAt.inMilliseconds}ms, treating as EOF');
        return;
      }

      failures++;
      if (failures > maxRetries) {
        throw PcmExtractionException(
          'Không đọc được audio từ nguồn sau $maxRetries lần thử '
          '(vị trí ${resumeAt.inSeconds}s).',
        );
      }
      final delayMs = math.min(
        retryBaseDelay.inMilliseconds * (1 << (failures - 1)),
        8000,
      );
      _diagnostics.log(
        'ResilientPcm',
        'Open failed at ${resumeAt.inMilliseconds}ms, retry $failures/$maxRetries in ${delayMs}ms',
        level: LogLevel.warning,
      );
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }
}
