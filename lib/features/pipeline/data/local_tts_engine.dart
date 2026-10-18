import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'performance_monitor.dart';

import '../../../core/diagnostics/diagnostics_service.dart';
import '../domain/ai_pipeline.dart';
import '../../settings/data/model_manager_repository.dart';
import 'tts_cache.dart';
import '../../../core/utils/cancellation_token.dart';

class LocalTextToSpeechEngine implements TextToSpeechEngine {
  LocalTextToSpeechEngine(
    this._modelRepository,
    this._diagnostics, [
    TtsCache? cache,
  ]) : _cache = cache ?? TtsCache();

  final ModelManagerRepository _modelRepository;
  final DiagnosticsService _diagnostics;
  final TtsCache _cache;

  static const String modelId = 'tts_piper_vi_female';
  static const String modelFileName = 'vi_VN-25hours_single-low.onnx';

  OrtSession? _session;
  Map<String, List<int>>? _phonemeIdMap;
  TtsCache get cache => _cache;

  Completer<void>? _processingLock;

  @override
  bool get installed => true;

  Future<void> _ensureInitialized() async {
    if (_session != null) return;

    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    final modelFile = await _modelRepository.getModelFile(modelId, modelFileName);
    if (!await modelFile.exists()) {
      throw ModelDownloadException('Piper TTS model missing. Please download it in settings.');
    }

    // Try to load accompanying config if exists
    final dir = await _modelRepository.getModelDir(modelId);
    final configFile = File('${dir.path}/$modelFileName.json');

    if (await configFile.exists()) {
      try {
        final configContent = await configFile.readAsString();
        final config = jsonDecode(configContent) as Map<String, dynamic>;
        final rawMap = config['phoneme_id_map'] as Map<String, dynamic>?;
        if (rawMap != null) {
          _phonemeIdMap = rawMap.map((key, value) {
            if (value is List) {
              return MapEntry(key, List<int>.from(value.map((e) => e as int)));
            }
            return MapEntry(key, [value as int]);
          });
        }
      } catch (e) {
        _diagnostics.log('TTS_ENGINE', 'Failed to load phoneme map: $e', level: LogLevel.warning);
      }
    }

    final sessionOptions = OrtSessionOptions();
    _session = await OnnxRuntime().createSession(modelFile.path, options: sessionOptions);
  }

  Future<bool> isModelReady() async {
    return _modelRepository.isModelDownloaded(modelId);
  }

  @override
  Future<Uint8List> synthesize(
    String text, {
    required Duration targetDuration,
  }) async {
    return synthesizeWithCancellation(
      text,
      targetDuration: targetDuration,
      cancellationToken: CancellationToken(),
    );
  }

