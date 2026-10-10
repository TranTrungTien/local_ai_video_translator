class AudioStreamInfo {
  const AudioStreamInfo({
    required this.sampleRate,
    required this.channels,
    required this.codec,
    required this.duration,
  });

  final int sampleRate;
  final int channels;
  final String codec;
  final Duration duration;
}
