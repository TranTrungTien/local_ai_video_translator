
import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter_test/flutter_test.dart';

// ==========================================
// 1. STUBS & UTILS
// ==========================================
bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null || b == null) return a == b;
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) if (a[i] != b[i]) return false;
  return true;
}

class PcmChunk {
  final Duration pts;
  final int sampleRate;
  final int channels;
  final Uint8List bytes;
  PcmChunk({required this.pts, required this.sampleRate, required this.channels, required this.bytes});
}

class TimedTextSegment {
  final Duration start;
  final Duration end;
  final String text;
  String? translatedText;
  TimedTextSegment({required this.start, required this.end, required this.text, this.translatedText});
}

// ==========================================
// 2. MEL PROCESSOR (16kHz, 80 mel bins, 30s window)
// ==========================================
class MelProcessor {
  static const int sampleRate = 16000;
  static const int nFft = 400;
  static const int hopLength = 160;
  static const int nMels = 80;
  static const int nFrames = 3000;
  static const int nSamples = 16000 * 30;
  static const int _freqBins = 201;

  static final Float64List _window = _periodicHann(400);
  static final List<Float64List> _melFilters = _createSlaneyFilters();

  static Float32List computeLogMel(Int16List pcm) {
    final samples = Float64List(nSamples);
    final limit = math.min(pcm.length, nSamples);
    for (var i = 0; i < limit; i++) samples[i] = pcm[i] / 32768.0;

    final centered = _reflectPad(samples, 200);
    final out = Float32List(nMels * nFrames);
    final frame = Float64List(400);
    var maxLog = -double.infinity;

    for (var t = 0; t < nFrames; t++) {
      final start = t * 160;
      for (var i = 0; i < 400; i++) frame[i] = centered[start + i] * _window[i];
      final power = _dftPower(frame);
      for (var m = 0; m < nMels; m++) {
        var energy = 0.0;
        final filter = _melFilters[m];
        for (var k = 0; k < _freqBins; k++) energy += filter[k] * power[k];
        final value = math.log(math.max(energy, 1e-10)) / math.ln10;
        out[m * nFrames + t] = value;
        if (value > maxLog) maxLog = value;
      }
    }
    final floor = maxLog - 8.0;
    for (var i = 0; i < out.length; i++) out[i] = (math.max(out[i], floor) + 4.0) / 4.0;
    return out;
  }

  static Float64List _reflectPad(Float64List input, int pad) {
    final out = Float64List(input.length + pad * 2);
    out.setRange(pad, pad + input.length, input);
    for (var i = 0; i < pad; i++) {
      out[pad - 1 - i] = input[math.min(i + 1, input.length - 1)];
      out[pad + input.length + i] = input[math.max(0, input.length - 2 - i)];
    }
    return out;
  }

  static Float64List _periodicHann(int length) {
    final w = Float64List(length);
    for (var i = 0; i < length; i++) w[i] = 0.5 - 0.5 * math.cos(2.0 * math.pi * i / length);
    return w;
  }

  static Float64List _dftPower(Float64List frame) {
    final power = Float64List(_freqBins);
    for (var k = 0; k < _freqBins; k++) {
      var re = 0.0, im = 0.0;
      final step = -2.0 * math.pi * k / 400;
      for (var n = 0; n < 400; n++) {
        final angle = step * n;
        re += frame[n] * math.cos(angle);
        im += frame[n] * math.sin(angle);
      }
      power[k] = re * re + im * im;
    }
    return power;
  }

  static List<Float64List> _createSlaneyFilters() {
    double hzToMel(double hz) {
      if (hz >= 1000.0) return 1000.0 / (200.0/3.0) + math.log(hz / 1000.0) / (math.log(6.4) / 27.0);
      return hz / (200.0/3.0);
    }
    double melToHz(double mel) {
      if (mel >= 15.0) return 1000.0 * math.exp((math.log(6.4) / 27.0) * (mel - 15.0));
      return (200.0/3.0) * mel;
    }
    final minMel = hzToMel(0.0), maxMel = hzToMel(8000.0);
    final hzPoints = List.generate(82, (i) => melToHz(minMel + (maxMel - minMel) * i / 81));
    return List.generate(80, (m) {
      final l = hzPoints[m], c = hzPoints[m+1], u = hzPoints[m+2], enorm = 2.0 / (u - l), f = Float64List(201);
      for (var k = 0; k < 201; k++) {
        final freq = k * 16000 / 400;
        f[k] = math.max(0.0, math.min((freq - l) / (c - l), (u - freq) / (u - c))) * enorm;
      }
      return f;
    });
  }
}

