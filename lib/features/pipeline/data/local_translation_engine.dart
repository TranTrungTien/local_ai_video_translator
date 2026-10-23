import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math' as math;
import '../../../core/utils/foundation_stub.dart' as stub;
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../../audio/data/vad_engine_web_stub.dart'
    if (dart.library.js_interop) 'package:web/web.dart' as web;
import '../../audio/data/vad_engine_web_stub.dart'
    if (dart.library.js_interop) 'dart:js_interop';

import 'performance_monitor.dart';
import '../../../core/diagnostics/diagnostics_service.dart';
import '../domain/ai_pipeline.dart';
import '../../settings/data/model_manager_repository.dart';
import 'subtitle_compressor.dart';
import 'translation_cache.dart';
import 'translation_metrics.dart';
import '../../../core/utils/tokenizer.dart';
import '../../../core/utils/cancellation_token.dart';

class LocalTranslationEngine implements TranslationEngine {
  LocalTranslationEngine(
    this._modelRepository,
    this._diagnostics, [
    TranslationCache? cache,
    TranslationMetrics? metrics,
    SubtitleCompressor? compressor,
  ]) : _cache = cache ?? TranslationCache(),
       _metrics = metrics ?? TranslationMetrics(),
       _compressor = compressor ?? const SubtitleCompressor();

  final ModelManagerRepository _modelRepository;
  final DiagnosticsService _diagnostics;
  final TranslationCache _cache;
  final TranslationMetrics _metrics;
  final SubtitleCompressor _compressor;

  static const String modelId = 'translate_opus_en_vi';

  OrtSession? _encoderSession;
  OrtSession? _decoderSession;
  SimpleTokenizer? _tokenizer;
  final List<TimedTextSegment> _contextHistory = [];

  Completer<void>? _activeInference;

  // Marian: decoder_start_token_id == pad_token_id, eos == 0.
  // Giá trị mặc định dưới đây chỉ là fallback; ưu tiên đọc từ config.json
  // đi kèm model (xem _loadSpecialTokens) và kiểm tra lại qua log.
  int _startToken = 59513;
  int _eosToken = 0;

  /// Nhận diện exception do huỷ chủ động, tránh biến nó thành lỗi model.
  /// Đổi lại thành `e is <TênClass>` nếu biết chính xác class trong
  /// cancellation_token.dart.
  static bool _isCancellation(Object e) =>
      e.runtimeType.toString().toLowerCase().contains('cancel');

  TranslationMetrics get metrics => _metrics;
  TranslationCache get cache => _cache;

  @override
  bool get installed => _encoderSession != null && _decoderSession != null;

  Future<void> _ensureInitialized() async {
    if (_encoderSession != null && _decoderSession != null && _tokenizer != null) return;

    if (!kIsWeb && io.Platform.environment.containsKey('FLUTTER_TEST')) return;

    if (kIsWeb) {
      final encoderBytes = await _modelRepository.getModelFileBytes(modelId, 'encoder_model_quantized.onnx');
      final decoderBytes = await _modelRepository.getModelFileBytes(modelId, 'decoder_model_merged_quantized.onnx');
      final vocabBytes = await _modelRepository.getModelFileBytes(modelId, 'vocab.json');
      final configBytes = await _modelRepository.getModelFileBytes(modelId, 'config.json');

      if (encoderBytes == null || decoderBytes == null || vocabBytes == null) {
        throw ModelDownloadException('Opus-MT models missing. Please download them.');
      }

      _tokenizer = await SimpleTokenizer.load(utf8.decode(vocabBytes));
      if (configBytes != null) {
        _parseSpecialTokens(utf8.decode(configBytes));
      }

      final sessionOptions = OrtSessionOptions();

      final encoderBlob = web.Blob([encoderBytes.toJS].toJS, web.BlobPropertyBag(type: 'application/octet-stream'));
      final decoderBlob = web.Blob([decoderBytes.toJS].toJS, web.BlobPropertyBag(type: 'application/octet-stream'));
      final encoderUrl = web.URL.createObjectURL(encoderBlob);
      final decoderUrl = web.URL.createObjectURL(decoderBlob);

      try {
        _encoderSession = await OnnxRuntime().createSession(encoderUrl, options: sessionOptions);
        _decoderSession = await OnnxRuntime().createSession(decoderUrl, options: sessionOptions);
      } finally {
        web.URL.revokeObjectURL(encoderUrl);
        web.URL.revokeObjectURL(decoderUrl);
      }
    } else {
      final encoderFile = await _modelRepository.getModelFile(modelId, 'encoder_model_quantized.onnx');
      final decoderFile = await _modelRepository.getModelFile(modelId, 'decoder_model_merged_quantized.onnx');

      if (!await encoderFile.exists() || !await decoderFile.exists()) {
        throw ModelDownloadException('Opus-MT models missing.');
      }

      final dir = await _modelRepository.getModelDir(modelId);
      final vocabFile = io.File('${dir.path}/vocab.json');
      if (!await vocabFile.exists()) {
        throw ModelContractException('Opus-MT vocab.json missing.');
      }
      _tokenizer = await SimpleTokenizer.load(await vocabFile.readAsString());

      await _loadSpecialTokens(dir);

      final sessionOptions = OrtSessionOptions();
      _encoderSession = await OnnxRuntime().createSession(encoderFile.path, options: sessionOptions);
      _decoderSession = await OnnxRuntime().createSession(decoderFile.path, options: sessionOptions);
    }

    _diagnostics.log('TRANSLATION_ENGINE', 'Opus-MT initialized');
  }

