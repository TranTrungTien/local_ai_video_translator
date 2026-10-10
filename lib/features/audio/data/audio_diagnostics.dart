import 'dart:async';

class AudioMetrics {
  const AudioMetrics({
    this.queueSize = 0,
    this.queuedAudioSeconds = 0.0,
    this.vadRealtimeFactor = 1.0,
    this.speechPercentage = 0.0,
    this.memoryConsumptionBytes = 0,
  });

  final int queueSize;
  final double queuedAudioSeconds;
  final double vadRealtimeFactor;
  final double speechPercentage;
  final int memoryConsumptionBytes;

  AudioMetrics copyWith({
    int? queueSize,
    double? queuedAudioSeconds,
    double? vadRealtimeFactor,
    double? speechPercentage,
    int? memoryConsumptionBytes,
  }) {
    return AudioMetrics(
      queueSize: queueSize ?? this.queueSize,
      queuedAudioSeconds: queuedAudioSeconds ?? this.queuedAudioSeconds,
      vadRealtimeFactor: vadRealtimeFactor ?? this.vadRealtimeFactor,
      speechPercentage: speechPercentage ?? this.speechPercentage,
      memoryConsumptionBytes:
          memoryConsumptionBytes ?? this.memoryConsumptionBytes,
    );
  }
}

class AudioDiagnostics {
  AudioMetrics _metrics = const AudioMetrics();
  final _controller = StreamController<AudioMetrics>.broadcast();

  AudioMetrics get metrics => _metrics;
  Stream<AudioMetrics> get stream => _controller.stream;

  void updateMetrics(AudioMetrics newMetrics) {
    _metrics = newMetrics;
    if (!_controller.isClosed) {
      _controller.add(_metrics);
    }
  }

  void reset() {
    _metrics = const AudioMetrics();
    if (!_controller.isClosed) {
      _controller.add(_metrics);
    }
  }

  void dispose() {
    _controller.close();
  }
}
