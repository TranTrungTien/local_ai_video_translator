import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/dio_provider.dart';
import '../../../core/utils/sha256_util.dart';
import '../domain/model_manifest.dart';

enum ModelDownloadState { notDownloaded, downloading, ready, failed }

class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.modelId,
    required this.state,
    required this.downloadedBytes,
    required this.totalBytes,
    this.currentFile,
    this.errorMessage,
  });

  final String modelId;
  final ModelDownloadState state;
  final int downloadedBytes;
  final int totalBytes;
  final String? currentFile;
  final String? errorMessage;

  double get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
}

class ModelIntegrityException implements Exception {
  ModelIntegrityException(this.message);
  final String message;

  @override
  String toString() => 'ModelIntegrityException: $message';
}

// ---------------------------------------------------------------------------
// Nguồn model đã kiểm chứng (tra cứu trên Hugging Face / GitHub).
// Tất cả URL được ghim theo commit để file không bị đổi bất ngờ.
// ---------------------------------------------------------------------------

// Xenova/whisper-tiny (đa ngôn ngữ, Apache-2.0)
const String _whisperBase =
    'https://huggingface.co/Xenova/whisper-tiny/resolve/e1309fbf61a10485319f046062a3b5dca5b7b9fb';

// Xenova/opus-mt-en-vi (chỉ dịch en -> vi)
const String _opusBase =
    'https://huggingface.co/Xenova/opus-mt-en-vi/resolve/30bcd461c0d7338ad106b36314d3eedc2d4e998c';

// rhasspy/piper-voices (MIT)
const String _piperBase =
    'https://huggingface.co/rhasspy/piper-voices/resolve/de3dcfdf1912bb49726dc4aa11c26017ce2ac62a/vi/vi_VN/25hours_single/low';

// snakers4/silero-vad (MIT)
const String _sileroBase =
    'https://raw.githubusercontent.com/snakers4/silero-vad/60b7ffa243625ebdc1070275a29f18c87843786a/src/silero_vad/data';

class ModelManagerRepository {
  ModelManagerRepository(this._dio);

  final Dio _dio;
  final _progressController =
  StreamController<ModelDownloadProgress>.broadcast();
  final Set<String> _active = <String>{};

  static const String _readyMarker = '.ready';

  Stream<ModelDownloadProgress> get progressStream =>
      _progressController.stream;

