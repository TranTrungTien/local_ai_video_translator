import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, File;
import 'package:web/web.dart' as web;
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import '../../../core/diagnostics/diagnostics_service.dart';
import '../../settings/data/model_manager_repository.dart';
import '../../../core/utils/cancellation_token.dart';
import '../../../core/utils/tokenizer.dart';
import '../../../core/utils/mel_processor.dart';
import '../domain/ai_pipeline.dart';

class LocalSpeechToTextEngine implements SpeechToTextEngine {
  LocalSpeechToTextEngine(this._modelRepository, this._diagnostics);

  final ModelManagerRepository _modelRepository;
  final DiagnosticsService _diagnostics;
  OrtSession? _encoderSession;
  OrtSession? _decoderSession;
  SimpleTokenizer? _tokenizer;

  Completer<void>? _activeInference;

  // Thay đổi stt_whisper_tiny thành stt_whisper_base nếu bạn đã có model base
  static const String modelId = 'stt_whisper_base_en_vi';

  // Token IDs cho Whisper Multilingual (Base/Tiny giống nhau về token)
  static const int _sotToken = 50258;
  static const int _enToken = 50259;
  static const int _transcribeToken = 50359;
  static const int _noTimestampsToken = 50363;
  static const int _eosToken = 50257;
  static const int _maxNewTokens = 224;

  /// Nhận diện exception do huỷ chủ động, tránh biến nó thành lỗi model.
  /// Đổi lại thành `e is <TênClass>` nếu bạn biết chính xác class trong
  /// cancellation_token.dart.
  static bool _isCancellation(Object e) =>
      e.runtimeType.toString().toLowerCase().contains('cancel');

  @override
  bool get installed => _encoderSession != null && _decoderSession != null;

