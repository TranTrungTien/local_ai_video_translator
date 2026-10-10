class SttBenchmarkResult {
  const SttBenchmarkResult({
    required this.modelLoadDuration,
    required this.peakMemoryBytes,
    required this.audioDuration,
    required this.inferenceDuration,
    required this.realtimeFactor,
    required this.language,
    required this.segmentCount,
  });

  final Duration modelLoadDuration;
  final int peakMemoryBytes;
  final Duration audioDuration;
  final Duration inferenceDuration;
  final double realtimeFactor; // processingWallTime / audioDuration
  final String language;
  final int segmentCount;

  static SttBenchmarkResult measure({
    required Duration modelLoadDuration,
    required int peakMemoryBytes,
    required Duration audioDuration,
    required Duration inferenceDuration,
    required String language,
    required int segmentCount,
  }) {
    final audioMs = audioDuration.inMilliseconds;
    final inferMs = inferenceDuration.inMilliseconds;
    final rtf = audioMs > 0 ? inferMs / audioMs : 1.0;

    return SttBenchmarkResult(
      modelLoadDuration: modelLoadDuration,
      peakMemoryBytes: peakMemoryBytes,
      audioDuration: audioDuration,
      inferenceDuration: inferenceDuration,
      realtimeFactor: rtf,
      language: language,
      segmentCount: segmentCount,
    );
  }
}