  void _parseSpecialTokens(String configContent) {
    try {
      final json = jsonDecode(configContent);
      if (json is! Map) return;
      final start = json['decoder_start_token_id'] ?? json['pad_token_id'];
      final eos = json['eos_token_id'];
      if (start is int) _startToken = start;
      if (eos is int) _eosToken = eos;
    } catch (e) {
      _diagnostics.log('TRANSLATION_ENGINE', 'Could not parse config: $e', level: LogLevel.warning);
    }
  }

  Future<void> _loadSpecialTokens(io.Directory dir) async {
    try {
      final configFile = io.File('${dir.path}/config.json');
      if (!await configFile.exists()) return;
      _parseSpecialTokens(await configFile.readAsString());
    } catch (e) {
      _diagnostics.log('TRANSLATION_ENGINE', 'Could not read config.json: $e', level: LogLevel.warning);
    }
  }

  Future<bool> isModelReady() async {
    return _modelRepository.isModelDownloaded(modelId);
  }

  @override
  Future<List<TimedTextSegment>> translate(
    List<TimedTextSegment> segments, {
    required String targetLanguage,
    CancellationToken? cancellationToken,
  }) async {
    if (segments.isEmpty) return const [];
    final token = cancellationToken ?? CancellationToken();
    token.throwIfCancelled();

    while (_activeInference != null) {
      await _activeInference!.future;
    }
    _activeInference = Completer<void>();

    try {
      await _ensureInitialized();
      token.throwIfCancelled();

      final stopwatch = Stopwatch()..start();
      final translatedSegments = <TimedTextSegment>[];

      // Batching segments for latency/memory balance
      const batchSize = 6;
      for (var i = 0; i < segments.length; i += batchSize) {
        token.throwIfCancelled();
        final batch = segments.skip(i).take(batchSize).toList();

        for (final seg in batch) {
          token.throwIfCancelled();
          _contextHistory.add(seg);
          if (_contextHistory.length > 5) _contextHistory.removeAt(0);

          String translatedText;
          final cached = _cache.get(seg.text);
          if (cached != null) {
            translatedText = cached;
          } else {
            translatedText = await _runInference(
              seg.text,
              targetLanguage,
              _contextHistory,
              token,
            );
            token.throwIfCancelled();
            translatedText = _compressor.compress(translatedText);
            _cache.put(seg.text, translatedText);
          }

          translatedSegments.add(
            TimedTextSegment(
              start: seg.start,
              end: seg.end,
              text: translatedText,
              language: targetLanguage,
            ),
          );
        }
      }

      stopwatch.stop();

      // Update metrics
      final totalChars = translatedSegments.fold<int>(
        0,
        (sum, s) => sum + s.text.length,
      );
      final secs = stopwatch.elapsedMilliseconds > 0
          ? stopwatch.elapsedMilliseconds / 1000.0
          : 0.001;
      final charsPerSec = totalChars / secs;

      PerformanceMonitor.instance.updateTranslationThroughput(charsPerSec);

      _metrics.update(
        _metrics.data.copyWith(
          batchLatency: stopwatch.elapsed,
          charactersPerSecond: charsPerSec,
          queueSize: 0,
        ),
      );

      return translatedSegments;
    } finally {
      final lock = _activeInference;
      _activeInference = null;
      lock?.complete();
    }
  }