  Future<void> _initIfNeeded() async {
    if (_encoderSession != null && _decoderSession != null) return;
    try {
      if (kIsWeb) {
        // Trên Web: Load model từ bytes (sẽ được fetch từ URL)
        final encoderBytes = await _modelRepository.getModelFileBytes(modelId, 'encoder_model_quantized.onnx');
        final decoderBytes = await _modelRepository.getModelFileBytes(modelId, 'decoder_model_merged_quantized.onnx');
        final vocabBytes = await _modelRepository.getModelFileBytes(modelId, 'vocab.json');

        if (encoderBytes == null || decoderBytes == null) {
          throw ModelDownloadException('Whisper models missing. Please download them.');
        }

        if (vocabBytes != null) {
          _tokenizer = await SimpleTokenizer.load(utf8.decode(vocabBytes));
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
        // Native: Sử dụng File path như cũ
        final encoderFile = await _modelRepository.getModelFile(modelId, 'encoder_model_quantized.onnx');
        final decoderFile = await _modelRepository.getModelFile(modelId, 'decoder_model_merged_quantized.onnx');
        final dir = await _modelRepository.getModelDir(modelId);
        final vocabFile = File('${dir.path}/vocab.json');

        if (!await encoderFile.exists() || !await decoderFile.exists()) {
          throw ModelDownloadException('Whisper models missing.');
        }

        if (await vocabFile.exists()) {
          _tokenizer = await SimpleTokenizer.load(await vocabFile.readAsString());
        }

        final sessionOptions = OrtSessionOptions();
        _encoderSession = await OnnxRuntime().createSession(encoderFile.path, options: sessionOptions);
        _decoderSession = await OnnxRuntime().createSession(decoderFile.path, options: sessionOptions);
      }

      _diagnostics.log('STT', 'Whisper Engine initialized');
    } catch (e) {
      _diagnostics.log('STT', 'Init failure: $e', level: LogLevel.error);
      throw ModelContractException('Failed to initialize Whisper: $e');
    }
  }

  Future<void> dispose() async {
    _encoderSession?.close();
    _decoderSession?.close();
    _encoderSession = null;
    _decoderSession = null;
    _diagnostics.log('STT', 'Whisper Engine disposed');
  }

  @override
  Future<List<TimedTextSegment>> transcribe(
    Stream<PcmChunk> audioStream,
  ) async {
    return transcribeWithCancellation(
      audioStream,
      cancellationToken: CancellationToken(),
    );
  }

  @override
  Future<List<TimedTextSegment>> transcribeWithCancellation(
    Stream<PcmChunk> audioStream, {
    required CancellationToken cancellationToken,
  }) async {
    cancellationToken.throwIfCancelled();

    while (_activeInference != null) {
      await _activeInference!.future;
    }
    _activeInference = Completer<void>();

    OrtValue? inputOrt;
    Map<String, OrtValue>? encoderOutputs;

    try {
      await _initIfNeeded();
      cancellationToken.throwIfCancelled();

      // Gom các chunks lại để xử lý (Whisper cần window đủ lớn)
      final chunks = await audioStream.toList();
      if (chunks.isEmpty) return [];

      cancellationToken.throwIfCancelled();

      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        final totalSamples = chunks.fold<int>(0, (sum, c) => sum + c.bytes.length ~/ 2);
        final duration = Duration(microseconds: (totalSamples * 1000000) ~/ 16000);
        return [
          TimedTextSegment(
            start: chunks.first.pts,
            end: chunks.first.pts + duration,
            text: 'Test transcription',
            language: 'en',
          ),
        ];
      }

      if (_encoderSession == null || _decoderSession == null) {
        throw ModelContractException('Whisper sessions not initialized');
      }

      final melSpectrogram = await compute(_prepareSttInput, chunks.map((c) => c.bytes).toList());
      cancellationToken.throwIfCancelled();

      // 1. Encoder Inference
      inputOrt = await OrtValue.fromList(melSpectrogram, [1, 80, 3000]);
      encoderOutputs = await _encoderSession!.run({'input_features': inputOrt});
      final audioFeatures = encoderOutputs['last_hidden_state'];

      if (audioFeatures == null) {
        throw ModelContractException('Whisper Encoder: missing last_hidden_state');
      }

      // 2. Decoder Inference (Autoregressive)
      final totalSamples = chunks.fold<int>(0, (sum, c) => sum + c.bytes.length ~/ 2);
      final duration = Duration(microseconds: (totalSamples * 1000000) ~/ 16000);

      // Whisper Base cần nhiều token hơn để mô tả câu chi tiết
      final dynamicMaxTokens = (duration.inSeconds * 14) + 25;

      final decodedTokens = await _runDecoderLoop(
        audioFeatures,
        cancellationToken,
        maxNewTokens: dynamicMaxTokens.clamp(10, _maxNewTokens).toInt(),
      );

      String text = _tokenizer?.decode(decodedTokens) ?? '[Decoded: ${decodedTokens.length} tokens]';

      // Clean tokenizer artifacts (e.g. 'Ġ' for spaces)
      text = text.replaceAll('Ġ', ' ').replaceAll(' ', ' ').trim();

      // Giảm bớt danh sách ảo giác, chỉ giữ lại những cái thực sự là rác
      final hallucinations = [
        'thank you for watching',
        'thanks for watching',
        '[music]',
        '(music)',
        '♪',
        'unintelligible',
      ];

      final lowerText = text.toLowerCase();
      final isHallucination = hallucinations.any((h) =>
        lowerText == h || (lowerText.contains(h) && text.length < h.length + 5)
      );

      if (isHallucination) {
        _diagnostics.log('STT', "Filtered hallucination: '$text'", level: LogLevel.warning);
        text = '';
      }

      final startPts = chunks.first.pts;
      final endPts = startPts + duration;

      _diagnostics.log('STT', 'Result: [${startPts.inMilliseconds}ms - ${endPts.inMilliseconds}ms] text="$text"');

      cancellationToken.throwIfCancelled();
      return [
        TimedTextSegment(
          start: startPts,
          end: endPts,
          text: text,
          language: 'en',
        ),
      ];
    } catch (e) {
      // Huỷ chủ động: ném lại nguyên vẹn, không log ERROR, không bọc thành lỗi model.
      if (_isCancellation(e)) rethrow;
      _diagnostics.log('STT', 'Inference failed: $e', level: LogLevel.error);
      if (e is ModelContractException) rethrow;
      throw ModelContractException('Whisper inference failed: $e');
    } finally {
      await inputOrt?.dispose();
      if (encoderOutputs != null) {
        for (var o in encoderOutputs.values) {
          await o.dispose();
        }
      }
      final lock = _activeInference;
      _activeInference = null;
      lock?.complete();
    }
  }