// ==========================================
// 3. TOKENIZER
// ==========================================
class SimpleTokenizer {
  final Map<int, String> _invVocab;
  final Map<String, int> _vocab;
  SimpleTokenizer(this._invVocab, this._vocab);
  static Future<SimpleTokenizer> load(String jsonStr) async {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final inv = <int, String>{};
    final vocab = <String, int>{};
    data.forEach((k, v) {
      final id = v as int;
      inv[id] = k;
      vocab[k] = id;
    });
    return SimpleTokenizer(inv, vocab);
  }

  List<int> encode(String text) {
    final result = <int>[];
    // Detect space prefix: Whisper uses 'Ġ', Opus uses ' '
    String space = _vocab.containsKey(' ') ? ' ' : (_vocab.containsKey('Ġ') ? 'Ġ' : ' ');
    String normalized = text.replaceAll(' ', space);

    int i = 0;
    while (i < normalized.length) {
      bool found = false;
      for (int len = math.min(normalized.length - i, 50); len > 0; len--) {
        final sub = normalized.substring(i, i + len);
        final id = _vocab[sub];
        if (id != null) {
          result.add(id);
          i += len;
          found = true;
          break;
        }
      }
      if (!found) i++;
    }
    return result;
  }

  String decode(List<int> tokens) {
    return tokens.map((t) => _invVocab[t] ?? '').where((s) => !s.startsWith('<|')).join('')
        .replaceAll('Ġ', ' ').replaceAll(' ', ' ').trim();
  }
}

// ==========================================
// 4. VAD ENGINE (Silero VAD v5)
// ==========================================
class LocalVadEngine {
  final OrtSession session;
  final Duration maxSpeechDuration = const Duration(seconds: 12);
  final Duration maxMergeGap = const Duration(milliseconds: 1000);
  final Duration minSpeechDuration = const Duration(milliseconds: 300);
  final Duration postRollDuration = const Duration(milliseconds: 200);
  final Duration preRollDuration = const Duration(milliseconds: 150);

  LocalVadEngine(this.session);

  final Float32List _state = Float32List(2 * 1 * 128);
  final Float32List _context = Float32List(64);
  final Float32List _windowBuffer = Float32List(576);

  void resetState() {
    _state.fillRange(0, _state.length, 0.0);
    _context.fillRange(0, _context.length, 0.0);
  }

  Future<bool> isSpeech(Uint8List bytes) async {
    final int16Data = bytes.buffer.asInt16List();
    const double scale = 1.0 / 32768.0;
    _windowBuffer.setRange(0, 64, _context);
    for (int i = 0; i < 512; i++) _windowBuffer[64 + i] = int16Data[i] * scale;

    final inputOrt = await OrtValue.fromList(_windowBuffer, [1, 576]);
    final srOrt = await OrtValue.fromList(Int64List.fromList([16000]), []);
    final stateOrt = await OrtValue.fromList(_state, [2, 1, 128]);

    final outputs = await session.run({'input': inputOrt, 'sr': srOrt, 'state': stateOrt});
    final probList = await outputs['output']!.asList();
    final prob = (probList[0] as List)[0] as double;

    final stateList = await outputs['state']!.asList();
    _updateState(_state, stateList);

    for (int i = 0; i < 64; i++) _context[i] = int16Data[int16Data.length - 64 + i] * scale;

    await inputOrt.dispose(); await srOrt.dispose(); await stateOrt.dispose();
    for (var o in outputs.values) await o.dispose();
    return prob >= 0.55;
  }

  void _updateState(Float32List state, List<dynamic> newValue) {
    int idx = 0;
    void traverse(dynamic item) {
      if (item is List) for (var c in item) traverse(c);
      else if (item is num) if (idx < state.length) state[idx++] = item.toDouble();
    }
    traverse(newValue);
  }
}