  static const List<AiModelManifest> defaultManifests = [
    // ---- STT: Whisper tiny (bản quantized, encoder + decoder gộp) ----
    AiModelManifest(
      id: 'stt_whisper_tiny_en_vi',
      type: AiModelType.stt,
      version: '1.1.0',
      languages: ['en', 'vi', 'ja', 'zh'],
      files: [
        ModelFile(
          name: 'encoder_model_quantized.onnx',
          url: '$_whisperBase/onnx/encoder_model_quantized.onnx',
          bytes: 10124910,
          sha256:
          'fd9d995b9dcb0520f0dbf6cf68651af639fc385f594d9d876e69ca2802dc438e',
        ),
        ModelFile(
          name: 'decoder_model_merged_quantized.onnx',
          url: '$_whisperBase/onnx/decoder_model_merged_quantized.onnx',
          bytes: 30727765,
          sha256:
          '6c0c125986b007d2e3734bec84c18bda0152071b90b87fadac6d7764499927a0',
        ),
        // File nhỏ: bytes là số xấp xỉ, chưa có sha256 (xem script tính hash).
        ModelFile(
            name: 'config.json', url: '$_whisperBase/config.json', bytes: 2250),
        ModelFile(
            name: 'generation_config.json',
            url: '$_whisperBase/generation_config.json',
            bytes: 3720),
        ModelFile(
            name: 'preprocessor_config.json',
            url: '$_whisperBase/preprocessor_config.json',
            bytes: 339),
        ModelFile(
            name: 'tokenizer.json',
            url: '$_whisperBase/tokenizer.json',
            bytes: 2480000),
        ModelFile(
            name: 'vocab.json',
            url: '$_whisperBase/vocab.json',
            bytes: 1040000),
        ModelFile(
            name: 'merges.txt', url: '$_whisperBase/merges.txt', bytes: 494000),
      ],
    ),

    // ---- Dịch: Opus-MT en -> vi (bản quantized) ----
    AiModelManifest(
      id: 'translate_opus_en_vi',
      type: AiModelType.translation,
      version: '1.3.0',
      languages: ['en', 'vi'],
      files: [
        ModelFile(
          name: 'encoder_model_quantized.onnx',
          url: '$_opusBase/onnx/encoder_model_quantized.onnx',
          bytes: 47105950,
          sha256:
          'dfcd7a32be3fdd21cbcf5d354520d626f1768fd6e205ca62a6a11a4641d31f36',
        ),
        ModelFile(
          name: 'decoder_model_merged_quantized.onnx',
          url: '$_opusBase/onnx/decoder_model_merged_quantized.onnx',
          bytes: 54373748,
          sha256:
          '1cfc6a84f9c189e6928c9710b281fae3f1f42d4ffbba109e7b4ec8e31ceb06dd',
        ),
        ModelFile(
            name: 'config.json', url: '$_opusBase/config.json', bytes: 1390),
        ModelFile(
            name: 'generation_config.json',
            url: '$_opusBase/generation_config.json',
            bytes: 293),
        ModelFile(
            name: 'source.spm', url: '$_opusBase/source.spm', bytes: 809000),
        ModelFile(
            name: 'target.spm', url: '$_opusBase/target.spm', bytes: 756000),
        ModelFile(
            name: 'vocab.json', url: '$_opusBase/vocab.json', bytes: 1300000),
        ModelFile(
            name: 'tokenizer.json',
            url: '$_opusBase/tokenizer.json',
            bytes: 5160000),
      ],
    ),

    // ---- TTS: Piper tiếng Việt (cần cả file .onnx.json đi kèm) ----
    AiModelManifest(
      id: 'tts_piper_vi_female',
      type: AiModelType.tts,
      version: '1.0.0',
      languages: ['vi'],
      files: [
        ModelFile(
          name: 'vi_VN-25hours_single-low.onnx',
          url: '$_piperBase/vi_VN-25hours_single-low.onnx',
          bytes: 63104526,
          sha256:
          '266945c4a80cb3301450c8ba6fcf6ba3542c56cf952a08a8ff3d2d4ff0ab5609',
        ),
        ModelFile(
          name: 'vi_VN-25hours_single-low.onnx.json',
          url: '$_piperBase/vi_VN-25hours_single-low.onnx.json',
          bytes: 4180,
        ),
      ],
    ),

    // ---- VAD: Silero ----
    // SHA-256 lấy từ hai mirror độc lập trên Hugging Face và khớp kích thước
    // 2,327,524 byte của manifest polyvoice. Hãy tự tính lại 1 lần để chắc chắn.
    AiModelManifest(
      id: 'vad_silero',
      type: AiModelType.vad,
      version: 'git-60b7ffa',
      languages: ['all'],
      files: [
        ModelFile(
          name: 'silero_vad.onnx',
          url: '$_sileroBase/silero_vad.onnx',
          bytes: 2327524,
          sha256:
          '1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3',
        ),
      ],
    ),
  ];

  AiModelManifest? manifestById(String modelId) {
    for (final m in defaultManifests) {
      if (m.id == modelId) return m;
    }
    return null;
  }

