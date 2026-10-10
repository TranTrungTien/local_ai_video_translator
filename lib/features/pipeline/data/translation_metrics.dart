import 'dart:async';

class TranslationMetricsData {
  const TranslationMetricsData({
    this.translationRtf = 0.15,
    this.charactersPerSecond = 120.0,
    this.batchLatency = Duration.zero,
    this.queueSize = 0,
    this.modelMemoryBytes = 45000000, // ~45 MB for Opus-MT ONNX
  });

  final double translationRtf;
  final double charactersPerSecond;
  final Duration batchLatency;
  final int queueSize;
  final int modelMemoryBytes;

  TranslationMetricsData copyWith({
    double? translationRtf,
    double? charactersPerSecond,
    Duration? batchLatency,
    int? queueSize,
    int? modelMemoryBytes,
  }) {
    return TranslationMetricsData(
      translationRtf: translationRtf ?? this.translationRtf,
      charactersPerSecond: charactersPerSecond ?? this.charactersPerSecond,
      batchLatency: batchLatency ?? this.batchLatency,
      queueSize: queueSize ?? this.queueSize,
      modelMemoryBytes: modelMemoryBytes ?? this.modelMemoryBytes,
    );
  }
}

class TranslationMetrics {
  TranslationMetricsData _data = const TranslationMetricsData();
  final _controller = StreamController<TranslationMetricsData>.broadcast();

  TranslationMetricsData get data => _data;
  Stream<TranslationMetricsData> get stream => _controller.stream;

  void update(TranslationMetricsData newData) {
    _data = newData;
    if (!_controller.isClosed) {
      _controller.add(_data);
    }
  }

  void reset() {
    _data = const TranslationMetricsData();
    if (!_controller.isClosed) {
      _controller.add(_data);
    }
  }

  void dispose() {
    _controller.close();
  }
}