// ==========================================
// 5. WHISPER ENGINE
// ==========================================
class WhisperEngine {
  final OrtSession encoder;
  final OrtSession decoder;
  final SimpleTokenizer tokenizer;
  WhisperEngine(this.encoder, this.decoder, this.tokenizer);

  Future<String> transcribe(List<Uint8List> chunks) async {
    final totalSamples = chunks.fold<int>(0, (s, c) => s + c.length ~/ 2);
    final pcm = Int16List(totalSamples);
    int offset = 0;
    for (final c in chunks) {
      final view = ByteData.sublistView(c);
      for (int i = 0; i < c.length; i += 2) pcm[offset++] = view.getInt16(i, Endian.little);
    }

    final mel = MelProcessor.computeLogMel(pcm);
    final inputOrt = await OrtValue.fromList(mel, [1, 80, 3000]);
    final encOut = await encoder.run({'input_features': inputOrt});
    final audioFeatures = encOut['last_hidden_state']!;

    final tokens = [50258, 50259, 50359, 50363];
    final promptLength = tokens.length;
    final tokenCounts = Int32List(51865);
    for (final t in tokens) tokenCounts[t]++;

    final dModel = audioFeatures.shape[2];
    final numLayers = dModel <= 384 ? 4 : 6;
    final numHeads = dModel ~/ 64;

    Map<String, OrtValue> pastKV = {};
    for (int i = 0; i < numLayers; i++) {
      for (final kv in ['key', 'value']) {
        pastKV['past_key_values.$i.decoder.$kv'] = await OrtValue.fromList(Float32List(0), [1, numHeads, 0, 64]);
        pastKV['past_key_values.$i.encoder.$kv'] = await OrtValue.fromList(Float32List(0), [1, numHeads, 0, 64]);
      }
    }

    try {
      for (int i = 0; i < 120; i++) {
        final useCache = i > 0;
        final currentTokens = useCache ? [tokens.last] : tokens;
        final idsOrt = await OrtValue.fromList(Int64List.fromList(currentTokens), [1, currentTokens.length]);
        final cacheOrt = await OrtValue.fromList([useCache], [1]);

        final outputs = await decoder.run({
          'input_ids': idsOrt,
          'encoder_hidden_states': audioFeatures,
          'use_cache_branch': cacheOrt,
          ...pastKV
        });

        final logitsVal = await outputs['logits']!.asList();
        final lastLogits = (logitsVal[0] as List).last as List;
        int nextToken = -1; double maxLogit = -double.infinity;
        for (int j = 0; j < 50364; j++) {
          double val = (lastLogits[j] as num).toDouble();
          if (tokenCounts[j] >= 3) val = val > 0 ? val / 1.15 : val * 1.15;
          if (val > maxLogit) { maxLogit = val; nextToken = j; }
        }

        if (nextToken == -1 || nextToken == 50257) break;
        tokens.add(nextToken); tokenCounts[nextToken]++;

        // 1. 3-gram repetition blocking
        const int n = 3;
        if (tokens.length >= n * 3 + promptLength) {
          final tail = tokens.sublist(tokens.length - n);
          bool hasLoop = true;
          for (int r = 1; r < 3; r++) {
            final start = tokens.length - n * (r + 1);
            if (!listEquals(tail, tokens.sublist(start, start + n))) {
              hasLoop = false; break;
            }
          }
          if (hasLoop) {
            tokens.removeRange(tokens.length - n * 2, tokens.length);
            break;
          }
        }

        // 2. Punctuation loop check
        if (tokens.length > 5 && nextToken < 100) {
          int repeatCount = 0;
          for (int k = tokens.length - 1; k >= tokens.length - 5; k--) {
            if (tokens[k] == nextToken) repeatCount++;
          }
          if (repeatCount >= 4) break;
        }

        // 3. Unique token ratio check
        if (tokens.length > 15 + promptLength) {
          final genOnly = tokens.sublist(promptLength);
          final ratio = genOnly.toSet().length / genOnly.length;
          if (ratio < 0.3) break;
        }

        final nextKV = <String, OrtValue>{};
        for (int l = 0; l < numLayers; l++) {
          for (final kv in ['key', 'value']) {
            final dIn = 'past_key_values.$l.decoder.$kv', dOut = 'present.$l.decoder.$kv';
            nextKV[dIn] = outputs.containsKey(dOut) ? outputs.remove(dOut)! : pastKV[dIn]!;
            final eIn = 'past_key_values.$l.encoder.$kv', eOut = 'present.$l.encoder.$kv';
            nextKV[eIn] = (i == 0 && outputs.containsKey(eOut)) ? outputs.remove(eOut)! : pastKV[eIn]!;
            if (nextKV[dIn] != pastKV[dIn]) pastKV[dIn]?.dispose();
            if (nextKV[eIn] != pastKV[eIn]) pastKV[eIn]?.dispose();
          }
        }
        pastKV = nextKV;
        await idsOrt.dispose(); await cacheOrt.dispose();
        for (var o in outputs.values) await o.dispose();
      }
    } finally {
      await inputOrt.dispose();
      for (var o in encOut.values) await o.dispose();
      for (var v in pastKV.values) await v.dispose();
    }

    String text = tokenizer.decode(tokens);
    final hallucinations = ['thank you for watching', 'thanks for watching', '[music]', '(music)', '♪', 'unintelligible'];
    final lowerText = text.toLowerCase();
    if (hallucinations.any((h) => lowerText == h || (lowerText.contains(h) && text.length < h.length + 5))) {
      return '';
    }
    return text;
  }
}

