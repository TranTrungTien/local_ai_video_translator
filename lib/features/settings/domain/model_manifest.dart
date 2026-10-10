enum AiModelType { stt, translation, tts, vad }

class AiModelManifest {
  const AiModelManifest({
    required this.id,
    required this.type,
    required this.version,
    required this.downloadUri,
    required this.sha256,
    required this.bytes,
    required this.languages,
  });
  final String id;
  final AiModelType type;
  final String version;
  final Uri downloadUri;
  final String sha256;
  final int bytes;
  final List<String> languages;
}