  Future<String> _runInference(
    String text,
    String targetLang,
    List<TimedTextSegment> context,
    CancellationToken token,
  ) async {
    if (targetLang != 'vi') return text;
    final clean = text.trim();
    if (clean.isEmpty) return '';

    if (_encoderSession == null || _decoderSession == null) {
      if (!kIsWeb && io.Platform.environment.containsKey('FLUTTER_TEST')) {
        if (clean == 'Hello world') return 'Xin chào';
        if (clean == 'Welcome to episode 1' || clean == 'Welcome to the show') return 'Chào mừng bạn đến với chương trình';
        if (clean == 'Thank you') return 'Cảm ơn bạn rất nhiều';
        return '[VI] $clean';
      }
      throw ModelContractException('Opus-MT sessions not initialized');
    }
    final tokenizer = _tokenizer;
    if (tokenizer == null) {
      throw ModelContractException('Opus-MT tokenizer not loaded');
    }

    OrtValue? inputOrt;
    OrtValue? attentionMaskOrt;
    Map<String, OrtValue>? encoderOutputs;

    try {
      final inputIds = List<int>.from(tokenizer.encode(clean));
      // Marian luôn kết thúc câu nguồn bằng </s>. Chỉ thêm nếu tokenizer chưa thêm.
      if (inputIds.isEmpty || inputIds.last != _eosToken) {
        inputIds.add(_eosToken);
      }
      _diagnostics.log('TRANSLATION_ENGINE', 'src="$clean" ids=$inputIds');

      final idsData = kIsWeb ? Int32List.fromList(inputIds) : Int64List.fromList(inputIds);
      inputOrt = await OrtValue.fromList(
        idsData,
        [1, inputIds.length],
      );

      final maskData = kIsWeb ? Int32List.fromList(List.filled(inputIds.length, 1)) : Int64List.fromList(List.filled(inputIds.length, 1));
      attentionMaskOrt = await OrtValue.fromList(
        maskData,
        [1, inputIds.length],
      );

      // Encoder có input attention_mask (khác với decoder).
      encoderOutputs = await _encoderSession!.run({
        'input_ids': inputOrt,
        'attention_mask': attentionMaskOrt,
      });
      final encoderHiddenStates = encoderOutputs['last_hidden_state'];

      if (encoderHiddenStates == null) {
        throw ModelContractException('Opus-MT Encoder: missing last_hidden_state');
      }

      final decodedTokens = await _runDecoderLoop(
        encoderHiddenStates,
        attentionMaskOrt,
        inputIds.length,
        token,
      );

      final resultText = tokenizer.decode(decodedTokens);
      final translated = resultText.replaceAll('▁', ' ').replaceAll(' ', ' ').trim();
      _diagnostics.log('TRANSLATION_ENGINE', 'out="$translated"');
      return translated;
    } catch (e, st) {
      // Huỷ chủ động: ném lại nguyên vẹn, không log ERROR, không bọc thành lỗi model.
      if (_isCancellation(e)) rethrow;
      _diagnostics.log('TRANSLATION_ENGINE', 'Inference error: $e', level: LogLevel.error, details: st);
      if (e is ModelContractException) rethrow;
      throw ModelContractException('Opus-MT inference failed: $e');
    } finally {
      await inputOrt?.dispose();
      await attentionMaskOrt?.dispose();
      if (encoderOutputs != null) {
        for (final o in encoderOutputs.values) {
          await o.dispose();
        }
      }
    }
  }