// ==========================================
// 6. TRANSLATION ENGINE (Opus-MT)
// ==========================================
class TranslationEngine {
  final OrtSession encoder;
  final OrtSession decoder;
  final SimpleTokenizer tokenizer;
  final int startToken;
  final int eosToken;

  TranslationEngine(this.encoder, this.decoder, this.tokenizer, {this.startToken = 59513, this.eosToken = 0});

  static Future<TranslationEngine> load(String modelDir) async {
    final tokenizer = await SimpleTokenizer.load(await io.File(p.join(modelDir, 'vocab.json')).readAsString());
    int start = 59513, eos = 0;
    final configFile = io.File(p.join(modelDir, 'config.json'));
    if (await configFile.exists()) {
      final config = jsonDecode(await configFile.readAsString());
      start = config['decoder_start_token_id'] ?? config['pad_token_id'] ?? start;
      eos = config['eos_token_id'] ?? eos;
    }
    return TranslationEngine(
      await OnnxRuntime().createSession(p.join(modelDir, 'encoder_model_quantized.onnx')),
      await OnnxRuntime().createSession(p.join(modelDir, 'decoder_model_merged_quantized.onnx')),
      tokenizer,
      startToken: start,
      eosToken: eos,
    );
  }

  Future<String> translate(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return '';

    final inputIds = List<int>.from(tokenizer.encode(clean));
    if (inputIds.isEmpty || inputIds.last != eosToken) inputIds.add(eosToken);

    final idsOrt = await OrtValue.fromList(Int64List.fromList(inputIds), [1, inputIds.length]);
    final maskData = Int64List.fromList(List.filled(inputIds.length, 1));
    final maskOrt = await OrtValue.fromList(maskData, [1, inputIds.length]);

    final encOut = await encoder.run({'input_ids': idsOrt, 'attention_mask': maskOrt});
    final encoderHiddenStates = encOut['last_hidden_state']!;

    final tokens = <int>[startToken];
    final maxNewTokens = (inputIds.length * 3 + 16).clamp(10, 256);
    final hasEncoderMask = decoder.inputNames.contains('encoder_attention_mask');

    int numLayers = 0;
    while (decoder.inputNames.contains('past_key_values.$numLayers.decoder.key')) numLayers++;
    int numHeads = encoderHiddenStates.shape[2] ~/ 64;

    Map<String, OrtValue> pastKV = {};
    for (int i = 0; i < numLayers; i++) {
      for (final part in ['decoder', 'encoder']) {
        for (final kv in ['key', 'value']) {
          pastKV['past_key_values.$i.$part.$kv'] = await OrtValue.fromList(Float32List(0), [1, numHeads, 0, 64]);
        }
      }
    }

    try {
      for (int i = 0; i < maxNewTokens; i++) {
        final useCache = i > 0;
        final currentTokens = useCache ? [tokens.last] : tokens;
        final idsInOrt = await OrtValue.fromList(Int64List.fromList(currentTokens), [1, currentTokens.length]);
        final cacheOrt = await OrtValue.fromList([useCache], [1]);

        final inputs = {
          'input_ids': idsInOrt,
          'encoder_hidden_states': encoderHiddenStates,
          'use_cache_branch': cacheOrt,
          if (hasEncoderMask) 'encoder_attention_mask': maskOrt,
          ...pastKV,
        };

        final outputs = await decoder.run(inputs);
        final logitsVal = await outputs['logits']!.asList();
        final lastLogits = (logitsVal[0] as List).last as List;

        int nextToken = -1; double maxLogit = -double.infinity;
        for (int j = 0; j < lastLogits.length; j++) {
          if (j == startToken) continue;
          double val = (lastLogits[j] as num).toDouble();
          if (tokens.contains(j)) val = val > 0 ? val / 1.2 : val * 1.2;
          if (val > maxLogit) { maxLogit = val; nextToken = j; }
        }

        if (nextToken == -1 || nextToken == eosToken) break;
        tokens.add(nextToken);

        final nextKV = <String, OrtValue>{};
        for (int l = 0; l < numLayers; l++) {
          for (final kv in ['key', 'value']) {
            final dIn = 'past_key_values.$l.decoder.$kv', dOut = 'present.$l.decoder.$kv';
            nextKV[dIn] = outputs.containsKey(dOut) ? outputs.remove(dOut)! : pastKV[dIn]!;
            final eIn = 'past_key_values.$l.encoder.$kv', eOut = 'present.$l.encoder.$kv';
            nextKV[eIn] = (i == 0 && outputs.containsKey(eOut)) ? outputs.remove(eOut)! : pastKV[eIn]!;
            if (nextKV[dIn] != pastKV[dIn]) pastKV[dIn]?.dispose();
            if (nextKV[eIn] != pastKV[eIn]) pastKV[eIn]?.dispose();
          }
        }
        pastKV = nextKV;
        await idsInOrt.dispose(); await cacheOrt.dispose();
        for (var o in outputs.values) await o.dispose();
      }
    } finally {
      await idsOrt.dispose(); await maskOrt.dispose();
      for (var o in encOut.values) await o.dispose();
      for (var v in pastKV.values) await v.dispose();
    }

    return tokenizer.decode(tokens.skip(1).toList()).replaceAll('▁', ' ').replaceAll(' ', ' ').trim();
  }
}