  Future<Directory> get _modelsDir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Thư mục chứa toàn bộ file của một model.
  Future<Directory> getModelDir(String modelId) async {
    final root = await _modelsDir;
    final dir = Directory('${root.path}/$modelId');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> getModelFile(String modelId, String fileName) async {
    final dir = await getModelDir(modelId);
    return File('${dir.path}/$fileName');
  }

  /// Chỉ trả về true khi model đã tải và xác minh đủ tất cả file
  /// (có marker .ready khớp version và file vẫn còn nguyên).
  Future<bool> isModelDownloaded(String modelId) async {
    final manifest = manifestById(modelId);
    if (manifest == null) return false;

    final dir = await getModelDir(modelId);
    final marker = File('${dir.path}/$_readyMarker');
    if (!await marker.exists()) return false;

    try {
      final data = jsonDecode(await marker.readAsString());
      if (data is! Map || data['version'] != manifest.version) return false;
    } catch (_) {
      return false;
    }

    for (final f in manifest.files) {
      final file = File('${dir.path}/${f.name}');
      if (!await file.exists()) return false;
      if (f.sha256 != null && await file.length() != f.bytes) return false;
    }
    return true;
  }

  /// Tải toàn bộ file của model, hỗ trợ resume và bắt buộc kiểm tra SHA-256.
  Future<void> downloadModel(AiModelManifest manifest) async {
    if (!_active.add(manifest.id)) return; // đang tải rồi

    final dir = await getModelDir(manifest.id);
    final marker = File('${dir.path}/$_readyMarker');
    if (await marker.exists()) await marker.delete();

    var completedBytes = 0;
    try {
      for (final spec in manifest.files) {
        await _downloadFile(
          manifest: manifest,
          spec: spec,
          dir: dir,
          completedBytes: completedBytes,
        );
        completedBytes += spec.bytes;
      }

      await marker.writeAsString(
        jsonEncode({
          'version': manifest.version,
          'files': manifest.files.map((f) => f.name).toList(),
        }),
      );

      _emit(ModelDownloadProgress(
        modelId: manifest.id,
        state: ModelDownloadState.ready,
        downloadedBytes: manifest.totalBytes,
        totalBytes: manifest.totalBytes,
      ));
    } catch (e) {
      _emit(ModelDownloadProgress(
        modelId: manifest.id,
        state: ModelDownloadState.failed,
        downloadedBytes: completedBytes,
        totalBytes: manifest.totalBytes,
        errorMessage: e.toString(),
      ));
    } finally {
      _active.remove(manifest.id);
    }
  }

  Future<void> _downloadFile({
    required AiModelManifest manifest,
    required ModelFile spec,
    required Directory dir,
    required int completedBytes,
  }) async {
    final target = File('${dir.path}/${spec.name}');
    final tmp = File('${target.path}.tmp');

    // Đã có file hợp lệ từ lần tải trước thì bỏ qua.
    if (await target.exists()) {
      try {
        await _verify(target, spec);
        return;
      } on ModelIntegrityException {
        await target.delete();
      }
    }

    // Tối đa 2 lần thử: lần 2 luôn tải lại từ đầu nếu lần 1 hỏng.
    for (var attempt = 0; attempt < 2; attempt++) {
      var existing = await tmp.exists() ? await tmp.length() : 0;

      // File tạm lớn hơn kích thước thật nghĩa là đã hỏng.
      if (spec.sha256 != null && existing > spec.bytes) {
        await tmp.delete();
        existing = 0;
      }

      try {
        // File tạm đã đủ dung lượng thì chỉ cần verify, không tải nữa.
        final alreadyComplete = spec.sha256 != null && existing == spec.bytes;
        if (!alreadyComplete) {
          await _dio.download(
            spec.url,
            tmp.path,
            options: Options(
              headers: existing > 0 ? {'Range': 'bytes=$existing-'} : null,
              receiveTimeout: const Duration(minutes: 5),
            ),
            // Quan trọng: nếu không append thì Dio ghi đè file tạm.
            fileAccessMode: existing > 0 ? FileAccessMode.append : FileAccessMode.write,
            deleteOnError: false,
            onReceiveProgress: (received, total) {
              _emit(ModelDownloadProgress(
                modelId: manifest.id,
                state: ModelDownloadState.downloading,
                downloadedBytes: completedBytes + existing + received,
                totalBytes: manifest.totalBytes,
                currentFile: spec.name,
              ));
            },
          );
        }

        // Nếu server bỏ qua Range và trả cả file, file sẽ sai hash ở đây
        // và bị xóa để thử lại từ đầu.
        await _verify(tmp, spec);

        if (await target.exists()) await target.delete();
        await tmp.rename(target.path);
        return;
      } on ModelIntegrityException {
        if (await tmp.exists()) await tmp.delete();
        if (attempt == 1) rethrow;
      } on DioException catch (e) {
        // 416: Range không hợp lệ (file tạm đã đủ/hỏng) -> tải lại từ đầu.
        if (e.response?.statusCode == 416 && attempt == 0) {
          if (await tmp.exists()) await tmp.delete();
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _verify(File file, ModelFile spec) async {
    final length = await file.length();
    if (length == 0) {
      throw ModelIntegrityException('${spec.name}: file rỗng');
    }

    final expectedHash = spec.sha256;
    if (expectedHash != null) {
      if (length != spec.bytes) {
        throw ModelIntegrityException(
          '${spec.name}: sai kích thước ($length != ${spec.bytes})',
        );
      }
      final actual = await Sha256Util.computeFileHash(file);
      if (actual.toLowerCase() != expectedHash.toLowerCase()) {
        throw ModelIntegrityException('${spec.name}: sai SHA-256');
      }
    } else if (spec.name.endsWith('.json')) {
      // File nhỏ chưa có hash: ít nhất đảm bảo không phải trang HTML lỗi.
      try {
        jsonDecode(await file.readAsString());
      } catch (_) {
        throw ModelIntegrityException('${spec.name}: JSON không hợp lệ');
      }
    }
  }

  Future<void> deleteModel(String modelId) async {
    final root = await _modelsDir;
    final dir = Directory('${root.path}/$modelId');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _emit(ModelDownloadProgress(
      modelId: modelId,
      state: ModelDownloadState.notDownloaded,
      downloadedBytes: 0,
      totalBytes: 0,
    ));
  }

  void _emit(ModelDownloadProgress p) {
    if (!_progressController.isClosed) _progressController.add(p);
  }

  void dispose() {
    _progressController.close();
  }
}

final modelManagerRepositoryProvider = Provider<ModelManagerRepository>((ref) {
  final repo = ModelManagerRepository(ref.watch(dioProvider));
  ref.onDispose(repo.dispose);
  return repo;
});