# Review Module: 04. Audio Extractor & Silero VAD Engine

## Included Files (7 files)

```text
android/app/src/main/kotlin/com/example/local_ai_video_translator/AudioCaptureService.kt
lib/features/audio/data/audio_diagnostics.dart
lib/features/audio/data/bounded_pcm_queue.dart
lib/features/audio/data/ffmpeg_audio_extractor.dart
lib/features/audio/data/pcm_audio_extractor.dart
lib/features/audio/data/vad_engine.dart
lib/features/audio/domain/entities/audio_stream_info.dart
```

## android/app/src/main/kotlin/com/example/local_ai_video_translator/AudioCaptureService.kt
```kotlin:android/app/src/main/kotlin/com/example/local_ai_video_translator/AudioCaptureService.kt
package com.example.local_ai_video_translator

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.*
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import kotlin.concurrent.thread

class AudioCaptureService : Service() {
    companion object {
        const val ACTION_START = "ACTION_START"
        const val ACTION_STOP = "ACTION_STOP"
        const val EXTRA_RESULT_CODE = "EXTRA_RESULT_CODE"
        const val EXTRA_DATA = "EXTRA_DATA"
        private const val NOTIFICATION_ID = 101
        private const val CHANNEL_ID = "audio_capture_channel"
    }

    private var mediaProjection: MediaProjection? = null
    private var audioRecord: AudioRecord? = null
    private var isCapturing = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                val data = intent.getParcelableExtra<Intent>(EXTRA_DATA)
                if (data != null) {
                    startForegroundService()
                    startCapture(resultCode, data)
                }
            }
            ACTION_STOP -> stopCapture()
        }
        return START_NOT_STICKY
    }

    private fun startForegroundService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Audio Capture", NotificationManager.IMPORTANCE_LOW)
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("AI Translator is Listening")
            .setContentText("Translating audio from current video...")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    private fun startCapture(resultCode: Int, data: Intent) {
        val mpManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = mpManager.getMediaProjection(resultCode, data)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val config = AudioPlaybackCaptureConfiguration.Builder(mediaProjection!!)
                .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
                .addMatchingUsage(AudioAttributes.USAGE_GAME)
                .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
                .build()

            val sampleRate = 16000
            val channelConfig = AudioFormat.CHANNEL_IN_MONO
            val audioFormat = AudioFormat.ENCODING_PCM_16BIT
            val bufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat) * 2

            audioRecord = AudioRecord.Builder()
                .setAudioFormat(AudioFormat.Builder()
                    .setEncoding(audioFormat)
                    .setSampleRate(sampleRate)
                    .setChannelMask(channelConfig)
                    .build())
                .setAudioPlaybackCaptureConfig(config)
                .setBufferSizeInBytes(bufferSize)
                .build()

            audioRecord?.startRecording()
            isCapturing = true

            thread {
                val buffer = ByteArray(bufferSize)
                while (isCapturing) {
                    val captureMonotonicUs = System.nanoTime() / 1000
                    val read = audioRecord?.read(buffer, 0, buffer.size) ?: 0
                    if (read > 0) {
                        AudioPcmBroker.emitAudioChunk(
                            pcmBytes = buffer.copyOf(read),
                            sampleRate = sampleRate,
                            channelCount = 1,
                            encoding = audioFormat,
                            captureMonotonicUs = captureMonotonicUs,
                            durationUs = (read.toLong() * 1_000_000L) / (sampleRate * 2)
                        )
                    }
                }
            }
        }
    }

    private fun stopCapture() {
        isCapturing = false
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null
        mediaProjection?.stop()
        mediaProjection = null
        stopForeground(true)
        stopSelf()
    }

    override fun onDestroy() {
        stopCapture()
        super.onDestroy()
    }
}

```

