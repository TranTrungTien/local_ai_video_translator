import 'dart:typed_data';

import '../domain/ai_pipeline.dart';
import '../../settings/data/model_manager_repository.dart';
import 'tts_cache.dart';

class LocalTextToSpeechEngine implements TextToSpeechEngine {
  LocalTextToSpeechEngine(this._modelRepository, [TtsCache? cache])
    : _cache = cache ?? TtsCache();

  final ModelManagerRepository _modelRepository;
  final TtsCache _cache;

  static const String modelId = 'tts_piper_vi_female';

  TtsCache get cache => _cache;

  @override
  bool get installed => true;

  Future<bool> isModelReady() async {
    return _modelRepository.isModelDownloaded(modelId);
  }

  @override
  Future<List<int>> synthesize(
    String text, {
    required Duration targetDuration,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return const [];

    // Check independent TTS chunk cache first (reused on backward seek)
    final cached = _cache.get(cleanText);
    if (cached != null) {
      return cached;
    }

    const sampleRate = 16000;
    const channels = 1;

    // Duration fitting: ensure generated speech duration fits target duration safely
    var targetMs = targetDuration.inMilliseconds;
    if (targetMs < 500) targetMs = 500; // minimum speech window

    final samplesNeeded = (sampleRate * targetMs) ~/ 1000;
    final byteCount = samplesNeeded * 2 * channels;

    final bytes = Uint8List(byteCount);
    // Fill mock audio PCM bytes for synthesis
    for (var i = 0; i < bytes.length; i += 2) {
      bytes[i] = 100;
      bytes[i + 1] = 0;
    }

    final audioList = bytes.toList();
    _cache.put(cleanText, audioList);
    return audioList;
  }
}
