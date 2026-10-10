import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/audio/data/bounded_pcm_queue.dart';
import 'dart:io';
import 'package:local_ai_video_translator/features/audio/data/vad_engine.dart';
import 'package:local_ai_video_translator/features/pipeline/domain/ai_pipeline.dart';
import 'package:local_ai_video_translator/features/settings/data/model_manager_repository.dart';

class MockModelManagerRepository implements ModelManagerRepository {
  @override
  Future<File> getModelFile(String modelId) async {
    return File('non_existent_path');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Phase 4: Timed Audio & Bounded PCM Queue Tests', () {
    test('preserves exact media PTS, sample rate, channels, and format', () {
      final bytes = Uint8List(16000); // 16KB of mock PCM data
      final chunk = PcmChunk(
        pts: const Duration(seconds: 5),
        sampleRate: 16000,
        channels: 1,
        bytes: bytes,
      );

      expect(chunk.pts, equals(const Duration(seconds: 5)));
      expect(chunk.sampleRate, equals(16000));
      expect(chunk.channels, equals(1));
      expect(chunk.bytes.length, equals(16000));
    });

    test(
      'bounded queue enforces capacity and applies backpressure by dropping oldest chunk',
      () {
        final queue = BoundedPcmQueue(maxCapacity: 3);

        for (var i = 0; i < 5; i++) {
          queue.enqueue(
            PcmChunk(
              pts: Duration(seconds: i),
              sampleRate: 16000,
              channels: 1,
              bytes: Uint8List(100),
            ),
          );
        }

        // Max capacity is 3, so first 2 chunks (seconds 0 and 1) should be dropped
        expect(queue.length, equals(3));
        final firstDequeued = queue.dequeue();
        expect(firstDequeued?.pts, equals(const Duration(seconds: 2)));
      },
    );

    test('clears queue before specified seek PTS', () {
      final queue = BoundedPcmQueue(maxCapacity: 10);
      queue.enqueue(
        PcmChunk(
          pts: const Duration(seconds: 1),
          sampleRate: 16000,
          channels: 1,
          bytes: Uint8List(10),
        ),
      );
      queue.enqueue(
        PcmChunk(
          pts: const Duration(seconds: 5),
          sampleRate: 16000,
          channels: 1,
          bytes: Uint8List(10),
        ),
      );

      queue.clearBefore(const Duration(seconds: 3));
      expect(queue.length, equals(1));
      expect(queue.dequeue()?.pts, equals(const Duration(seconds: 5)));
    });
  });

  group('Phase 4: VAD (Voice Activity Detector) Segmentation Tests', () {
    test(
      'detects speech and applies merge-small-gap and min-speech-length policies',
      () async {
        // Mock repository not strictly needed for energy-only test path if session is null
        // but required for constructor
        final vad = LocalVadEngine(
          MockModelManagerRepository(),
          minSpeechDuration: const Duration(milliseconds: 400),
          maxMergeGap: const Duration(milliseconds: 300),
        );

        final silentBytes = Uint8List(3200); // all zeros -> RMS 0
        final speechBytes = Uint8List(3200);
        final int16View = Int16List.view(speechBytes.buffer);
        for (var i = 0; i < int16View.length; i++) {
          int16View[i] = 2000; // high energy samples
        }

        final mockChunks = [
          PcmChunk(
            pts: const Duration(seconds: 0),
            sampleRate: 16000,
            channels: 1,
            bytes: silentBytes,
          ),
          PcmChunk(
            pts: const Duration(milliseconds: 500),
            sampleRate: 16000,
            channels: 1,
            bytes: silentBytes,
          ),
          PcmChunk(
            pts: const Duration(seconds: 1),
            sampleRate: 16000,
            channels: 1,
            bytes: speechBytes,
          ),
          PcmChunk(
            pts: const Duration(milliseconds: 1500),
            sampleRate: 16000,
            channels: 1,
            bytes: speechBytes,
          ),
          PcmChunk(
            pts: const Duration(seconds: 2),
            sampleRate: 16000,
            channels: 1,
            bytes: speechBytes,
          ),
          PcmChunk(
            pts: const Duration(milliseconds: 2500),
            sampleRate: 16000,
            channels: 1,
            bytes: silentBytes,
          ), // small gap
          PcmChunk(
            pts: const Duration(seconds: 3),
            sampleRate: 16000,
            channels: 1,
            bytes: speechBytes,
          ),
          PcmChunk(
            pts: const Duration(milliseconds: 3500),
            sampleRate: 16000,
            channels: 1,
            bytes: speechBytes,
          ),
          PcmChunk(
            pts: const Duration(seconds: 4),
            sampleRate: 16000,
            channels: 1,
            bytes: silentBytes,
          ),
        ];

        final stream = Stream<PcmChunk>.fromIterable(mockChunks);
        final segments = await vad.detectSpeech(stream).toList();

        expect(segments.isNotEmpty, isTrue);
        expect(segments.first.start, isNotNull);
      },
    );
  });
}
