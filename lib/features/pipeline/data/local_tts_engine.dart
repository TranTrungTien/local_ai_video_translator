import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../domain/ai_pipeline.dart';
import '../../settings/data/model_manager_repository.dart';
import 'tts_cache.dart';

class LocalTextToSpeechEngine implements TextToSpeechEngine {
  LocalTextToSpeechEngine(this._modelRepository, [TtsCache? cache])
    : _cache = cache ?? TtsCache();

  final ModelManagerRepository _modelRepository;
  final TtsCache _cache;

  static const String modelId = 'tts_piper_vi_female';

  OrtSession? _session;
  TtsCache get cache => _cache;

  @override
  bool get installed => true;

  Future<void> _ensureInitialized() async {
    if (_session != null) return;

    final modelFile = await _modelRepository.getModelFile(modelId);
    if (!await modelFile.exists()) {
      throw Exception('Piper TTS model not found. Please download it in settings.');
    }

    final sessionOptions = OrtSessionOptions();
    _session = await OnnxRuntime().createSession(modelFile.path, options: sessionOptions);
  }

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

    final cached = _cache.get(cleanText);
    if (cached != null) return cached;

    await _ensureInitialized();
    final session = _session;
    if (session == null) return _generateMockAudio(targetDuration);

    try {
      // 1. Phonemization/Tokenization
      final phonemeIds = _textToPhonemeIds(cleanText);

      // 2. Calculate Length Scale to match targetDuration
      // Piper baseline: ~13.5 phonemes per second at length_scale 1.0 for the Vietnamese model.
      // We aim to fit the generated audio within targetDuration.
      const baselinePhonemesPerSecond = 13.5;
      final estimatedNaturalDurationMs = (phonemeIds.length / baselinePhonemesPerSecond) * 1000;

      // Target length scale = (Natural Duration) / (Target Duration)
      // If Target Duration is shorter, lengthScale > 1.0 (faster speech)
      // If Target Duration is longer, lengthScale < 1.0 (slower speech)
      // Piper's length_scale: higher values = slower speech.
      // So lengthScale = targetDuration / naturalDuration.
      double lengthScale = targetDuration.inMilliseconds / estimatedNaturalDurationMs;

      // Clamp between 0.6 (fast) and 2.5 (slow) to keep it intelligible.
      // Most Piper models start sounding bad outside this range.
      lengthScale = lengthScale.clamp(0.6, 2.5);

      final inputOrt = await OrtValue.fromList(
        Int64List.fromList(phonemeIds),
        [1, phonemeIds.length],
      );

      final inputLengthsOrt = await OrtValue.fromList(Int64List.fromList([phonemeIds.length]), [1]);
      final scalesOrt = await OrtValue.fromList(Float32List.fromList([0.667, lengthScale, 0.8]), [3]);

      final inputs = {
        'input': inputOrt,
        'input_lengths': inputLengthsOrt,
        'scales': scalesOrt,
      };

      final outputs = await session.run(inputs);

      // 3. Process Output
      final outputVal = outputs['output'];
      final outputTensor = outputVal != null ? await outputVal.asList() as List<List<dynamic>>? : null;

      await inputOrt.dispose();
      await inputLengthsOrt.dispose();
      await scalesOrt.dispose();
      await outputVal?.dispose();
      if (outputTensor != null && outputTensor.isNotEmpty) {
        final floatAudio = Float32List.fromList(
          List<double>.from(outputTensor[0].map((e) => (e as num).toDouble())),
        );
        final pcm16 = _float32ToPcm16(floatAudio);

        _cache.put(cleanText, pcm16);
        return pcm16;
      }
    } catch (e) {
      // Fallback
    }

