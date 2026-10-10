class CacheInvalidationPolicy {
  const CacheInvalidationPolicy({
    required this.sttModelVersion,
    required this.translationModelVersion,
    required this.targetLanguage,
    required this.pipelineVersion,
  });

  final String sttModelVersion;
  final String translationModelVersion;
  final String targetLanguage;
  final String pipelineVersion;

  bool isCompatible({
    required String cachedSttVersion,
    required String cachedTranslationVersion,
    required String cachedTargetLang,
    required String cachedPipelineVersion,
  }) {
    return cachedSttVersion == sttModelVersion &&
        cachedTranslationVersion == translationModelVersion &&
        cachedTargetLang == targetLanguage &&
        cachedPipelineVersion == pipelineVersion;
  }

  static const currentPolicy = CacheInvalidationPolicy(
    sttModelVersion: '1.0.0',
    translationModelVersion: '1.2.0',
    targetLanguage: 'vi',
    pipelineVersion: '2.0.0',
  );
}
