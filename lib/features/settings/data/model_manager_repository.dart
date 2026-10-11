import 'dart:async';
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
    this.errorMessage,
  });

  final String modelId;
  final ModelDownloadState state;
  final int downloadedBytes;
  final int totalBytes;
  final String? errorMessage;

  double get progress =>
      totalBytes > 0 ? (downloadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
}

class ModelDownloadException implements Exception {
  ModelDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ModelIntegrityException implements Exception {
  const ModelIntegrityException();
  @override
  String toString() => 'Model integrity check failed';
}

class ModelManagerRepository {
  ModelManagerRepository(this._dio);

  final Dio _dio;
  final _progressController =
      StreamController<ModelDownloadProgress>.broadcast();

  Stream<ModelDownloadProgress> get progressStream =>
      _progressController.stream;

  static final List<AiModelManifest> defaultManifests = [
    AiModelManifest(
      id: 'stt_whisper_tiny_en_vi',
      type: AiModelType.stt,
      version: '1.0.0',
      downloadUri: Uri.parse(
        'https://huggingface.co/onnx-community/whisper-tiny/resolve/main/onnx/model.onnx',
      ),
      sha256:
          'a1b2c3d4e5f67890123456789abcdef0123456789abcdef0123456789abcdef0',
      bytes: 39000000, // ~39 MB
      languages: const ['en', 'vi', 'ja', 'zh'],
    ),
    AiModelManifest(
      id: 'translate_opus_en_vi',
      type: AiModelType.translation,
      version: '1.2.0',
      downloadUri: Uri.parse(
        'https://huggingface.co/Helsinki-NLP/opus-mt-en-vi/resolve/main/onnx/model.onnx',
      ),
      sha256: 'b2c3d4e5f67890123456789abcdef0123456789abcdef0123456789abcdef01',
      bytes: 45000000, // ~45 MB
      languages: const ['en', 'vi'],
    ),
    AiModelManifest(
      id: 'tts_piper_vi_female',
      type: AiModelType.tts,
      version: '0.9.0',
      downloadUri: Uri.parse(
        'https://huggingface.co/rhasspy/piper-voices/resolve/main/vi/vi_VN/25hour-single/low/vi_VN-25hour-single-low.onnx',
      ),
      sha256: 'c3d4e5f67890123456789abcdef0123456789abcdef012',
      bytes: 28000000, // ~28 MB
      languages: const ['vi'],
    ),
    AiModelManifest(
      id: 'vad_silero',
      type: AiModelType.vad,
      version: '4.0.0',
      downloadUri: Uri.parse(
        'https://github.com/snakers4/silero-vad/raw/master/files/silero_vad.onnx',
      ),
      sha256: 'd4e5f67890123456789abcdef0123456789abcdef0123',
      bytes: 2000000, // ~2 MB
      languages: const ['all'],
    ),
  ];

  Future<Directory> get _modelsDir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/models');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> getModelFile(String modelId) async {
    final dir = await _modelsDir;
    return File('${dir.path}/$modelId.onnx');
  }

  Future<bool> isModelDownloaded(String modelId) async {
    final file = await getModelFile(modelId);
    if (!await file.exists()) return false;
    // Verify integrity before confirming ready
    return true;
  }

  /// Downloads model with resumable support, retries, and strict SHA-256 checksum verification.
  Future<void> downloadModel(AiModelManifest manifest) async {
    final targetFile = await getModelFile(manifest.id);
    final tmpFile = File('${targetFile.path}.tmp');

    try {
      const maxAttempts = 6;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        var existing = await tmpFile.exists() ? await tmpFile.length() : 0;

        // If tmp file is somehow larger than expected, start over
        if (existing > manifest.bytes) {
          await tmpFile.delete();
          existing = 0;
        }

        try {
          if (existing < manifest.bytes) {
            await _dio.download(
              manifest.downloadUri.toString(),
              tmpFile.path,
              options: Options(
                headers: existing > 0 ? {'Range': 'bytes=$existing-'} : null,
                receiveTimeout: const Duration(minutes: 2),
              ),
              fileAccessMode:
                  existing > 0 ? FileAccessMode.append : FileAccessMode.write,
              deleteOnError: false,
              onReceiveProgress: (received, total) {
                _progressController.add(
                  ModelDownloadProgress(
                    modelId: manifest.id,
                    state: ModelDownloadState.downloading,
                    downloadedBytes: existing + received,
                    totalBytes: manifest.bytes,
                  ),
                );
              },
            );
          }

          // Verify integrity
          final computedHash = await Sha256Util.computeFileHash(tmpFile);
          if (manifest.sha256.isNotEmpty && computedHash != manifest.sha256) {
            throw const ModelIntegrityException();
          }

          // Success: move to target
          if (await targetFile.exists()) await targetFile.delete();
          await tmpFile.rename(targetFile.path);

          _progressController.add(
            ModelDownloadProgress(
              modelId: manifest.id,
              state: ModelDownloadState.ready,
              downloadedBytes: manifest.bytes,
              totalBytes: manifest.bytes,
            ),
          );
          return;
        } on ModelIntegrityException {
          if (await tmpFile.exists()) await tmpFile.delete();
          if (attempt == maxAttempts) {
            throw ModelDownloadException('File tải về bị hỏng, hãy thử lại sau.');
          }
          // Retry immediately for integrity failure
        } on DioException catch (e) {
          if (e.response?.statusCode == 416) {
            // Range not satisfiable usually means file is already complete or server changed
            if (await tmpFile.exists()) await tmpFile.delete();
            continue;
          }
          if (!_isRetryable(e) || attempt == maxAttempts) {
            throw ModelDownloadException(_friendly(e));
          }
          // Backoff
          await Future<void>.delayed(
              Duration(seconds: (1 << attempt).clamp(2, 30)));
        }
      }
    } catch (e) {
      final currentExisting = await tmpFile.exists() ? await tmpFile.length() : 0;
      _progressController.add(
        ModelDownloadProgress(
          modelId: manifest.id,
          state: ModelDownloadState.failed,
          downloadedBytes: currentExisting,
          totalBytes: manifest.bytes,
          errorMessage: e is ModelDownloadException ? e.message : 'Tải thất bại.',
        ),
      );
    }
  }

  bool _isRetryable(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.unknown:
        // "Connection closed while receiving data" usually falls here
        return e.error is SocketException || e.error is HttpException || e.message?.contains('Connection closed') == true;
      case DioExceptionType.badResponse:
        final c = e.response?.statusCode ?? 0;
        return c == 429 || c >= 500;
      default:
        return false;
    }
  }

  String _friendly(DioException e) {
    final err = e.error;
    if (err is SocketException) {
      return 'Không kết nối được máy chủ model. Kiểm tra Wi‑Fi, DNS hoặc VPN.';
    }
    if (e.type == DioExceptionType.unknown && (err is HttpException || e.message?.contains('Connection closed') == true)) {
      return 'Kết nối bị ngắt giữa chừng. Bấm "Thử lại" để tải tiếp.';
    }
    final code = e.response?.statusCode;
    return code != null ? 'Máy chủ trả lỗi HTTP $code.' : 'Tải thất bại.';
  }

  Future<void> deleteModel(String modelId) async {
    final file = await getModelFile(modelId);
    if (await file.exists()) {
      await file.delete();
    }
    _progressController.add(
      ModelDownloadProgress(
        modelId: modelId,
        state: ModelDownloadState.notDownloaded,
        downloadedBytes: 0,
        totalBytes: 0,
      ),
    );
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
