import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/dio_provider.dart';
import '../../../core/utils/sha256_util.dart';
import '../domain/model_manifest.dart';

// Conditionally import web libraries
import '../../audio/data/vad_engine_web_stub.dart'
    if (dart.library.js_interop) 'package:web/web.dart' as web;
import '../../audio/data/vad_engine_web_stub.dart'
    if (dart.library.js_interop) 'dart:js_interop';

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

class ModelDownloadException implements Exception {
  ModelDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ModelIntegrityException implements Exception {
  ModelIntegrityException(this.message);
  final String message;
  @override
  String toString() => 'ModelIntegrityException: $message';
}

class ModelContractException implements Exception {
  ModelContractException(this.message);
  final String message;
  @override
  String toString() => 'ModelContractException: $message';
}

// Whisper Base (English/Vietnamese optimized) - Pinned commit
const String _whisperBase =
    'https://huggingface.co/Xenova/whisper-base/resolve/d33af214c6ab08c278d722454aaac60f04599f8e';
// Opus-MT (En-Vi) - Pinned commit
const String _opusBase =
    'https://huggingface.co/Xenova/opus-mt-en-vi/resolve/dd3afdf29af23ff9568f755a8b0a9f9b4f6f9437';
// Piper TTS - Pinned v1.0.0 release
const String _piperBase =
    'https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/vi/vi_VN/25hours_single/low';
// Silero VAD v5.1 - Pinned commit
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
    AiModelManifest(
      id: 'stt_whisper_base_en_vi',
      type: AiModelType.stt,
      version: '1.2.1',
      languages: ['en', 'vi', 'ja', 'zh'],
      files: [
        ModelFile(
          name: 'encoder_model_quantized.onnx',
          url: '$_whisperBase/onnx/encoder_model_quantized.onnx',
          bytes: 23196523,
          sha256: null,
        ),
        ModelFile(
          name: 'decoder_model_merged_quantized.onnx',
          url: '$_whisperBase/onnx/decoder_model_merged_quantized.onnx',
          bytes: 53697669,
          sha256: 'a6beb6baabb66f00b6a686d828c95ffca6146d51900cbad0266cad38f64cf861',
        ),
        ModelFile(
          name: 'config.json',
          url: '$_whisperBase/config.json',
          bytes: 2300,
          sha256: null,
        ),
        ModelFile(
          name: 'tokenizer.json',
          url: '$_whisperBase/tokenizer.json',
          bytes: 2480000,
          sha256: null,
        ),
        ModelFile(
          name: 'vocab.json',
          url: '$_whisperBase/vocab.json',
          bytes: 1040000,
          sha256: null,
        ),
        ModelFile(
          name: 'merges.txt',
          url: '$_whisperBase/merges.txt',
          bytes: 494000,
          sha256: null,
        ),
        ModelFile(
          name: 'preprocessor_config.json',
          url: '$_whisperBase/preprocessor_config.json',
          bytes: 340,
          sha256: null,
        ),
      ],
    ),
    AiModelManifest(
      id: 'translate_opus_en_vi',
      type: AiModelType.translation,
      version: '1.3.1',
      languages: ['en', 'vi'],
      files: [
        ModelFile(
          name: 'encoder_model_quantized.onnx',
          url: '$_opusBase/onnx/encoder_model_quantized.onnx',
          bytes: 47105950,
          sha256: null,
        ),
        ModelFile(
          name: 'decoder_model_merged_quantized.onnx',
          url: '$_opusBase/onnx/decoder_model_merged_quantized.onnx',
          bytes: 54373748,
          sha256: '1cfc6a84f9c189e6928c9710b281fae3f1f42d4ffbba109e7b4ec8e31ceb06dd',
        ),
        ModelFile(
          name: 'config.json',
          url: '$_opusBase/config.json',
          bytes: 1389,
          sha256: null,
        ),
        ModelFile(
          name: 'tokenizer.json',
          url: '$_opusBase/tokenizer.json',
          bytes: 5163544,
          sha256: null,
        ),
        ModelFile(
          name: 'vocab.json',
          url: '$_opusBase/vocab.json',
          bytes: 1299764,
          sha256: null,
        ),
      ],
    ),
    AiModelManifest(
      id: 'tts_piper_vi_female',
      type: AiModelType.tts,
      version: '1.0.1',
      languages: ['vi'],
      files: [
        ModelFile(
          name: 'vi_VN-25hours_single-low.onnx',
          url: '$_piperBase/vi_VN-25hours_single-low.onnx',
          bytes: 63104526,
          sha256: '266945c4a80cb3301450c8ba6fcf6ba3542c56cf952a08a8ff3d2d4ff0ab5609',
        ),
        ModelFile(
          name: 'vi_VN-25hours_single-low.onnx.json',
          url: '$_piperBase/vi_VN-25hours_single-low.onnx.json',
          bytes: 4200,
          sha256: null,
        ),
      ],
    ),
    AiModelManifest(
      id: 'vad_silero',
      type: AiModelType.vad,
      version: '5.1.0',
      languages: ['all'],
      files: [
        ModelFile(
          name: 'silero_vad.onnx',
          url: '$_sileroBase/silero_vad.onnx',
          bytes: 2327524,
          sha256: '1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3',
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

  Future<io.Directory> get _modelsDir async {
    if (kIsWeb) throw UnsupportedError('File system not available on Web');
    final docs = await getApplicationDocumentsDirectory();
    final dir = io.Directory('${docs.path}/models');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<io.Directory> getModelDir(String modelId) async {
    if (kIsWeb) throw UnsupportedError('File system not available on Web');
    final root = await _modelsDir;
    final dir = io.Directory('${root.path}/$modelId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Uint8List?> getModelFileBytes(String modelId, String fileName) async {
    if (kIsWeb) {
      final cachedBytes = await _getCachedModelWeb(modelId, fileName);
      if (cachedBytes != null) {
        debugPrint('Using cached model: $modelId/$fileName');
        return cachedBytes;
      }

      final manifest = manifestById(modelId);
      if (manifest == null) return null;
      final fileSpec = manifest.files.firstWhere((f) => f.name == fileName,
          orElse: () => throw Exception('File not in manifest'));

      try {
        debugPrint('Downloading model to browser cache: ${fileSpec.url}');
        final response = await _dio.get<List<int>>(
          fileSpec.url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {
              'Access-Control-Allow-Origin': '*',
            },
          ),
          onReceiveProgress: (received, total) {
            _emit(ModelDownloadProgress(
              modelId: modelId,
              state: ModelDownloadState.downloading,
              downloadedBytes: received,
              totalBytes: total > 0 ? total : fileSpec.bytes,
              currentFile: fileName,
            ));
          },
        );

        final bytes = Uint8List.fromList(response.data!);
        await _cacheModelWeb(modelId, fileName, bytes);
        return bytes;
      } catch (e) {
        debugPrint('Web model fetch failed: $e');
        return null;
      }
    }
    final file = await getModelFile(modelId, fileName);
    if (await file.exists()) {
      return file.readAsBytes();
    }
    return null;
  }

  Future<void> _cacheModelWeb(String modelId, String fileName, Uint8List bytes) async {
    try {
      final cache = await web.window.caches.open('ai-models').toDart;
      final url = 'models/$modelId/$fileName';
      final response = web.Response(bytes.toJS, web.ResponseInit(
        headers: {'Content-Type': 'application/octet-stream'}.jsify() as web.HeadersInit,
      ));
      await cache.put(url.toJS, response).toDart;
    } catch (e) {
      debugPrint('Web model caching failed: $e');
    }
  }

  Future<Uint8List?> _getCachedModelWeb(String modelId, String fileName) async {
    try {
      final cache = await web.window.caches.open('ai-models').toDart;
      final url = 'models/$modelId/$fileName';
      final response = await cache.match(url.toJS).toDart;
      if (response != null) {
        final arrayBuffer = await response.arrayBuffer().toDart;
        return arrayBuffer.toDart.asUint8List();
      }
    } catch (e) {
      debugPrint('Web model cache retrieval failed: $e');
    }
    return null;
  }

  Future<io.File> getModelFile(String modelId, String fileName) async {
    if (kIsWeb) throw UnsupportedError('File system not available on Web');
    final dir = await getModelDir(modelId);
    return io.File('${dir.path}/$fileName');
  }

  Future<bool> isModelDownloaded(String modelId) async {
    final manifest = manifestById(modelId);
    if (manifest == null) return false;

    if (kIsWeb) {
      try {
        final cache = await web.window.caches.open('ai-models').toDart;
        for (final f in manifest.files) {
          final url = 'models/$modelId/${f.name}';
          final match = await cache.match(url.toJS).toDart;
          if (match == null) return false;
        }
        return true;
      } catch (_) {
        return false;
      }
    }

    final dir = await getModelDir(modelId);
    final marker = io.File('${dir.path}/$_readyMarker');
    if (!await marker.exists()) return false;

    try {
      final data = jsonDecode(await marker.readAsString());
      if (data is! Map || data['version'] != manifest.version) return false;
    } catch (_) {
      return false;
    }

    for (final f in manifest.files) {
      final file = io.File('${dir.path}/${f.name}');
      if (!await file.exists()) return false;
      if (await file.length() == 0) return false;
    }
    return true;
  }

  Future<void> downloadModel(AiModelManifest manifest) async {
    if (!_active.add(manifest.id)) return;

    if (kIsWeb) {
      try {
        var completedBytes = 0;
        for (final spec in manifest.files) {
          _emit(ModelDownloadProgress(
            modelId: manifest.id,
            state: ModelDownloadState.downloading,
            downloadedBytes: completedBytes,
            totalBytes: manifest.totalBytes,
            currentFile: spec.name,
          ));

          final bytes = await getModelFileBytes(manifest.id, spec.name);
          if (bytes == null) throw Exception('Download failed for ${spec.name}');
          completedBytes += spec.bytes;
        }

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
          downloadedBytes: 0,
          totalBytes: manifest.totalBytes,
          errorMessage: e.toString(),
        ));
      } finally {
        _active.remove(manifest.id);
      }
      return;
    }

    var completedBytes = 0;
    try {
      final dir = await getModelDir(manifest.id);
      final marker = io.File('${dir.path}/$_readyMarker');
      if (await marker.exists()) await marker.delete();

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
      rethrow;
    } finally {
      _active.remove(manifest.id);
    }
  }

  Future<void> _downloadFile({
    required AiModelManifest manifest,
    required ModelFile spec,
    required dynamic dir,
    required int completedBytes,
  }) async {
    final target = io.File('${dir.path}/${spec.name}');
    final tmp = io.File('${target.path}.tmp');

    if (await target.exists()) {
      try {
        await _verify(target, spec);
        return;
      } on ModelIntegrityException {
        await target.delete();
      }
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      var existing = await tmp.exists() ? await tmp.length() : 0;
      if (spec.sha256 != null && existing > spec.bytes) {
        await tmp.delete();
        existing = 0;
      }

      try {
        if (existing < spec.bytes || spec.bytes == 0) {
          await _dio.download(
            spec.url,
            tmp.path,
            options: Options(
              headers: existing > 0 ? {'Range': 'bytes=$existing-'} : null,
              receiveTimeout: const Duration(minutes: 5),
            ),
            fileAccessMode: existing > 0 ? FileAccessMode.append : FileAccessMode.write,
            deleteOnError: false,
            onReceiveProgress: (received, total) {
              _emit(ModelDownloadProgress(
                modelId: manifest.id,
                state: ModelDownloadState.downloading,
                downloadedBytes: completedBytes + existing + received.toInt(),
                totalBytes: manifest.totalBytes,
                currentFile: spec.name,
              ));
            },
          );
        }

        await _verify(tmp, spec);
        if (await target.exists()) await target.delete();
        await tmp.rename(target.path);
        return;
      } on ModelIntegrityException {
        if (await tmp.exists()) await tmp.delete();
        if (attempt == 1) rethrow;
      } on DioException catch (e) {
        if (e.response?.statusCode == 416 && attempt == 0) {
          if (await tmp.exists()) await tmp.delete();
          continue;
        }
        rethrow;
      }
    }
  }

  Future<void> _verify(io.File file, ModelFile spec) async {
    final length = await file.length();
    if (length == 0) throw ModelIntegrityException('${spec.name}: file rỗng');

    if (spec.sha256 != null) {
      final actual = await Sha256Util.computeFileHash(file);
      if (actual.toLowerCase() != spec.sha256!.toLowerCase()) {
        throw ModelIntegrityException(
          '${spec.name}: sai SHA-256 ($actual != ${spec.sha256})',
        );
      }
    } else if (spec.name.endsWith('.json')) {
      try {
        jsonDecode(await file.readAsString());
      } catch (_) {
        throw ModelIntegrityException('${spec.name}: JSON không hợp lệ');
      }
    }
  }

  void _emit(ModelDownloadProgress p) {
    if (!_progressController.isClosed) _progressController.add(p);
  }

  void dispose() => _progressController.close();

  AiModelManifest? get activeManifest => null;

  Future<void> setEnabledModel(String modelId) async {}

  Future<void> deleteModel(String modelId) async {
    if (kIsWeb) {
      try {
        final cache = await web.window.caches.open('ai-models').toDart;
        final manifest = manifestById(modelId);
        if (manifest != null) {
          for (final f in manifest.files) {
            await cache.delete('models/$modelId/${f.name}'.toJS).toDart;
          }
        }
      } catch (_) {}
      _emit(ModelDownloadProgress(
        modelId: modelId,
        state: ModelDownloadState.notDownloaded,
        downloadedBytes: 0,
        totalBytes: 0,
      ));
      return;
    }

    final dir = await getModelDir(modelId);
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
}

final modelManagerRepositoryProvider = Provider<ModelManagerRepository>((ref) {
  final repo = ModelManagerRepository(ref.watch(dioProvider));
  ref.onDispose(repo.dispose);
  return repo;
});
