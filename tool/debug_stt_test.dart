
import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

import 'package:local_ai_video_translator/features/audio/data/vad_engine.dart';
import 'package:local_ai_video_translator/features/pipeline/data/local_stt_engine.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/ai_pipeline.dart';
import 'package:local_ai_video_translator/core/diagnostics/diagnostics_service.dart';
import 'package:local_ai_video_translator/features/settings/data/model_manager_repository.dart';
import 'package:local_ai_video_translator/core/utils/cancellation_token.dart';

class CliDiagnostics implements DiagnosticsService {
  @override
  void log(String tag, String message, {LogLevel level = LogLevel.info, Object? details}) {
    final timestamp = DateTime.now().toIso8601String().split('T').last;
    print('[$timestamp] [$tag] [${level.name.toUpperCase()}] $message');
    if (details != null) print('  Details: $details');
  }

  @override
  void clear() {}

  @override
  void dispose() {}

  @override
  List<DiagnosticEntry> get logs => [];

  @override
  Stream<DiagnosticEntry> get stream => const Stream.empty();
}

class LocalFileSystemRepo implements ModelManagerRepository {
  final String baseDir;
  LocalFileSystemRepo(this.baseDir);

  @override
  Future<io.File> getModelFile(String modelId, String fileName) async {
    final file = io.File(p.join(baseDir, modelId, fileName));
    if (!await file.exists()) {
      throw Exception('Model file missing: ${file.path}');
    }
    return file;
  }

  @override
  Future<io.Directory> getModelDir(String modelId) async => io.Directory(p.join(baseDir, modelId));

  @override
  Future<Uint8List?> getModelFileBytes(String modelId, String fileName) async {
    final file = await getModelFile(modelId, fileName);
    return await file.readAsBytes();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Transcription Debug', () async {
    final String videoPath = 'test.mp4';
    final String modelDir = p.join(io.Directory.current.path, 'ai_models');

    print('\x1B[36m=== LOCAL AI DEBUGGER (via flutter test) ===\x1B[0m');

    final diagnostics = CliDiagnostics();
    final repo = LocalFileSystemRepo(modelDir);

    print('Step 1: Extracting Audio...');
    final tempPcm = io.File('debug_input.pcm');
    const audioFilters = 'pan=mono|c0=0.5*c0+0.5*c1,highpass=f=80,lowpass=f=7500,afftdn=nf=-25';

    // Try to find ffmpeg
    String ffmpegPath = 'ffmpeg';
    final commonPaths = [
      'D:\\trans\\ffmpeg\\ffmpeg.exe',
      'D:\\Ultimate Vocal Remover\\ffmpeg.exe',
      'C:\\ProgramData\\chocolatey\\bin\\ffmpeg.exe',
    ];

    for (final path in commonPaths) {
      if (io.File(path).existsSync()) {
        ffmpegPath = path;
        break;
      }
    }

    print('Using ffmpeg from: $ffmpegPath');

    final process = await io.Process.run(ffmpegPath, [
      '-y',
      '-i', videoPath,
      '-vn',
      '-af', audioFilters,
      '-ar', '16000',
      '-ac', '1',
      '-f', 's16le',
      '-acodec', 'pcm_s16le',
      tempPcm.path,
    ]);

    if (process.exitCode != 0) {
      print('FFmpeg Error: ${process.stderr}');
      return;
    }

    final vad = LocalVadEngine(repo, diagnostics);
    final stt = LocalSpeechToTextEngine(repo, diagnostics);

    print('Step 2: Voice Activity Detection...');
    final pcmStream = _createPcmStream(tempPcm);

    final List<SpeechSegment> speechSegments = [];
    try {
      await for (final segment in vad.detectSpeech(pcmStream)) {
        speechSegments.add(segment);
        print('  [VAD] Speech detected: ${segment.start.inSeconds}s -> ${segment.end.inSeconds}s');
      }
    } catch (e) {
      print('\x1B[31m[VAD] Error: $e\x1B[0m');
    }

    print('Step 3: Transcribing ${speechSegments.length} segments...');
    final srtOutput = io.File(p.setExtension(videoPath, '.srt'));
    final srtSink = srtOutput.openWrite();

    for (int i = 0; i < speechSegments.length; i++) {
      final segment = speechSegments[i];
      final chunkStream = Stream.fromIterable(segment.chunks);

      try {
        final results = await stt.transcribeWithCancellation(
          chunkStream,
          cancellationToken: CancellationToken(),
        );

        if (results.isNotEmpty) {
          final text = results.first.text;
          print('\x1B[32m[${i+1}] ${_formatDuration(segment.start)}: $text\x1B[0m');
          _writeSrtEntry(srtSink, i + 1, segment.start, segment.end, text);
        }
      } catch (e) {
        print('STT Error at segment $i: $e');
      }
    }

    await srtSink.close();
    print('\x1B[36m=== FINISHED: ${srtOutput.path} ===\x1B[0m');
    if (tempPcm.existsSync()) await tempPcm.delete();
  }, timeout: const Timeout(Duration(minutes: 30)));
}

Stream<PcmChunk> _createPcmStream(io.File file) async* {
  final raf = await file.open();
  const int sampleRate = 16000;
  final int bytesPerChunk = (sampleRate * 2 * 0.5).toInt();
  int offset = 0;

  try {
    while (true) {
      final bytes = await raf.read(bytesPerChunk);
      if (bytes.isEmpty) break;
      yield PcmChunk(
        pts: Duration(milliseconds: (offset / (sampleRate * 2) * 1000).toInt()),
        sampleRate: sampleRate,
        channels: 1,
        bytes: bytes,
      );
      offset += bytes.length;
    }
  } finally {
    await raf.close();
  }
}

void _writeSrtEntry(io.IOSink sink, int index, Duration start, Duration end, String text) {
  sink.writeln('$index');
  sink.writeln('${_formatDuration(start)} --> ${_formatDuration(end)}');
  sink.writeln(text);
  sink.writeln();
}

String _formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  String three(int n) => n.toString().padLeft(3, '0');
  return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))},${three(d.inMilliseconds.remainder(1000))}';
}