## lib/features/audio/data/audio_diagnostics.dart
```dart:lib/features/audio/data/audio_diagnostics.dart
import 'dart:async';

class AudioMetrics {
  const AudioMetrics({
    this.queueSize = 0,
    this.queuedAudioSeconds = 0.0,
    this.vadRealtimeFactor = 1.0,
    this.speechPercentage = 0.0,
    this.memoryConsumptionBytes = 0,
  });

  final int queueSize;
  final double queuedAudioSeconds;
  final double vadRealtimeFactor;
  final double speechPercentage;
  final int memoryConsumptionBytes;

  AudioMetrics copyWith({
    int? queueSize,
    double? queuedAudioSeconds,
    double? vadRealtimeFactor,
    double? speechPercentage,
    int? memoryConsumptionBytes,
  }) {
    return AudioMetrics(
      queueSize: queueSize ?? this.queueSize,
      queuedAudioSeconds: queuedAudioSeconds ?? this.queuedAudioSeconds,
      vadRealtimeFactor: vadRealtimeFactor ?? this.vadRealtimeFactor,
      speechPercentage: speechPercentage ?? this.speechPercentage,
      memoryConsumptionBytes:
          memoryConsumptionBytes ?? this.memoryConsumptionBytes,
    );
  }
}

class AudioDiagnostics {
  AudioMetrics _metrics = const AudioMetrics();
  final _controller = StreamController<AudioMetrics>.broadcast();

  AudioMetrics get metrics => _metrics;
  Stream<AudioMetrics> get stream => _controller.stream;

  void updateMetrics(AudioMetrics newMetrics) {
    _metrics = newMetrics;
    if (!_controller.isClosed) {
      _controller.add(_metrics);
    }
  }

  void reset() {
    _metrics = const AudioMetrics();
    if (!_controller.isClosed) {
      _controller.add(_metrics);
    }
  }

  void dispose() {
    _controller.close();
  }
}

```

## lib/features/audio/data/bounded_pcm_queue.dart
```dart:lib/features/audio/data/bounded_pcm_queue.dart
import 'dart:collection';
import '../../pipeline/domain/ai_pipeline.dart';

class BoundedPcmQueue {
  BoundedPcmQueue({this.maxCapacity = 100});

  final int maxCapacity;
  final Queue<PcmChunk> _queue = Queue<PcmChunk>();

  int get length => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  bool get isFull => _queue.length >= maxCapacity;

  void enqueue(PcmChunk chunk) {
    if (isFull) {
      // Drop oldest chunk to apply backpressure & prevent unlimited memory accumulation
      _queue.removeFirst();
    }
    _queue.add(chunk);
  }

  PcmChunk? dequeue() {
    if (_queue.isEmpty) return null;
    return _queue.removeFirst();
  }

  void clearBefore(Duration pts) {
    _queue.removeWhere(
      (chunk) => chunk.pts + const Duration(milliseconds: 500) < pts,
    );
  }

  void clear() {
    _queue.clear();
  }

  Duration get queuedAudioDuration {
    if (_queue.isEmpty) return Duration.zero;
    final first = _queue.first.pts;
    final last = _queue.last.pts + const Duration(milliseconds: 500);
    return last > first ? last - first : Duration.zero;
  }

  int get approximateMemoryBytes {
    int total = 0;
    for (final chunk in _queue) {
      total += chunk.bytes.length;
    }
    return total;
  }
}

```

## lib/features/audio/data/ffmpeg_audio_extractor.dart
```dart:lib/features/audio/data/ffmpeg_audio_extractor.dart
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
      List<int> pendingBuffer = [];
      int totalBytesRead = 0;

      await for (final data in inputStream.timeout(
        const Duration(seconds: 10), // Tăng timeout cho mạng chậm
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
        pendingBuffer.addAll(data);

        while (pendingBuffer.length >= bytesPerChunk) {
          final chunkData = pendingBuffer.sublist(0, bytesPerChunk);
          pendingBuffer = pendingBuffer.sublist(bytesPerChunk);

          yield PcmChunk(
            pts: currentPts,
            sampleRate: sampleRate,
            channels: channels,
            bytes: Uint8List.fromList(chunkData),
            playbackSessionId: playbackSessionId,
            timelineEpoch: timelineEpoch,
            seekGeneration: seekGeneration,
          );

          currentPts += const Duration(milliseconds: chunkDurationMs);
        }
      }

      _diagnostics.log(
        'FFmpegAudio',
        'Stream closed. Total bytes: $totalBytesRead',
      );

      if (pendingBuffer.isNotEmpty && !cancellationToken!.isCancelled) {
        yield PcmChunk(
          pts: currentPts,
          sampleRate: sampleRate,
          channels: channels,
          bytes: Uint8List.fromList(pendingBuffer),
          playbackSessionId: playbackSessionId,
          timelineEpoch: timelineEpoch,
          seekGeneration: seekGeneration,
        );
      }
    } catch (e) {
      if (e is OperationCancelledException) {
        _diagnostics.log('FFmpegAudio', 'Extraction cancelled');
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

```

## lib/features/audio/data/pcm_audio_extractor.dart
```dart:lib/features/audio/data/pcm_audio_extractor.dart
import 'dart:async';

import 'package:flutter/services.dart';

import '../../../core/diagnostics/diagnostics_service.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../pipeline/domain/ai_pipeline.dart';
import '../../source_resolver/domain/entities/resolved_source.dart';
import 'ffmpeg_audio_extractor.dart';

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
  NativePcmAudioExtractor(this._diagnostics);

  final DiagnosticsService _diagnostics;
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
      // Use FFmpeg for local files or direct streams
      yield* FfmpegPcmAudioExtractor(_diagnostics).extractPcmStream(
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

```

