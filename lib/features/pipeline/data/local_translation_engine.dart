import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

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

    if (Platform.environment.containsKey('FLUTTER_TEST')) return;

    final encoderFile = await _modelRepository.getModelFile(
      modelId,
      'encoder_model_quantized.onnx',
    );
    final decoderFile = await _modelRepository.getModelFile(
      modelId,
      'decoder_model_merged_quantized.onnx',
    );

    if (!await encoderFile.exists() || !await decoderFile.exists()) {
      throw ModelDownloadException('Opus-MT models (encoder/decoder) missing. Please download them in settings.');
    }

    final dir = await _modelRepository.getModelDir(modelId);
    final vocabFile = File('${dir.path}/vocab.json');
    if (!await vocabFile.exists()) {
      // Không có tokenizer thì không dịch được; báo rõ thay vì tạo lại session mỗi lần gọi.
      throw ModelContractException('Opus-MT vocab.json missing. Please re-download the translation model.');
    }
    _tokenizer = await SimpleTokenizer.load(await vocabFile.readAsString());

    await _loadSpecialTokens(dir);

    final sessionOptions = OrtSessionOptions();
    _encoderSession = await OnnxRuntime().createSession(
      encoderFile.path,
      options: sessionOptions,
    );
    _decoderSession = await OnnxRuntime().createSession(
      decoderFile.path,
      options: sessionOptions,
    );

    _diagnostics.log('TRANSLATION_ENGINE', 'Opus-MT initialized (start=$_startToken, eos=$_eosToken)');
    _diagnostics.log('TRANSLATION_ENGINE', 'Decoder Inputs: ${_decoderSession?.inputNames}');
    _diagnostics.log('TRANSLATION_ENGINE', 'Decoder Outputs: ${_decoderSession?.outputNames}');
  }

  /// Đọc decoder_start_token_id / eos_token_id từ config.json nếu có.
  Future<void> _loadSpecialTokens(Directory dir) async {
    try {
      final configFile = File('${dir.path}/config.json');
      if (!await configFile.exists()) return;
      final json = jsonDecode(await configFile.readAsString());
      if (json is! Map) return;

      final start = json['decoder_start_token_id'] ?? json['pad_token_id'];
      final eos = json['eos_token_id'];
      if (start is int) _startToken = start;
      if (eos is int) _eosToken = eos;
    } catch (e) {
      _diagnostics.log('TRANSLATION_ENGINE', 'Could not read config.json, using defaults: $e', level: LogLevel.warning);
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

      inputOrt = await OrtValue.fromList(
        Int64List.fromList(inputIds),
        [1, inputIds.length],
      );

      attentionMaskOrt = await OrtValue.fromList(
        Int64List.fromList(List.filled(inputIds.length, 1)),
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

        final inputIdsOrt = await OrtValue.fromList(
          Int64List.fromList(currentTokens),
          [1, currentTokens.length],
        );
        final useCacheBranchOrt = await OrtValue.fromList([useCache], [1]);

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
          for (int j = 0; j < lastLogits.length; j++) {
            // Marian không được sinh pad (= start token), theo bad_words_ids của generation config.
            if (j == _startToken) continue;
            final val = (lastLogits[j] as num).toDouble();
            if (val > maxLogit) {
              maxLogit = val;
              nextToken = j;
            }
          }

          if (nextToken == -1 || nextToken == _eosToken) break;
          tokens.add(nextToken);

          // Chống lặp: dừng nếu 4 token sinh ra gần nhất giống hệt nhau.
          if (tokens.length - 1 >= 4) {
            final t = tokens.sublist(tokens.length - 4);
            if (t.every((x) => x == t.first)) {
              tokens.removeRange(tokens.length - 3, tokens.length);
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