// ==========================================
// 7. MAIN FLOW
// ==========================================
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  String? videoPath = io.Platform.environment['VIDEO_PATH'];
  if (videoPath == null || videoPath.isEmpty) {
    // Fallback for manual testing if needed
    videoPath = 'test.mp4';
  }

  if (videoPath == null) {
    print('\x1B[31mError: No video path provided.\x1B[0m');
    print('Usage: flutter test tool/debug_stt.dart -- <video_path>');
    return;
  }

  final modelDir = p.join(io.Directory.current.path, 'ai_models');
  print('\x1B[36m[STT DEBUG] Processing: $videoPath\x1B[0m');

  String ffmpeg = 'ffmpeg';
  if (io.Platform.isWindows) {
    final possiblePaths = [
      io.Platform.environment['FFMPEG_PATH'],
      r'D:\Ultimate Vocal Remover\ffmpeg.exe',
      r'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
    ];
    for (final path in possiblePaths) {
      if (path != null && io.File(path).existsSync()) {
        ffmpeg = path;
        break;
      }
    }
  }

  final tempPcm = io.File('debug_input.pcm');
  final ff = await io.Process.run(ffmpeg, [
    '-y', '-i', videoPath, '-vn', '-af', 'pan=mono|c0=0.5*c0+0.5*c1,highpass=f=80,lowpass=f=7500,afftdn=nf=-25',
    '-ar', '16000', '-ac', '1', '-f', 's16le', tempPcm.path
  ]);
  if (ff.exitCode != 0) { print('FFmpeg Error: ${ff.stderr}'); return; }

  final vad = LocalVadEngine(await OnnxRuntime().createSession(p.join(modelDir, 'vad_silero', 'silero_vad.onnx')));
  final sttId = 'stt_whisper_base_en_vi';
  final tokenizer = await SimpleTokenizer.load(await io.File(p.join(modelDir, sttId, 'vocab.json')).readAsString());
  final stt = WhisperEngine(
    await OnnxRuntime().createSession(p.join(modelDir, sttId, 'encoder_model_quantized.onnx')),
    await OnnxRuntime().createSession(p.join(modelDir, sttId, 'decoder_model_merged_quantized.onnx')),
    tokenizer
  );

  TranslationEngine? translator;
  final transId = 'translate_opus_en_vi';
  if (await io.Directory(p.join(modelDir, transId)).exists()) {
    print('\x1B[36m[STT DEBUG] Loading Translation Model...\x1B[0m');
    translator = await TranslationEngine.load(p.join(modelDir, transId));
  } else {
    print('\x1B[33m[STT DEBUG] Translation model not found. Proceeding with STT only.\x1B[0m');
  }

  final bytes = await tempPcm.readAsBytes();
  final List<TimedTextSegment> results = [];
  List<PcmChunk> activeChunks = [], preRoll = [], pending = [];
  Duration? start;

  Future<void> processSegment(Duration s, Duration e, List<Uint8List> chunks) async {
    final text = await stt.transcribe(chunks);
    if (text.isNotEmpty) {
      String? translated;
      if (translator != null) {
        translated = await translator.translate(text);
      }
      results.add(TimedTextSegment(start: s, end: e, text: text, translatedText: translated));
      final display = translated != null ? '$text -> $translated' : text;
      print('\x1B[32m[${results.length}] ${_format(s)}: $display\x1B[0m');
    }
  }

  for (int i = 0; i < bytes.length; i += 1024) {
    if (i + 1024 > bytes.length) break;
    final chunkBytes = bytes.sublist(i, i + 1024);
    final pts = Duration(milliseconds: (i ~/ 32));
    final chunk = PcmChunk(pts: pts, sampleRate: 16000, channels: 1, bytes: chunkBytes);

    if (await vad.isSpeech(chunkBytes)) {
      if (start == null) {
        start = preRoll.isNotEmpty ? preRoll.first.pts : pts;
        activeChunks = [...preRoll];
      }
      activeChunks.addAll(pending); pending.clear(); activeChunks.add(chunk);
      if (pts + const Duration(milliseconds: 32) - start! >= vad.maxSpeechDuration) {
        await processSegment(start, pts, activeChunks.map((c) => c.bytes).toList());
        start = null; activeChunks = []; vad.resetState();
      }
    } else {
      if (start != null) {
        pending.add(chunk);
        if (pts - pending.first.pts > vad.maxMergeGap) {
          if (pts - start! >= vad.minSpeechDuration) {
            final postRollCount = (vad.postRollDuration.inMilliseconds ~/ 32);
            activeChunks.addAll(pending.take(math.min(postRollCount, pending.length)));
            await processSegment(start, activeChunks.last.pts, activeChunks.map((c) => c.bytes).toList());
          }
          start = null; activeChunks = []; pending = []; vad.resetState();
        }
      } else {
        preRoll.add(chunk); if (preRoll.length > 5) preRoll.removeAt(0);
      }
    }
  }

  // Final flush
  if (start != null && activeChunks.isNotEmpty) {
    if (pending.isNotEmpty) {
      final postRollCount = (vad.postRollDuration.inMilliseconds ~/ 32);
      activeChunks.addAll(pending.take(math.min(postRollCount, pending.length)));
    }
    await processSegment(start, activeChunks.last.pts, activeChunks.map((c) => c.bytes).toList());
  }

  final srt = io.File(p.setExtension(videoPath, '.srt')).openWrite();
  for (int i = 0; i < results.length; i++) {
    srt.writeln('${i + 1}');
    srt.writeln('${_format(results[i].start)} --> ${_format(results[i].end)}');
    srt.writeln('${results[i].translatedText ?? results[i].text}\n');
  }
  await srt.close();
  print('\x1B[36mDone: ${results.length} segments exported to SRT.\x1B[0m');
  if (tempPcm.existsSync()) tempPcm.deleteSync();
  io.exit(0);
}

String _format(Duration d) {
  String f(int n) => n.toString().padLeft(2, '0');
  String ms(int n) => n.toString().padLeft(3, '0');
  return '${f(d.inHours)}:${f(d.inMinutes % 60)}:${f(d.inSeconds % 60)},${ms(d.inMilliseconds % 1000)}';
}
