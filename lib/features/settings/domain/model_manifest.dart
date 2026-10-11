enum AiModelType { stt, translation, tts, vad }

/// Một file thuộc về model (một model có thể gồm nhiều file).
class ModelFile {
  const ModelFile({
    required this.name,
    required this.url,
    required this.bytes,
    this.sha256,
  });

  /// Tên file khi lưu trên máy (nằm trong thư mục models/modelId/).
  final String name;

  /// URL đã ghim theo commit để nội dung không đổi.
  final String url;

  /// Kích thước chính xác (byte) nếu có [sha256]; nếu không thì chỉ là
  /// số xấp xỉ, dùng để hiển thị tiến độ.
  final int bytes;

  /// SHA-256 (64 ký tự hex). Null với file nhỏ chưa tính hash:
  /// khi đó chỉ kiểm tra file không rỗng (và JSON hợp lệ nếu là .json).
  final String? sha256;

  Uri get uri => Uri.parse(url);
}

class AiModelManifest {
  const AiModelManifest({
    required this.id,
    required this.type,
    required this.version,
    required this.files,
    required this.languages,
  });

  final String id;
  final AiModelType type;
  final String version;
  final List<ModelFile> files;
  final List<String> languages;

  int get totalBytes => files.fold<int>(0, (sum, f) => sum + f.bytes);
}