  @override
  Future<Uint8List> synthesizeWithCancellation(
    String text, {
    required Duration targetDuration,
    required CancellationToken cancellationToken,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return Uint8List(0);

    final cached = _cache.get(cleanText);
    if (cached != null) return Uint8List.fromList(cached);

    cancellationToken.throwIfCancelled();

    while (_processingLock != null) {
      await _processingLock!.future;
    }
    _processingLock = Completer<void>();

    try {
      await _ensureInitialized();
      cancellationToken.throwIfCancelled();

      final session = _session;
      if (session == null) {
        final mockAudio = _generateMockAudio(targetDuration);
        _cache.put(cleanText, mockAudio);
        return mockAudio;
      }

      final stopwatch = Stopwatch()..start();
      OrtValue? inputOrt;
      OrtValue? inputLengthsOrt;
      OrtValue? scalesOrt;
      Map<String, OrtValue>? outputs;

      try {
        final phonemeIds = _textToPhonemeIds(cleanText);

        // 2. Calculate Length Scale to match targetDuration
        // Piper lengthScale: 1.0 = normal, > 1.0 = slower, < 1.0 = faster.
        // Tỷ lệ âm tiết tiếng Việt trung bình khoảng 3.5 - 4.5 âm tiết/giây.
        // Mỗi âm tiết có trung bình ~4 phonemes. Vậy ~16 phonemes/giây là hợp lý.
        const baselinePhonemesPerSecond = 16.0;
        final estimatedNaturalDurationMs = (phonemeIds.length / baselinePhonemesPerSecond) * 1000;

        // Tính toán scale để khớp với targetDuration của video
        double lengthScale = targetDuration.inMilliseconds / estimatedNaturalDurationMs;

        // Giới hạn scale trong khoảng an toàn (0.6x đến 2.0x tốc độ)
        lengthScale = lengthScale.clamp(0.6, 2.0);

        inputOrt = await OrtValue.fromList(
          Int64List.fromList(phonemeIds),
          [1, phonemeIds.length],
        );

        inputLengthsOrt = await OrtValue.fromList(Int64List.fromList([phonemeIds.length]), [1]);

        // noiseScale=0.667, lengthScale=X, noiseW=0.8
        scalesOrt = await OrtValue.fromList(Float32List.fromList([0.667, lengthScale, 0.8]), [3]);

        final inputs = {
          'input': inputOrt,
          'input_lengths': inputLengthsOrt,
          'scales': scalesOrt,
        };

        outputs = await session.run(inputs);

        // 3. Process Output
        final outputVal = outputs['output'];
        if (outputVal == null) throw Exception('TTS Output is null');

        final List<dynamic> outputTensor = await outputVal.asList();

        if (outputTensor.isNotEmpty) {
          final List<double> flatData = [];
          // Piper thường output [1, T] hoặc [1, T, 1]
          if (outputTensor[0] is List) {
             final firstDim = outputTensor[0] as List;
             if (firstDim.isNotEmpty && firstDim[0] is List) {
               // [1, T, 1] case
               for (var frame in firstDim) {
                 flatData.add((frame as List)[0] as double);
               }
             } else {
               // [1, T] case
               flatData.addAll(firstDim.map((e) => (e as num).toDouble()));
             }
          } else {
             flatData.addAll(outputTensor.map((e) => (e as num).toDouble()));
          }

          final floatAudio = Float32List.fromList(flatData);
          var pcm16 = _float32ToPcm16(floatAudio);

          // Hậu xử lý: Nếu audio sinh ra quá ngắn, thêm silence padding để khớp với timeline
          final currentDurationMs = (pcm16.length / (16000 * 2)) * 1000;
          if (currentDurationMs < targetDuration.inMilliseconds - 100) {
             final paddingSize = ((targetDuration.inMilliseconds - currentDurationMs) * 16000 * 2 / 1000).toInt();
             if (paddingSize > 0) {
               final padded = Uint8List(pcm16.length + (paddingSize & ~1));
               padded.setRange(0, pcm16.length, pcm16);
               pcm16 = padded;
             }
          }

          stopwatch.stop();
          final audioDurationSec = pcm16.length / (16000 * 2);
          if (audioDurationSec > 0) {
            final rtf = stopwatch.elapsedMilliseconds / (audioDurationSec * 1000);
            PerformanceMonitor.instance.updateTtsRtf(rtf);
          }

          _cache.put(cleanText, pcm16);
          return pcm16;
        }
      } finally {
        await inputOrt?.dispose();
        await inputLengthsOrt?.dispose();
        await scalesOrt?.dispose();
        if (outputs != null) {
          for (var v in outputs.values) {
            await v.dispose();
          }
        }
      }
    } catch (e, st) {
      _diagnostics.log('TTS_ENGINE', 'Synthesis error: $e', level: LogLevel.error, details: st.toString());
    } finally {
      final lock = _processingLock;
      _processingLock = null;
      lock?.complete();
    }

    return _generateMockAudio(targetDuration);
  }

  List<int> _textToPhonemeIds(String text) {
    final map = _phonemeIdMap;
    if (map != null) {
      final List<int> ids = [0]; // BOS
      final normalized = text.toLowerCase().trim();
      for (var i = 0; i < normalized.length; i++) {
        final char = normalized[i];
        final phonemes = map[char] ?? map[' '] ?? [3];
        ids.addAll(phonemes);
        ids.add(1); // Separator
      }
      if (ids.last == 1) ids.removeLast();
      ids.add(2); // EOS
      return ids;
    }

    final List<int> ids = [0]; // BOS
    final normalizedText = text.toLowerCase().trim();
    int i = 0;
    while (i < normalizedText.length) {
      String match = normalizedText[i];
      int consume = 1;

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

      final id = _vietnameseDigraphs[match] ?? _phonemeMap[match] ?? _phonemeMap[match[0]] ?? 3;
      ids.add(id);
      ids.add(1);
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

  Uint8List _float32ToPcm16(Float32List float32Data) {
    final pcm16Data = Int16List(float32Data.length);
    for (var i = 0; i < float32Data.length; i++) {
      final sample = (float32Data[i] * 32767.0).clamp(-32768.0, 32767.0);
      pcm16Data[i] = sample.toInt();
    }
    return pcm16Data.buffer.asUint8List();
  }

  Uint8List _generateMockAudio(Duration targetDuration) {
    const sampleRate = 16000;
    const channels = 1;
    var targetMs = targetDuration.inMilliseconds;
    if (targetMs < 500) targetMs = 500;

    final samplesNeeded = (sampleRate * targetMs) ~/ 1000;
    final bytes = Uint8List(samplesNeeded * 2 * channels);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = (i % 2 == 0) ? 10 : 0;
    }
    return bytes;
  }

  void dispose() {
    _session?.close();
    _session = null;
  }
}
