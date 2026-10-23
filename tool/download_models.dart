
import 'dart:io';
import 'package:path/path.dart' as p;

const String whisperBase = 'https://huggingface.co/Xenova/whisper-base/resolve/d33af214c6ab08c278d722454aaac60f04599f8e';
const String sileroBase = 'https://raw.githubusercontent.com/snakers4/silero-vad/60b7ffa243625ebdc1070275a29f18c87843786a/src/silero_vad/data';

final modelsToDownload = {
  'vad_silero': [
    '$sileroBase/silero_vad.onnx',
  ],
  'stt_whisper_base_en_vi': [
    '$whisperBase/onnx/encoder_model_quantized.onnx',
    '$whisperBase/onnx/decoder_model_merged_quantized.onnx',
    '$whisperBase/config.json',
    '$whisperBase/tokenizer.json',
    '$whisperBase/vocab.json',
    '$whisperBase/merges.txt',
    '$whisperBase/preprocessor_config.json',
  ],
};

Future<void> main(List<String> args) async {
  final String targetDir = args.isNotEmpty ? args[0] : p.join(Directory.current.path, 'ai_models');
  print('Target directory: $targetDir');

  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 30);

  try {
    for (var entry in modelsToDownload.entries) {
      final modelId = entry.key;
      final urls = entry.value;
      final modelPath = Directory(p.join(targetDir, modelId));

      if (!await modelPath.exists()) {
        await modelPath.create(recursive: true);
      }

      for (var url in urls) {
        final fileName = p.basename(url);
        final filePath = p.join(modelPath.path, fileName);
        final file = File(filePath);

        if (await file.exists()) {
          print('Skipping $fileName (already exists)');
          continue;
        }

        print('Downloading $fileName...');
        await _downloadFile(client, url, file);
      }
    }
    print('\nAll models downloaded successfully to $targetDir');
    print('\nNow you can run debug script:');
    print('dart tool/debug_stt.dart test.mp4 "$targetDir"');
  } finally {
    client.close();
  }
}

Future<void> _downloadFile(HttpClient client, String url, File file) async {
  final request = await client.getUrl(Uri.parse(url));
  final response = await request.close();

  if (response.statusCode != 200) {
    throw Exception('Failed to download $url: HTTP ${response.statusCode}');
  }

  final total = response.contentLength;
  int received = 0;

  final sink = file.openWrite();
  await response.map((chunk) {
    received += chunk.length;
    if (total != -1) {
      final progress = (received / total * 100).toStringAsFixed(1);
      stdout.write('\rProgress: $progress% ($received/$total)');
    }
    return chunk;
  }).pipe(sink);
  stdout.write('\n');
}
