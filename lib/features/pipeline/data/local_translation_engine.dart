import 'dart:async';
import 'dart:io';
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

    // Try to load accompanying vocab if exists
    final dir = await _modelRepository.getModelDir(modelId);
    final vocabFile = File('${dir.path}/vocab.json');
    if (await vocabFile.exists()) {
      _tokenizer = await SimpleTokenizer.load(await vocabFile.readAsString());
    }

    final sessionOptions = OrtSessionOptions();
    _encoderSession = await OnnxRuntime().createSession(
      encoderFile.path,
      options: sessionOptions,
    );
    _decoderSession = await OnnxRuntime().createSession(
      decoderFile.path,
      options: sessionOptions,
    );
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
      // ... rest of logic
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

    try {
      final inputIds = _tokenizer?.encode(clean) ?? clean.codeUnits;

      final inputOrt = await OrtValue.fromList(
        Int64List.fromList(inputIds),
        [1, inputIds.length],
      );

      final attentionMaskOrt = await OrtValue.fromList(
        Int64List.fromList(List.filled(inputIds.length, 1)),
        [1, inputIds.length],
      );

      final encoderOutputs = await _encoderSession!.run({
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
        token,
      );

      await inputOrt.dispose();
      await attentionMaskOrt.dispose();
      for (var o in encoderOutputs.values) {
        await o.dispose();
      }

      return _tokenizer?.decode(decodedTokens) ?? String.fromCharCodes(decodedTokens);
    } catch (e, st) {
      _diagnostics.log('TRANSLATION_ENGINE', 'Inference error: $e', level: LogLevel.error, details: st);
      if (e is ModelContractException) rethrow;
      throw ModelContractException('Opus-MT inference failed: $e');
    }
  }

  Future<List<int>> _runDecoderLoop(
    OrtValue encoderHiddenStates,
    OrtValue encoderAttentionMask,
    CancellationToken token,
  ) async {
    final tokens = <int>[];
    // Marian en-vi (Xenova) decoder start token
    const int startToken = 59513;
    const int eosToken = 0;

    tokens.add(startToken);
    const int maxNewTokens = 256;

    for (int i = 0; i < maxNewTokens; i++) {
      token.throwIfCancelled();

      final inputIdsOrt = await OrtValue.fromList(
        Int64List.fromList(tokens),
        [1, tokens.length],
      );

      // Mask cho decoder (self-attention) có độ dài khớp với số lượng tokens hiện tại
      final decoderMaskOrt = await OrtValue.fromList(
        Int64List.fromList(List.filled(tokens.length, 1)),
        [1, tokens.length],
      );

      final useCacheBranchOrt = await OrtValue.fromList([false], [1]);

      final inputs = {
        'input_ids': inputIdsOrt,
        'encoder_hidden_states': encoderHiddenStates,
        'attention_mask': decoderMaskOrt,               // Self-attention mask
        'encoder_attention_mask': encoderAttentionMask, // Cross-attention mask
        'use_cache_branch': useCacheBranchOrt,
      };

      final outputs = await _decoderSession!.run(inputs);
      final logitsVal = outputs['logits'];

      if (logitsVal == null) {
        await inputIdsOrt.dispose();
        await decoderMaskOrt.dispose();
        await useCacheBranchOrt.dispose();
        for (var o in outputs.values) {
          await o.dispose();
        }
        break;
      }

      final logitsList = await logitsVal.asList();
      final lastLogits = (logitsList[0] as List).last as List;

      int nextToken = 0;
      double maxLogit = -double.infinity;
      for (int j = 0; j < lastLogits.length; j++) {
        final val = (lastLogits[j] as num).toDouble();
        if (val > maxLogit) {
          maxLogit = val;
          nextToken = j;
        }
      }

      await inputIdsOrt.dispose();
      await decoderMaskOrt.dispose();
      await useCacheBranchOrt.dispose();
      for (var o in outputs.values) {
        await o.dispose();
      }

      if (nextToken == eosToken) break;
      tokens.add(nextToken);

      // Avoid infinite loops if model misbehaves
      if (tokens.length > maxNewTokens) break;
    }

    // Filter out special tokens and start token
    return tokens.where((t) => t != startToken && t != eosToken).toList();
  }

  void dispose() {
    _encoderSession?.close();
    _decoderSession?.close();
  }
}
