import 'dart:async';

class PerformanceMetrics {
  const PerformanceMetrics({
    required this.playerBufferSeconds,
    required this.aiReadyBufferSeconds,
    required this.droppedFrameCount,
    required this.sttRtf,
    required this.translationThroughputCharsPerSec,
    required this.ttsRtf,
    required this.memoryUsageMb,
    required this.thermalState,
    required this.batteryLevelPercent,
    required this.isCharging,
    required this.pcmQueueSize,
    required this.activeJobCount,
  });

  final double playerBufferSeconds;
  final double aiReadyBufferSeconds;
  final int droppedFrameCount;
  final double sttRtf;
  final double translationThroughputCharsPerSec;
  final double ttsRtf;
  final double memoryUsageMb;
  final String thermalState;
  final int batteryLevelPercent;
  final bool isCharging;
  final int pcmQueueSize;
  final int activeJobCount;
}

class PerformanceMonitor {
  final _controller = StreamController<PerformanceMetrics>.broadcast();

  Stream<PerformanceMetrics> get metricsStream => _controller.stream;

  void reportMetrics(PerformanceMetrics metrics) {
    if (!_controller.isClosed) {
      _controller.add(metrics);
    }
  }

  void dispose() {
    _controller.close();
  }
}