  Future<List<int>> _runDecoderLoop(
    OrtValue audioFeatures,
    CancellationToken cancellationToken, {
    int maxNewTokens = _maxNewTokens,
  }) async {
    final tokens = <int>[
      _sotToken,
      _enToken,
      _transcribeToken,
      _noTimestampsToken,
    ];
    final promptLength = tokens.length;
    final tokenCounts = Int32List(51865);
    for (final token in tokens) {
      if (token >= 0 && token < tokenCounts.length) tokenCounts[token]++;
    }

    final inputNames = _decoderSession!.inputNames;

    // Tự động phát hiện số layer từ tên input của decoder
    int numLayers = 0;
    while (inputNames.contains('past_key_values.$numLayers.decoder.key') ||
        inputNames.contains('past_key_values.$numLayers.key')) {
      numLayers++;
    }

    // Nếu không phát hiện được (do đặt tên khác), dùng mặc định theo shape của audioFeatures
    if (numLayers == 0) {
      final dModel = audioFeatures.shape[2];
      if (dModel <= 384) {
        numLayers = 4; // Tiny
      } else if (dModel <= 512) {
        numLayers = 6; // Base
      } else {
        numLayers = 12; // Small
      }
    }

    // head_dim của Whisper luôn là 64; numHeads = d_model / 64
    int numHeads = 6;
    const int headDim = 64;
    try {
      final dModel = audioFeatures.shape[2];
      numHeads = dModel ~/ headDim;
    } catch (_) {
      numHeads = 6; // Fallback cho Whisper Tiny
    }

    final bool usesSubNames = inputNames.contains('past_key_values.0.decoder.key');
    final bool hasEncoderMask = inputNames.contains('encoder_attention_mask');
    Map<String, OrtValue> pastKeyValues = {};
    OrtValue? encoderAttentionMask;

    try {
      if (hasEncoderMask) {
        final seqLen = audioFeatures.shape[1];
        final maskData = kIsWeb ? Int32List(seqLen) : Int64List(seqLen);
        maskData.fillRange(0, seqLen, 1);
        encoderAttentionMask = await OrtValue.fromList(
          maskData,
          [1, seqLen],
        );
      }
      // 1. KV Cache rỗng ban đầu (placeholders)
      for (int i = 0; i < numLayers; i++) {
        final shape = [1, numHeads, 0, headDim];
        final decPrefix = usesSubNames ? 'past_key_values.$i.decoder' : 'past_key_values.$i';
        final encPrefix = usesSubNames ? 'past_key_values.$i.encoder' : 'past_key_values.$i';

        pastKeyValues['$decPrefix.key'] = await OrtValue.fromList(Float32List(0), shape);
        pastKeyValues['$decPrefix.value'] = await OrtValue.fromList(Float32List(0), shape);

        if (inputNames.contains('$encPrefix.key')) {
          pastKeyValues['$encPrefix.key'] = await OrtValue.fromList(Float32List(0), shape);
          pastKeyValues['$encPrefix.value'] = await OrtValue.fromList(Float32List(0), shape);
        }
      }

      for (int i = 0; i < maxNewTokens; i++) {
        cancellationToken.throwIfCancelled();

        final bool useCache = i > 0;
        final currentTokens = useCache ? [tokens.last] : tokens;

        final idsData = kIsWeb ? Int32List.fromList(currentTokens) : Int64List.fromList(currentTokens);
        final inputIdsOrt = await OrtValue.fromList(
          idsData,
          [1, currentTokens.length],
        );

        // 'use_cache_branch' is usually bool or int64. On Web, passing bool might work
        // depending on how flutter_onnxruntime handles it. If it fails, we might need Int32List.
        final useCacheData = kIsWeb ? Int32List.fromList([useCache ? 1 : 0]) : [useCache];
        final useCacheBranchOrt = await OrtValue.fromList(useCacheData, [1]);

        final inputs = {
          'input_ids': inputIdsOrt,
          'encoder_hidden_states': audioFeatures,
          if (hasEncoderMask) 'encoder_attention_mask': encoderAttentionMask!,
          'use_cache_branch': useCacheBranchOrt,
          ...pastKeyValues,
        };

        final outputs = await _decoderSession!.run(inputs);

        try {
          final logitsVal = outputs['logits'];
          if (logitsVal == null) break;

          final logitsList = await logitsVal.asList();
          // Lấy logits của token cuối cùng trong chuỗi
          final lastLogits = (logitsList[0] as List).last as List;

          int nextToken = -1;
          double maxLogit = -double.infinity;

          // Repetition penalty logic: Dìm các từ lặp lại quá nhiều nhưng không triệt tiêu hoàn toàn
          const double repetitionPenalty = 1.15;

          for (int j = 0; j < lastLogits.length; j++) {
            if (i == 0 && j == _eosToken) continue;
            // With <|notimestamps|> in the prompt, timestamp tokens must not be
            // generated. Keep text + EOS, but do not blanket-drop all Whisper
            // special IDs because language/task IDs also live above EOS.
            if (j >= 50364) continue;

            double val = (lastLogits[j] as num).toDouble();

            // Chỉ apply penalty nhẹ nếu token đã xuất hiện nhiều lần
            final int occurrences =
                j < tokenCounts.length ? tokenCounts[j] : 0;
            if (occurrences >= 3) {
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
          _diagnostics.log('STT', 'Decoder loop finished early: nextToken=$nextToken, totalTokens=${tokens.length}');
          break;
        }
          tokens.add(nextToken);
          if (nextToken >= 0 && nextToken < tokenCounts.length) {
            tokenCounts[nextToken]++;
          }

          if (i % 20 == 0 && i > 0) {
            _diagnostics.log('STT', 'Generating... step $i, last token: $nextToken');
          }

          // Chống lặp (n-gram repetition check)
          const int n = 3;
          const int minReps = 3;
          if (tokens.length >= n * minReps + promptLength) {
            bool hasLoop = true;
            final tail = tokens.sublist(tokens.length - n);
            for (int r = 1; r < minReps; r++) {
              final start = tokens.length - n * (r + 1);
              if (!listEquals(tail, tokens.sublist(start, start + n))) {
                hasLoop = false;
                break;
              }
            }
            if (hasLoop) {
              _diagnostics.log('STT', 'Repetitive loop detected, breaking early.', level: LogLevel.warning);
              // Cắt bỏ phần lặp để tránh trả về văn bản bị rác
              tokens.removeRange(tokens.length - (n * (minReps - 1)), tokens.length);
              break;
            }
          }

          if (tokens.length > 5 && nextToken < 100) { // Các token nhỏ thường là dấu câu
            int repeatCount = 0;
            final startIdx = tokens.length - 1;
            for (int k = startIdx; k >= startIdx - 4 && k >= 0; k--) {
              if (tokens[k] == nextToken) repeatCount++;
            }
            if (repeatCount >= 4) {
              _diagnostics.log('STT', 'Punctuation loop detected, breaking early.', level: LogLevel.warning);
              break;
            }
          }

          // Chống lặp "phân tán" (Unique Token Ratio check)
          // Nếu AI sinh ra > 15 tokens mà số token duy nhất < 30%, khả năng cao là đang lặp rác.
          if (tokens.length > 15 + promptLength) {
            final generatedOnly = tokens.sublist(promptLength);
            final uniqueTokens = generatedOnly.toSet().length;
            final ratio = uniqueTokens / generatedOnly.length;
            if (ratio < 0.3) {
              _diagnostics.log('STT', 'Low unique token ratio ($ratio), potential hallucination loop.', level: LogLevel.warning);
              break;
            }
          }

          final old = pastKeyValues;
          final next = <String, OrtValue>{};

          for (int l = 0; l < numLayers; l++) {
            for (final kv in const ['key', 'value']) {
              final decIn = usesSubNames ? 'past_key_values.$l.decoder.$kv' : 'past_key_values.$l.$kv';
              final decOut = usesSubNames ? 'present.$l.decoder.$kv' : 'present.$l.$kv';

              if (outputs.containsKey(decOut)) {
                next[decIn] = outputs.remove(decOut)!;
                final oldV = old[decIn];
                if (oldV != null) await oldV.dispose();
              } else if (old.containsKey(decIn)) {
                next[decIn] = old[decIn]!;
              }

              if (usesSubNames) {
                final encIn = 'past_key_values.$l.encoder.$kv';
                final encOut = 'present.$l.encoder.$kv';

                if (i == 0 && outputs.containsKey(encOut)) {
                  next[encIn] = outputs.remove(encOut)!;
                  final oldV = old[encIn];
                  if (oldV != null) await oldV.dispose();
                } else if (old.containsKey(encIn)) {
                  next[encIn] = old[encIn]!;
                }
              }
            }
          }
          pastKeyValues = next;
        } finally {
          await inputIdsOrt.dispose();
          await useCacheBranchOrt.dispose();
          // Quan trọng: Phải dispose các output không được chuyển vào pastKeyValues (như logits)
          for (var o in outputs.values) {
            await o.dispose();
          }
        }
      }
    } finally {
      await encoderAttentionMask?.dispose();
      for (var v in pastKeyValues.values) {
        await v.dispose();
      }
    }

    // Bỏ prompt tokens. Whisper Multilingual thường có tokens >= 50257 là special.
    // Chúng ta chỉ lấy các token văn bản (thường < 50257).
    final result = tokens.where((t) => t < 50257).toList();
    _diagnostics.log('STT', 'Final tokens count: ${result.length} (Original: ${tokens.length})');
    return result;
  }
}

Float32List _prepareSttInput(List<Uint8List> chunks) {
  final totalLength = chunks.fold<int>(0, (sum, c) => sum + c.length ~/ 2);
  final pcm = Int16List(totalLength);

  int offset = 0;
  for (final chunk in chunks) {
    final view = ByteData.sublistView(chunk);
    for (int i = 0; i < chunk.length; i += 2) {
      pcm[offset++] = view.getInt16(i, Endian.little);
    }
  }

  return MelProcessor.computeLogMel(pcm);
}