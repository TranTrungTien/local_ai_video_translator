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

      // 1. Encoder Inference
      // MelProcessor already ensures 80x3000 frames.
      final inputOrt = await OrtValue.fromList(melSpectrogram, [1, 80, 3000]);
      final encoderOutputs = await _encoderSession!.run({'input_features': inputOrt});
      final audioFeatures = encoderOutputs['last_hidden_state'];

      if (audioFeatures == null) {
        throw ModelContractException('Whisper Encoder: missing last_hidden_state');
      }

      // 2. Decoder Inference (Autoregressive)
      final decodedTokens = await _runDecoderLoop(audioFeatures, cancellationToken);
      final text = _tokenizer?.decode(decodedTokens) ?? '[Decoded: ${decodedTokens.length} tokens]';

      await inputOrt.dispose();
      for (var o in encoderOutputs.values) {
        await o.dispose();
      }

      final totalSamples = chunks.fold<int>(0, (sum, c) => sum + c.bytes.length ~/ 2);
      final duration = Duration(microseconds: (totalSamples * 1000000) ~/ 16000);

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
      _diagnostics.log('STT', 'Inference failed: $e', level: LogLevel.error);
      if (e is ModelContractException) rethrow;
      throw ModelContractException('Whisper inference failed: $e');
    } finally {
      final lock = _activeInference;
      _activeInference = null;
      lock?.complete();
    }
  }

  Future<List<int>> _runDecoderLoop(
    OrtValue audioFeatures,
    CancellationToken cancellationToken,
  ) async {
    final tokens = <int>[];
    tokens.add(50257); // <|startoftranscript|>
    tokens.add(50259); // <|en|> (Force English for En-Vi pipeline)
    // Bỏ qua ép buộc <|vi|> (50275) để model nhận diện đúng ngôn ngữ nguồn (English).
    // Điều này giúp Engine Dịch (Opus-MT EN-VI) hoạt động chính xác.
    tokens.add(50359); // <|transcribe|>
    tokens.add(50363); // <|notimestamps|>

    const int maxNewTokens = 128;
    const int eosToken = 50256;

    // Mask cho encoder (audio features) luôn cố định 1500 frames cho Whisper Tiny/Base
    final encoderMaskOrt = await OrtValue.fromList(
      Int64List.fromList(List.filled(1500, 1)),
      [1, 1500],
    );

    try {
      for (int i = 0; i < maxNewTokens; i++) {
        cancellationToken.throwIfCancelled();

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
          'encoder_hidden_states': audioFeatures,
          'attention_mask': decoderMaskOrt,         // Self-attention mask
          'encoder_attention_mask': encoderMaskOrt, // Cross-attention mask
          'use_cache_branch': useCacheBranchOrt,
        };

        final outputs = await _decoderSession!.run(inputs);
        final logitsVal = outputs['logits'];

        if (logitsVal == null) {
          await inputIdsOrt.dispose();
          await decoderMaskOrt.dispose();
          await useCacheBranchOrt.dispose();
          for (var o in outputs.values) await o.dispose();
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
      }
    } finally {
      await encoderMaskOrt.dispose();
    }

    return tokens.where((t) => t < 50257).toList();
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