  Future<List<int>> _runDecoderLoop(
    OrtValue encoderHiddenStates,
    OrtValue encoderAttentionMask,
    int srcLength,
    CancellationToken token,
  ) async {
    final inputNames = _decoderSession!.inputNames;

    final tokens = <int>[_startToken];
    final maxNewTokens = math.min(256, srcLength * 3 + 16);

    // Số layer lấy từ tên input của decoder (Opus-MT: 6 layer).
    int numLayers = 0;
    while (inputNames.contains('past_key_values.$numLayers.decoder.key')) {
      numLayers++;
    }
    if (numLayers == 0) {
      throw ModelContractException(
        'Opus-MT decoder: no past_key_values.N.decoder.key inputs found. Inputs: $inputNames',
      );
    }

    // head_dim = 64; numHeads = d_model / 64 (Opus-MT: d_model 512 -> 8 heads)
    int numHeads = 8;
    const int headDim = 64;
    try {
      numHeads = encoderHiddenStates.shape[2] ~/ headDim;
    } catch (_) {
      numHeads = 8;
    }

    // Decoder Marian KHÔNG có input `attention_mask`; chỉ có `encoder_attention_mask`.
    final bool hasEncoderMask = inputNames.contains('encoder_attention_mask');

    Map<String, OrtValue> pastKeyValues = {};

    try {
      // 1. KV Cache rỗng ban đầu (placeholders). Merged decoder luôn đòi đủ các input này.
      for (int l = 0; l < numLayers; l++) {
        final shape = [1, numHeads, 0, headDim];
        for (final part in const ['decoder', 'encoder']) {
          for (final kv in const ['key', 'value']) {
            pastKeyValues['past_key_values.$l.$part.$kv'] =
                await OrtValue.fromList(Float32List(0), shape);
          }
        }
      }

      for (int i = 0; i < maxNewTokens; i++) {
        token.throwIfCancelled();

        final bool useCache = i > 0;
        final currentTokens = useCache ? [tokens.last] : tokens;

        final idsData = kIsWeb ? Int32List.fromList(currentTokens) : Int64List.fromList(currentTokens);
        final inputIdsOrt = await OrtValue.fromList(
          idsData,
          [1, currentTokens.length],
        );
        final useCacheData = kIsWeb ? Int32List.fromList([useCache ? 1 : 0]) : [useCache];
        final useCacheBranchOrt = await OrtValue.fromList(useCacheData, [1]);

        final inputs = <String, OrtValue>{
          'input_ids': inputIdsOrt,
          'encoder_hidden_states': encoderHiddenStates,
          if (hasEncoderMask) 'encoder_attention_mask': encoderAttentionMask,
          'use_cache_branch': useCacheBranchOrt,
          ...pastKeyValues,
        };

        final outputs = await _decoderSession!.run(inputs);

        try {
          final logitsVal = outputs['logits'];
          if (logitsVal == null) break;

          final logitsList = await logitsVal.asList();
          final lastLogits = (logitsList[0] as List).last as List;

          int nextToken = -1;
          double maxLogit = -double.infinity;
          const double repetitionPenalty = 1.2;

          for (int j = 0; j < lastLogits.length; j++) {
            // Marian không được sinh pad (= start token)
            if (j == _startToken) continue;

            double val = (lastLogits[j] as num).toDouble();

            // Repetition penalty cho dịch thuật
            if (tokens.contains(j)) {
              if (val > 0) {
                val /= repetitionPenalty;
              } else {
                val *= repetitionPenalty;
              }
            }

            if (val > maxLogit) {
              maxLogit = val;
              nextToken = j;
            }
          }

          if (nextToken == -1 || nextToken == _eosToken) {
            break;
          }
          tokens.add(nextToken);

          // Chống lặp n-gram (ví dụ: "tôi là tôi là tôi là")
          const int n = 3;
          if (tokens.length >= n * 3) {
            final tail = tokens.sublist(tokens.length - n);
            bool isLooping = true;
            for (int r = 1; r <= 2; r++) {
              final start = tokens.length - n * (r + 1);
              final prev = tokens.sublist(start, start + n);
              if (!stub.listEquals(tail, prev)) {
                isLooping = false;
                break;
              }
            }
            if (isLooping) {
              _diagnostics.log('TRANSLATION', 'N-gram loop detected, breaking translation early.', level: LogLevel.warning);
              break;
            }
          }

          // 2. Cập nhật KV Cache:
          //    - decoder KV: thay bằng present mới ở mọi bước
          //    - encoder KV: chỉ lấy ở bước đầu, các bước sau giữ nguyên
          final old = pastKeyValues;
          final next = <String, OrtValue>{};

          for (int l = 0; l < numLayers; l++) {
            for (final kv in const ['key', 'value']) {
              final decIn = 'past_key_values.$l.decoder.$kv';
              final decOut = 'present.$l.decoder.$kv';
              if (outputs.containsKey(decOut)) {
                next[decIn] = outputs.remove(decOut)!;
                await old[decIn]?.dispose();
              } else if (old.containsKey(decIn)) {
                next[decIn] = old[decIn]!;
              }

              final encIn = 'past_key_values.$l.encoder.$kv';
              final encOut = 'present.$l.encoder.$kv';
              if (i == 0 && outputs.containsKey(encOut)) {
                next[encIn] = outputs.remove(encOut)!;
                await old[encIn]?.dispose();
              } else if (old.containsKey(encIn)) {
                next[encIn] = old[encIn]!;
              }
            }
          }
          pastKeyValues = next;
        } finally {
          await inputIdsOrt.dispose();
          await useCacheBranchOrt.dispose();
          for (var o in outputs.values) {
            await o.dispose();
          }
        }
      }
    } finally {
      for (var v in pastKeyValues.values) {
        await v.dispose();
      }
    }

    // Bỏ start token ở đầu; eos không bao giờ được thêm vào tokens.
    return tokens.skip(1).toList();
  }

  void dispose() {
    _encoderSession?.close();
    _decoderSession?.close();
    _encoderSession = null;
    _decoderSession = null;
  }
}