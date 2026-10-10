import 'dart:async';

class PlayerDiagnosticsMetrics {
  const PlayerDiagnosticsMetrics({
    this.prepareDuration = Duration.zero,
    this.bufferEventCount = 0,
    this.droppedFrameCount = 0,
    this.decoderInfo = 'Software/Hardware Default',
    this.bandwidthEstimate = 0,
    this.lastError,
  });

  final Duration prepareDuration;
  final int bufferEventCount;
  final int droppedFrameCount;
  final String decoderInfo;
  final int bandwidthEstimate; // bits per second
  final String? lastError;

  PlayerDiagnosticsMetrics copyWith({
    Duration? prepareDuration,
    int? bufferEventCount,
    int? droppedFrameCount,
    String? decoderInfo,
    int? bandwidthEstimate,
    String? lastError,
  }) {
    return PlayerDiagnosticsMetrics(
      prepareDuration: prepareDuration ?? this.prepareDuration,
      bufferEventCount: bufferEventCount ?? this.bufferEventCount,
      droppedFrameCount: droppedFrameCount ?? this.droppedFrameCount,
      decoderInfo: decoderInfo ?? this.decoderInfo,
      bandwidthEstimate: bandwidthEstimate ?? this.bandwidthEstimate,
      lastError: lastError ?? this.lastError,
    );
  }
}

class PlayerDiagnostics {
  PlayerDiagnosticsMetrics _metrics = const PlayerDiagnosticsMetrics();
  final _controller = StreamController<PlayerDiagnosticsMetrics>.broadcast();

  PlayerDiagnosticsMetrics get metrics => _metrics;
  Stream<PlayerDiagnosticsMetrics> get stream => _controller.stream;

  void recordPrepareDuration(Duration duration) {
    _metrics = _metrics.copyWith(prepareDuration: duration);
    _controller.add(_metrics);
  }

  void incrementBufferEvents() {
    _metrics = _metrics.copyWith(
      bufferEventCount: _metrics.bufferEventCount + 1,
    );
    _controller.add(_metrics);
  }

  void updateDroppedFrames(int count) {
    _metrics = _metrics.copyWith(droppedFrameCount: count);
    _controller.add(_metrics);
  }

  void updateDecoderInfo(String info) {
    _metrics = _metrics.copyWith(decoderInfo: info);
    _controller.add(_metrics);
  }

  void updateBandwidthEstimate(int bps) {
    _metrics = _metrics.copyWith(bandwidthEstimate: bps);
    _controller.add(_metrics);
  }

  void recordError(String error) {
    _metrics = _metrics.copyWith(lastError: error);
    _controller.add(_metrics);
  }

  void reset() {
    _metrics = const PlayerDiagnosticsMetrics();
    _controller.add(_metrics);
  }

  void dispose() {
    _controller.close();
  }
}
