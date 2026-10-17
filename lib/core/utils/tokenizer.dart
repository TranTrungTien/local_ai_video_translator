import 'dart:convert';

/// A simplified BPE/WordPiece tokenizer for local ONNX models.
class SimpleTokenizer {
  SimpleTokenizer._(this._vocab, this._specialTokens);

  final Map<String, int> _vocab;
  final Map<String, int> _specialTokens;
  final Map<int, String> _invVocab = {};

  static Future<SimpleTokenizer> load(String vocabJson) async {
    final Map<String, dynamic> data = jsonDecode(vocabJson);
    final vocab = <String, int>{};
    final special = <String, int>{};

    data.forEach((key, value) {
      // Nhận diện các định dạng token đặc biệt phổ biến: <|...|>, [CLS], </s>, >>lang<<, etc.
      final isSpecial = (key.startsWith('<|') && key.endsWith('|>')) ||
          (key.startsWith('[') && key.endsWith(']')) ||
          (key.startsWith('>>') && key.endsWith('<<')) ||
          (key.startsWith('<') && key.endsWith('>') && key.length <= 6) ||
          key == '</s>' ||
          key == '<mask>';

      if (isSpecial) {
        special[key] = value;
      }
      vocab[key] = value;
    });

    final tokenizer = SimpleTokenizer._(vocab, special);
    vocab.forEach((key, value) {
      tokenizer._invVocab[value] = key;
    });
    return tokenizer;
  }

  /// Encodes text using greedy longest-match (essential for BPE/SentencePiece).
  List<int> encode(String text, {bool addWhisperTokens = false, String? lang}) {
    final tokens = <int>[];

    // Prepend Whisper special tokens if required
    if (addWhisperTokens) {
      tokens.add(_specialTokens['<|startoftranscript|>'] ?? 50257);
      if (lang == 'vi') tokens.add(_specialTokens['<|vi|>'] ?? 50275);
      tokens.add(_specialTokens['<|transcribe|>'] ?? 50359);
      tokens.add(_specialTokens['<|notimestamps|>'] ?? 50362);
    }

    // Normalizing space to the special meta-character ' ' (U+2581)
    // SentencePiece/Marian uses this to distinguish word boundaries.
    final normalized = '\u2581${text.toLowerCase().replaceAll(' ', '\u2581')}';
    int start = 0;
    while (start < normalized.length) {
      bool found = false;
      for (int end = normalized.length; end > start; end--) {
        final sub = normalized.substring(start, end);
        if (_vocab.containsKey(sub)) {
          tokens.add(_vocab[sub]!);
          start = end;
          found = true;
          break;
        }
      }
      if (!found) {
        final char = normalized[start];
        tokens.add(_vocab[char] ?? _specialTokens['<|unk|>'] ?? _specialTokens['<unk>'] ?? 3);
        start++;
      }
    }

    if (addWhisperTokens) {
      tokens.add(_specialTokens['<|endoftranscript|>'] ?? 50256);
    }
    return tokens;
  }

  String decode(List<int> tokens) {
    return tokens
        .map((t) => _invVocab[t] ?? '')
        .where((s) => !s.startsWith('<|') && s != '</s>' && s != '<unk>') // Filter special tokens
        .join('')
        .replaceAll('\u2581', ' ')
        .trim();
  }
}
