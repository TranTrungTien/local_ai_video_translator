import 'dart:async';
import 'dart:io';
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

  static const String modelId = 'stt_whisper_tiny_en_vi';

  // Token IDs cho Whisper Multilingual.
  // Nếu model thực chất là tiny.en: SOT=50257, EOT=50256, notimestamps=50362,
  // và không có token ngôn ngữ / task.
  static const int _sotToken = 50258; // <|startoftranscript|>
  static const int _enToken = 50259; // <|en|>
  static const int _transcribeToken = 50359; // <|transcribe|>
  static const int _noTimestampsToken = 50363; // <|notimestamps|>
  static const int _eosToken = 50257; // <|endoftext|>
  static const int _spaceToken = 220; // " " (begin_suppress_tokens)
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
      final encoderFile = await _modelRepository.getModelFile(
        modelId,
        'encoder_model_quantized.onnx',
      );
      final decoderFile = await _modelRepository.getModelFile(
        modelId,
        'decoder_model_merged_quantized.onnx',
      );

      final dir = await _modelRepository.getModelDir(modelId);
      final vocabFile = File('${dir.path}/vocab.json');

      if (!await encoderFile.exists() || !await decoderFile.exists()) {
        throw ModelDownloadException('Whisper models (encoder/decoder) missing. Please download them in settings.');
      }

      if (await vocabFile.exists()) {
        _tokenizer = await SimpleTokenizer.load(await vocabFile.readAsString());
        _diagnostics.log('STT', 'Tokenizer loaded successfully');
      } else {
        _diagnostics.log('STT', 'Warning: vocab.json not found at ${vocabFile.path}', level: LogLevel.warning);
      }

      if (Platform.environment.containsKey('FLUTTER_TEST')) return;

      final sessionOptions = OrtSessionOptions();
      _encoderSession = await OnnxRuntime().createSession(
        encoderFile.path,
        options: sessionOptions,
      );
      _decoderSession = await OnnxRuntime().createSession(
        decoderFile.path,
        options: sessionOptions,
      );

      _diagnostics.log('STT', 'Whisper Engine (Encoder+Decoder) initialized');
      _diagnostics.log('STT', 'Decoder Inputs: ${_decoderSession?.inputNames}');
      _diagnostics.log('STT', 'Decoder Outputs: ${_decoderSession?.outputNames}');
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

      if (_encoderSession == null || _decoderSession == null) {
        throw ModelContractException('Whisper sessions not initialized');
      }

      final melSpectrogram = await compute(_prepareSttInput, chunks.map((c) => c.bytes).toList());
      cancellationToken.throwIfCancelled();

      // 1. Encoder Inference (MelProcessor phải trả đúng 80x3000 frames)
      inputOrt = await OrtValue.fromList(melSpectrogram, [1, 80, 3000]);
      encoderOutputs = await _encoderSession!.run({'input_features': inputOrt});
      final audioFeatures = encoderOutputs['last_hidden_state'];

      if (audioFeatures == null) {
        throw ModelContractException('Whisper Encoder: missing last_hidden_state');
      }

      // 2. Decoder Inference (Autoregressive)
      final decodedTokens = await _runDecoderLoop(audioFeatures, cancellationToken);
      String text = _tokenizer?.decode(decodedTokens) ?? '[Decoded: ${decodedTokens.length} tokens]';

      // Clean tokenizer artifacts (e.g. 'Ġ' for spaces)
      text = text.replaceAll('Ġ', ' ').replaceAll(' ', ' ').trim();

      final totalSamples = chunks.fold<int>(0, (sum, c) => sum + c.bytes.length ~/ 2);
      final duration = Duration(microseconds: (totalSamples * 1000000) ~/ 16000);
      final startPts = chunks.first.pts;
      final endPts = startPts + duration;

      _diagnostics.log('STT', 'Result: [${startPts.inMilliseconds}ms - ${endPts.inMilliseconds}ms] text="$text"');

      cancellationToken.throwIfCancelled();
      return [
        TimedTextSegment(
          start: chunks.first.pts,
          end: chunks.first.pts + duration,
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
    CancellationToken cancellationToken,
  ) async {
    final tokens = <int>[
      _sotToken,
      _enToken, // Ép English cho pipeline En-Vi
      _transcribeToken,
      _noTimestampsToken,
    ];
    final promptLength = tokens.length;

    final inputNames = _decoderSession!.inputNames;

    // Tự động phát hiện số layer từ tên input của decoder
    int numLayers = 0;
    while (inputNames.contains('past_key_values.$numLayers.decoder.key') ||
        inputNames.contains('past_key_values.$numLayers.key')) {
      numLayers++;
    }
    if (numLayers == 0) numLayers = 4; // Fallback cho Whisper Tiny

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
        encoderAttentionMask = await OrtValue.fromList(
          Int64List(seqLen)..fillRange(0, seqLen, 1),
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

      for (int i = 0; i < _maxNewTokens; i++) {
        cancellationToken.throwIfCancelled();

        final bool useCache = i > 0;
        final currentTokens = useCache ? [tokens.last] : tokens;

        final inputIdsOrt = await OrtValue.fromList(
          Int64List.fromList(currentTokens),
          [1, currentTokens.length],
        );

        final useCacheBranchOrt = await OrtValue.fromList([useCache], [1]);
        if (i == 0) {
          _diagnostics.log('STT', 'use_cache_branch tensor type: ${useCacheBranchOrt.dataType}');
        }

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

          for (int j = 0; j < lastLogits.length; j++) {
            // Chỉ cho phép text tokens (< 50257) và EOS (50257).
            if (j > _eosToken) continue;
            // begin_suppress_tokens: tránh EOT/khoảng trắng ngay token đầu tiên.
            if (i == 0 && (j == _eosToken || j == _spaceToken)) continue;

            final val = (lastLogits[j] as num).toDouble();
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

          if (i % 10 == 0 && i > 0) {
            _diagnostics.log('STT', 'Generating... step $i, last token: $nextToken');
          }

          // Chống lặp: dừng nếu 4 token sinh ra gần nhất giống hệt nhau.
          final generated = tokens.length - promptLength;
          if (generated >= 4) {
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
              final decIn = usesSubNames ? 'past_key_values.$l.decoder.$kv' : 'past_key_values.$l.$kv';
              final decOut = usesSubNames ? 'present.$l.decoder.$kv' : 'present.$l.$kv';

              if (outputs.containsKey(decOut)) {
                next[decIn] = outputs.remove(decOut)!;
                if (old.containsKey(decIn)) await old[decIn]!.dispose();
              } else if (old.containsKey(decIn)) {
                next[decIn] = old[decIn]!;
              }

              if (usesSubNames) {
                final encIn = 'past_key_values.$l.encoder.$kv';
                final encOut = 'present.$l.encoder.$kv';

                if (i == 0 && outputs.containsKey(encOut)) {
                  next[encIn] = outputs.remove(encOut)!;
                  if (old.containsKey(encIn)) await old[encIn]!.dispose();
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