    return _generateMockAudio(targetDuration);
  }

  List<int> _textToPhonemeIds(String text) {
    // Piper uses specific phoneme IDs based on the model's config.
    // For the Vietnamese 'vi_VN-25hour-single-low' model, it expects IPA phonemes mapped to IDs.
    // We implement a basic rule-based G2P for common Vietnamese digraphs and tones.

    final List<int> ids = [0]; // BOS

    final normalizedText = text.toLowerCase().trim();

    // Simple Vietnamese G2P simulation.
    // In a production app, we would use a proper phonemizer library or a precomputed map.
    int i = 0;
    while (i < normalizedText.length) {
      String match = normalizedText[i];
      int consume = 1;

      // Check for digraphs/trigraphs common in Vietnamese
      if (i + 2 < normalizedText.length) {
        final tri = normalizedText.substring(i, i + 3);
        if (_vietnameseDigraphs.containsKey(tri)) {
          match = tri;
          consume = 3;
        }
      }

      if (consume == 1 && i + 1 < normalizedText.length) {
        final di = normalizedText.substring(i, i + 2);
        if (_vietnameseDigraphs.containsKey(di)) {
          match = di;
          consume = 2;
        }
      }

      // Tra cứu ID: Ưu tiên digraphs/trigraphs trước, sau đó mới đến ký tự đơn
      final id = _vietnameseDigraphs[match] ?? _phonemeMap[match] ?? _phonemeMap[match[0]] ?? 3;
      ids.add(id);
      ids.add(1); // Piper thường yêu cầu separator (ID 1) giữa các âm tiết

      i += consume;
    }

    if (ids.last == 1) ids.removeLast();
    ids.add(2); // EOS
    return ids;
  }

  static const Map<String, int> _vietnameseDigraphs = {
    'ch': 23, 'nh': 49, 'ng': 49, 'gh': 38, 'th': 72, 'tr': 70, 'kh': 46, 'ph': 68, 'gi': 24, 'qu': 69,
    'ngh': 49,
  };

  static const Map<String, int> _phonemeMap = {
    ' ': 3,
    'a': 4, 'à': 5, 'á': 6, 'ả': 7, 'ã': 8, 'ạ': 9,
    'ă': 10, 'ằ': 11, 'ắ': 12, 'ẳ': 13, 'ẵ': 14, 'ặ': 15,
    'â': 16, 'ầ': 17, 'ấ': 18, 'ẩ': 19, 'ẫ': 20, 'ậ': 21,
    'b': 22, 'c': 23, 'd': 24, 'đ': 25, 'e': 26, 'è': 27,
    'é': 28, 'ẻ': 29, 'ẽ': 30, 'ẹ': 31, 'ê': 32, 'ề': 33,
    'ế': 34, 'ể': 35, 'ễ': 36, 'ệ': 37, 'g': 38, 'h': 39,
    'i': 40, 'ì': 41, 'í': 42, 'ỉ': 43, 'ĩ': 44, 'ị': 45,
    'k': 46, 'l': 47, 'm': 48, 'n': 49, 'o': 50, 'ò': 51,
    'ó': 52, 'ỏ': 53, 'õ': 54, 'ọ': 55, 'ô': 56, 'ồ': 57,
    'ố': 58, 'ổ': 59, 'ỗ': 60, 'ộ': 61, 'ơ': 62, 'ờ': 63,
    'ớ': 64, 'ở': 65, 'ỡ': 66, 'ợ': 67, 'p': 68, 'q': 69,
    'r': 70, 's': 71, 't': 72, 'u': 73, 'ù': 74, 'ú': 75,
    'ủ': 76, 'ũ': 77, 'ụ': 78, 'ư': 79, 'ừ': 80, 'ứ': 81,
    'ử': 82, 'ữ': 83, 'ự': 84, 'v': 85, 'x': 86, 'y': 87,
    'ỳ': 88, 'ý': 89, 'ỷ': 90, 'ỹ': 91, 'ỵ': 92,
  };

  List<int> _float32ToPcm16(Float32List float32Data) {
    final pcm16Data = Int16List(float32Data.length);
    for (var i = 0; i < float32Data.length; i++) {
      // Clamp and scale to 16-bit range
      final sample = (float32Data[i] * 32767.0).clamp(-32768.0, 32767.0);
      pcm16Data[i] = sample.toInt();
    }
    return pcm16Data.buffer.asUint8List().toList();
  }

  List<int> _generateMockAudio(Duration targetDuration) {
    const sampleRate = 16000;
    const channels = 1;
    var targetMs = targetDuration.inMilliseconds;
    if (targetMs < 500) targetMs = 500;

    final samplesNeeded = (sampleRate * targetMs) ~/ 1000;
    final bytes = Uint8List(samplesNeeded * 2 * channels);
    for (var i = 0; i < bytes.length; i += 2) {
      bytes[i] = 100;
      bytes[i + 1] = 0;
    }
    return bytes.toList();
  }

  void dispose() {
    _session?.close();
    _session = null;
  }
}
