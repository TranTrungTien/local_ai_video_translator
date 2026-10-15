import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../pipeline/domain/ai_pipeline.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import 'pcm_audio_extractor.dart';

class FfmpegPcmAudioExtractor implements PcmAudioExtractor {
  FfmpegPcmAudioExtractor(this._diagnostics);

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
    final pipePath = await FFmpegKitConfig.registerNewFFmpegPipe();
    if (pipePath == null) {
      _diagnostics.log(
        'FFmpegAudio',
        'Could not register FFmpeg pipe',
        level: LogLevel.error,
      );
      return;
    }

    const sampleRate = 16000;
    const channels = 1;
    const chunkDurationMs = 500;
    const bytesPerSecond = sampleRate * channels * 2;
    const bytesPerChunk = (bytesPerSecond * chunkDurationMs) ~/ 1000;

    _diagnostics.log('FFmpegAudio', 'Starting extraction: ${source.uri}');

    final startMs = startPosition?.inMilliseconds ?? 0;
    final inputPath = source.uri.isScheme('file')
        ? source.uri.toFilePath()
        : source.uri.toString();

    final List<String> args = [
      '-y',
      '-nostdin',
      '-hide_banner',
      '-rw_timeout',
      '5000000',
    ];

    if (source.requestContext.headers.isNotEmpty &&
        !source.uri.isScheme('file')) {
      // Tách User-Agent vì một số build FFmpeg ưu tiên tham số riêng cho nó
      final userAgent = source.requestContext.headers['User-Agent'] ??
          source.requestContext.headers['user-agent'];
      if (userAgent != null) {
        args.addAll(['-user_agent', userAgent]);
      }

      final headersString = source.requestContext.headers.entries
              .where((e) => e.key.toLowerCase() != 'user-agent')
              .map((e) => '${e.key}: ${e.value}')
              .join('\r\n') +
          '\r\n\r\n'; // QUAN TRỌNG: FFmpeg yêu cầu kết thúc bằng 2 cặp CRLF để đánh dấu hết header

      if (headersString.trim().isNotEmpty) {
        args.addAll(['-headers', headersString]);
      }
    }

    if (startMs > 0) {
      args.addAll(['-ss', (startMs / 1000.0).toString()]);
    }

    args.addAll(['-i', inputPath]);
    args.addAll([
      '-vn',
      '-ac',
      '$channels',
      '-ar',
      '$sampleRate',
      '-f',
      's16le',
      pipePath,
    ]);

    // Log command without sensitive headers
    final safeArgs = List<String>.from(args);
    for (int i = 0; i < safeArgs.length - 1; i++) {
      if (safeArgs[i] == '-headers') {
        safeArgs[i + 1] = '***';
      }
    }
    _diagnostics.log(
      'FFmpegAudio',
      'FFmpeg Command: ffmpeg ${safeArgs.join(' ')}',
    );

    final file = File(pipePath);

    final sessionFuture = FFmpegKit.executeWithArgumentsAsync(args, (
      session,
    ) async {
      final returnCode = await session.getReturnCode();
      final logs = await session.getLogs();
      final fullLog = logs.map((l) => l.getMessage()).join('\n');

      if (ReturnCode.isSuccess(returnCode)) {
        _diagnostics.log('FFmpegAudio', 'FFmpeg finished successfully');
      } else {
        _diagnostics.log(
          'FFmpegAudio',
          'FFmpeg Failed (code $returnCode). Log:\n$fullLog',
          level: LogLevel.error,
        );
      }
    });

    final session = await sessionFuture;
    final sessionId = session.getSessionId();

    void cancelListener() {
      FFmpegKit.cancel(sessionId);
    }

    cancellationToken?.addListener(cancelListener);

    try {
      cancellationToken?.throwIfCancelled();
      int retry = 0;
      while (!await file.exists() && retry < 30) {
        await Future.delayed(const Duration(milliseconds: 200));
        cancellationToken?.throwIfCancelled();
        retry++;
      }

      if (!await file.exists()) {
        throw Exception('Pipe file not found: $pipePath');
      }

      _diagnostics.log('FFmpegAudio', 'Pipe ready, opening stream...');
      final inputStream = file.openRead();
      var currentPts = startPosition ?? Duration.zero;
      final pending = BytesBuilder(copy: false);
      int totalBytesRead = 0;

      await for (final data in inputStream.timeout(
        const Duration(seconds: 10),
        onTimeout: (sink) {
          _diagnostics.log(
            'FFmpegAudio',
            'Pipe stream timeout',
            level: LogLevel.warning,
          );
          sink.close();
        },
      )) {
        cancellationToken?.throwIfCancelled();
        totalBytesRead += data.length;
        pending.add(data);

        if (pending.length >= bytesPerChunk) {
          final all = pending.takeBytes();
          var off = 0;
          while (all.length - off >= bytesPerChunk) {
            yield PcmChunk(
              pts: currentPts,
              sampleRate: sampleRate,
              channels: channels,
              bytes: Uint8List.sublistView(all, off, off + bytesPerChunk),
              playbackSessionId: playbackSessionId,
              timelineEpoch: timelineEpoch,
              seekGeneration: seekGeneration,
            );
            off += bytesPerChunk;
            currentPts += const Duration(milliseconds: chunkDurationMs);
          }
          if (off < all.length) {
            pending.add(Uint8List.sublistView(all, off));
          }
        }
      }

      _diagnostics.log(
        'FFmpegAudio',
        'Stream closed. Total bytes: $totalBytesRead',
      );

      if (pending.isNotEmpty && !(cancellationToken?.isCancelled ?? false)) {
        final remaining = pending.takeBytes();
        // Ensure even number of bytes for Int16List conversion if needed elsewhere
        final length = remaining.length & ~1;
        if (length > 0) {
          yield PcmChunk(
            pts: currentPts,
            sampleRate: sampleRate,
            channels: channels,
            bytes: Uint8List.sublistView(remaining, 0, length),
            playbackSessionId: playbackSessionId,
            timelineEpoch: timelineEpoch,
            seekGeneration: seekGeneration,
          );
        }
      }
    } catch (e) {
      if (e is OperationCancelledException || (cancellationToken?.isCancelled ?? false)) {
        _diagnostics.log('FFmpegAudio', 'Extraction cancelled', level: LogLevel.info);
      } else {
        _diagnostics.log(
          'FFmpegAudio',
          'Stream read error: $e',
          level: LogLevel.error,
        );
      }
    } finally {
      cancellationToken?.removeListener(cancelListener);
      // Đảm bảo dừng FFmpeg và giải phóng pipe
      await FFmpegKit.cancel(sessionId);
      await FFmpegKitConfig.closeFFmpegPipe(pipePath);
      _diagnostics.log(
        'FFmpegAudio',
        'Cleaned up FFmpeg session $sessionId and pipe $pipePath',
      );
    }
  }
}
