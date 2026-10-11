import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../../../core/diagnostics/diagnostics_service.dart';
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
  }) async* {
    final pipePath = await FFmpegKitConfig.registerNewFFmpegPipe();
    if (pipePath == null) {
      _diagnostics.log('FFmpegAudio', 'Could not register FFmpeg pipe', level: LogLevel.error);
      return;
    }

    final sampleRate = 16000;
    final channels = 1;
    final chunkDurationMs = 500;
    final bytesPerSecond = sampleRate * channels * 2;
    final bytesPerChunk = (bytesPerSecond * chunkDurationMs) ~/ 1000;

    _diagnostics.log('FFmpegAudio', 'Starting extraction: ${source.uri}');
    
    final startMs = startPosition?.inMilliseconds ?? 0;
    final ssArg = startMs > 0 ? '-ss ${startMs / 1000.0}' : '';
    
    String headersArg = '';
    if (source.requestContext.headers.isNotEmpty) {
      final headersString = source.requestContext.headers.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('\r\n');
      headersArg = '-headers "$headersString"';
    }

    // Convert to local path if it's a file URI for better compatibility on Android
    final inputPath = source.uri.isScheme('file') ? source.uri.toFilePath() : source.uri.toString();

    // CRITICAL: -y is required because registerNewFFmpegPipe() creates the pipe file on disk
    // before FFmpeg starts. FFmpeg will see it and ask to overwrite.
    // -nostdin prevents FFmpeg from hanging waiting for input.
    final ffmpegCommand = '-y -nostdin -hide_banner '
        '$headersArg $ssArg -i "$inputPath" -vn -ac $channels -ar $sampleRate -f s16le "$pipePath"';

    _diagnostics.log('FFmpegAudio', 'FFmpeg Command: $ffmpegCommand');

    final file = File(pipePath);

    // Run FFmpeg in background
    final sessionFuture = FFmpegKit.executeAsync(ffmpegCommand, (session) async {
      final returnCode = await session.getReturnCode();
      final logs = await session.getLogs();
      final fullLog = logs.map((l) => l.getMessage()).join('\n');

      if (ReturnCode.isSuccess(returnCode)) {
        _diagnostics.log('FFmpegAudio', 'FFmpeg finished successfully');
      } else {
        _diagnostics.log('FFmpegAudio', 'FFmpeg Failed (code $returnCode). Log:\n$fullLog',
            level: LogLevel.error);
      }
    });

    try {
      int retry = 0;
      while (!await file.exists() && retry < 30) {
        await Future.delayed(const Duration(milliseconds: 200));
        retry++;
      }

      if (!await file.exists()) {
        _diagnostics.log('FFmpegAudio', 'Pipe file not found: $pipePath', level: LogLevel.error);
        return;
      }

      _diagnostics.log('FFmpegAudio', 'Pipe ready, opening stream...');
      final inputStream = file.openRead();
      var currentPts = startPosition ?? Duration.zero;
      List<int> pendingBuffer = [];
      int totalBytesRead = 0;

      await for (final data in inputStream) {
        totalBytesRead += data.length;
        pendingBuffer.addAll(data);

        while (pendingBuffer.length >= bytesPerChunk) {
          final chunkData = pendingBuffer.sublist(0, bytesPerChunk);
          pendingBuffer = pendingBuffer.sublist(bytesPerChunk);

          yield PcmChunk(
            pts: currentPts,
            sampleRate: sampleRate,
            channels: channels,
            bytes: Uint8List.fromList(chunkData),
          );

          currentPts += Duration(milliseconds: chunkDurationMs);
        }
      }
      
      _diagnostics.log('FFmpegAudio', 'Stream closed. Total bytes: $totalBytesRead');

      if (pendingBuffer.isNotEmpty) {
        yield PcmChunk(
          pts: currentPts,
          sampleRate: sampleRate,
          channels: channels,
          bytes: Uint8List.fromList(pendingBuffer),
        );
      }
    } catch (e) {
      _diagnostics.log('FFmpegAudio', 'Stream read error: $e', level: LogLevel.error);
    } finally {
      final session = await sessionFuture;
      await FFmpegKit.cancel(session.getSessionId());
      _diagnostics.log('FFmpegAudio', 'Cleaned up FFmpeg session');
    }
  }
}
