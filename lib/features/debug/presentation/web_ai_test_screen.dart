import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/data/model_manager_repository.dart';
import '../../pipeline/data/local_stt_engine.dart';
import '../../pipeline/domain/ai_pipeline.dart';
import '../../../core/diagnostics/diagnostics_service.dart';

class WebAiTestScreen extends ConsumerStatefulWidget {
  const WebAiTestScreen({super.key});

  @override
  ConsumerState<WebAiTestScreen> createState() => _WebAiTestScreenState();
}

class _WebAiTestScreenState extends ConsumerState<WebAiTestScreen> {
  String status = 'Idle';
  List<String> logs = [];

  void _addLog(String msg) {
    setState(() {
      logs.insert(0, msg);
      status = msg;
    });
    debugPrint(msg);
  }

  Future<void> _startTest() async {
    final repo = ref.read(modelManagerRepositoryProvider);
    final diagnostics = ref.read(diagnosticsServiceProvider);
    final stt = LocalSpeechToTextEngine(repo, diagnostics);

    try {
      _addLog('Checking models in Cache Storage...');
      final isDownloaded = await repo.isModelDownloaded('stt_whisper_base_en_vi');

      if (!isDownloaded) {
        _addLog('Downloading models (80MB)... This may take a minute.');
        final manifest = repo.manifestById('stt_whisper_base_en_vi');
        if (manifest != null) {
          await repo.downloadModel(manifest);
        }
      }

      _addLog('Initializing ONNX Runtime sessions...');
      // Dummy PCM: 1 second of silence
      final dummyPcm = Uint8List(16000 * 2);
      final stream = Stream.value(PcmChunk(
        pts: Duration.zero,
        sampleRate: 16000,
        channels: 1,
        bytes: dummyPcm,
      ));

      _addLog('Running Inference (Whisper Base)...');
      final results = await stt.transcribe(stream);

      _addLog('Test Complete! Results: ${results.length} segments.');
      for (var res in results) {
        _addLog('>> [${res.start.inMilliseconds}ms]: ${res.text}');
      }
    } catch (e) {
      _addLog('FATAL ERROR: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Web AI Debugger')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _startTest,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Run End-to-End STT Test'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      logs[i],
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