## lib/features/audio/data/vad_engine.dart
```dart:lib/features/audio/data/vad_engine.dart
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../../../core/diagnostics/diagnostics_service.dart';
import '../../pipeline/domain/ai_pipeline.dart';
import '../../settings/data/model_manager_repository.dart';

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
  Stream<SpeechSegment> detectSpeech(
    Stream<PcmChunk> audioStream, {
    void Function(Duration pts, Duration? activeSpeechStart)? onProgress,
  });
}

class LocalVadEngine implements VoiceActivityDetector {
  LocalVadEngine(
    this._modelRepository,
    this._diagnostics, {
    this.threshold = 0.5,
    this.minSpeechDuration = const Duration(milliseconds: 250),
    this.maxMergeGap = const Duration(milliseconds: 300),
    this.preRollDuration = const Duration(milliseconds: 200),
  });

  final ModelManagerRepository _modelRepository;
  final DiagnosticsService _diagnostics;
  final double threshold;
  final Duration minSpeechDuration;
  final Duration maxMergeGap;
  final Duration preRollDuration;

  static const String modelId = 'vad_silero';

  OrtSession? _session;
  final Float32List _state = Float32List(2 * 1 * 128);

  // Tái sử dụng bộ đệm 512 float32 để giảm thiểu Garbage Collection
  final Float32List _windowFloatBuffer = Float32List(512);

  @override
  bool get installed => true;

  Future<void> _ensureInitialized() async {
    if (_session != null) return;

    final modelFile = await _modelRepository.getModelFile(
      modelId,
      'silero_vad.onnx',
    );
    if (!await modelFile.exists()) {
      return;
    }

    final sessionOptions = OrtSessionOptions();
    _session = await OnnxRuntime().createSession(
      modelFile.path,
      options: sessionOptions,
    );
  }

  @override
  Stream<SpeechSegment> detectSpeech(
    Stream<PcmChunk> audioStream, {
    void Function(Duration pts, Duration? activeSpeechStart)? onProgress,
  }) async* {
    await _ensureInitialized();
    _resetState();

    final windowBuffer = BytesBuilder();
    const windowSizeBytes = 512 * 2;
    const windowDuration = Duration(milliseconds: 32);

    final List<PcmChunk> preRollBuffer = [];
    _RawSpeechRange? active;
    _RawSpeechRange? pendingGap;

    Duration? bufferStartPts;

    await for (final chunk in audioStream) {
      final bytesPerMs = (chunk.sampleRate * 1 * 2) ~/ 1000;

      if (bufferStartPts == null) {
        bufferStartPts = chunk.pts;
      } else {
        // Check if the new chunk is continuous with the data in the buffer
        final expectedNextPts = bufferStartPts +
            Duration(milliseconds: windowBuffer.length ~/ bytesPerMs);
        final drift = (chunk.pts - expectedNextPts).inMilliseconds.abs();

        if (drift > 100) {
          // Discontinuity (e.g., seek), clear old buffer and state
          windowBuffer.clear();
          bufferStartPts = chunk.pts;
          preRollBuffer.clear();

          if (active != null && active.end - active.start >= minSpeechDuration) {
             yield SpeechSegment(
              start: active.start,
              end: active.end,
              chunks: List.unmodifiable(active.chunks),
            );
          }

          active = null;
          pendingGap = null;
          _resetState();
        }
      }

      windowBuffer.add(chunk.bytes);

      while (windowBuffer.length >= windowSizeBytes) {
        final windowBytes = windowBuffer.takeBytes();
        final currentWindowBytes = windowBytes.sublist(0, windowSizeBytes);
        if (windowBytes.length > windowSizeBytes) {
          windowBuffer.add(windowBytes.sublist(windowSizeBytes));
        }

        final currentPts = bufferStartPts!;
        final currentChunk = PcmChunk(
          pts: currentPts,
          sampleRate: chunk.sampleRate,
          channels: 1,
          bytes: currentWindowBytes,
          playbackSessionId: chunk.playbackSessionId,
          timelineEpoch: chunk.timelineEpoch,
          seekGeneration: chunk.seekGeneration,
        );

        if (onProgress != null) {
          onProgress.call(currentPts + windowDuration, active?.start);
        }

        final isSpeech = await _isSpeechData(
          currentWindowBytes,
          chunk.sampleRate,
        );

        bufferStartPts += windowDuration;

        if (isSpeech) {
          active ??= _RawSpeechRange(
            start: preRollBuffer.isNotEmpty
                ? preRollBuffer.first.pts
                : currentPts,
            end: currentPts + windowDuration,
            chunks: [...preRollBuffer],
          );

          if (pendingGap != null) {
            active.chunks.addAll(pendingGap.chunks);
            pendingGap = null;
          }
          active.chunks.add(currentChunk);
          active.end = currentPts + windowDuration;

          preRollBuffer.clear();
        } else {
          if (active != null) {
            pendingGap ??= _RawSpeechRange(
              start: currentPts,
              end: currentPts + windowDuration,
              chunks: [],
            );
            pendingGap.chunks.add(currentChunk);
            pendingGap.end = currentPts + windowDuration;

            if (pendingGap.end - pendingGap.start > maxMergeGap) {
              if (active.end - active.start >= minSpeechDuration) {
                yield SpeechSegment(
                  start: active.start,
                  end: active.end,
                  chunks: List.unmodifiable(active.chunks),
                );
              }
              active = null;
              pendingGap = null;
            }
          } else {
            preRollBuffer.add(currentChunk);
            final totalPreRoll =
                preRollBuffer.length * windowDuration.inMilliseconds;
            if (totalPreRoll > preRollDuration.inMilliseconds) {
              preRollBuffer.removeAt(0);
            }
          }
        }
      }
    }

    if (active != null && active.end - active.start >= minSpeechDuration) {
      yield SpeechSegment(
        start: active.start,
        end: active.end,
        chunks: List.unmodifiable(active.chunks),
      );
    }
  }

  void _resetState() {
    _state.fillRange(0, _state.length, 0.0);
  }

  Future<bool> _isSpeechData(Uint8List bytes, int sampleRate) async {
    final session = _session;
    if (session == null) return _isSpeechEnergy(bytes);

    try {
      _fillPcm16ToFloat32Buffer(bytes, _windowFloatBuffer);

      final inputOrt = await OrtValue.fromList(_windowFloatBuffer, [
        1,
        _windowFloatBuffer.length,
      ]);
      final srOrt = await OrtValue.fromList(Int64List.fromList([sampleRate]), [
        1,
      ]);
      final stateOrt = await OrtValue.fromList(_state, [2, 1, 128]);

      final inputs = {'input': inputOrt, 'sr': srOrt, 'state': stateOrt};

      final outputs = await session.run(inputs);

      final outputVal = await outputs['output']?.asList();
      final stateVal = await outputs['state']?.asList();

      if (outputVal != null && stateVal != null) {
        final probability = outputVal[0][0] as double;
        _updateState(_state, stateVal as List<List<List<double>>>);

        await inputOrt.dispose();
        await srOrt.dispose();
        await stateOrt.dispose();
        await outputs['output']?.dispose();
        await outputs['state']?.dispose();

        return probability >= threshold;
      }
    } catch (e, st) {
      _diagnostics.log(
        'VAD_ENGINE',
        'Inference error: $e',
        level: LogLevel.error,
        details: st,
      );
    }
    return _isSpeechEnergy(bytes);
  }

  void _fillPcm16ToFloat32Buffer(Uint8List bytes, Float32List targetBuffer) {
    final int16Data = bytes.buffer.asInt16List();
    const double scale = 1.0 / 32768.0;
    final len = min(int16Data.length, targetBuffer.length);
    for (var i = 0; i < len; i++) {
      targetBuffer[i] = int16Data[i] * scale;
    }
  }

  void _updateState(Float32List state, List<List<List<double>>> newValue) {
    int idx = 0;
    for (var i = 0; i < newValue.length; i++) {
      for (var j = 0; j < newValue[i].length; j++) {
        for (var k = 0; k < newValue[i][j].length; k++) {
          state[idx++] = newValue[i][j][k].toDouble();
        }
      }
    }
  }

  bool _isSpeechEnergy(Uint8List bytes) {
    final samples = bytes.buffer.asInt16List();
    double sumSquare = 0;
    for (final s in samples) {
      sumSquare += s * s;
    }
    final energy = sqrt(sumSquare / samples.length);
    return energy >= 250.0;
  }

  void dispose() {
    _session?.close();
    _session = null;
  }
}

class _RawSpeechRange {
  _RawSpeechRange({
    required this.start,
    required this.end,
    required this.chunks,
  });
  final Duration start;
  Duration end;
  final List<PcmChunk> chunks;
}

```

## lib/features/audio/domain/entities/audio_stream_info.dart
```dart:lib/features/audio/domain/entities/audio_stream_info.dart
class AudioStreamInfo {
  const AudioStreamInfo({
    required this.sampleRate,
    required this.channels,
    required this.codec,
    required this.duration,
  });

  final int sampleRate;
  final int channels;
  final String codec;
  final Duration duration;
}

```

