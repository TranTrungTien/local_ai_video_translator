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
  PerformanceMonitor._();
  static final PerformanceMonitor instance = PerformanceMonitor._();

  final _controller = StreamController<PerformanceMetrics>.broadcast();
  PerformanceMetrics _current = const PerformanceMetrics(
    playerBufferSeconds: 0,
    aiReadyBufferSeconds: 0,
    droppedFrameCount: 0,
    sttRtf: 0,
    translationThroughputCharsPerSec: 0,
    ttsRtf: 0,
    memoryUsageMb: 0,
    thermalState: 'unknown',
    batteryLevelPercent: 0,
    isCharging: false,
    pcmQueueSize: 0,
    activeJobCount: 0,
  );

  Stream<PerformanceMetrics> get metricsStream => _controller.stream;
  PerformanceMetrics get current => _current;

  void reportMetrics(PerformanceMetrics metrics) {
    _current = metrics;
    if (!_controller.isClosed) {
      _controller.add(metrics);
    }
  }

  void updateSttRtf(double rtf) {
    reportMetrics(_current.copyWith(sttRtf: rtf));
  }

  void updateTranslationThroughput(double charsPerSec) {
    reportMetrics(_current.copyWith(translationThroughputCharsPerSec: charsPerSec));
  }

  void updateTtsRtf(double rtf) {
    reportMetrics(_current.copyWith(ttsRtf: rtf));
  }

  void updateAiBuffer(double seconds) {
    reportMetrics(_current.copyWith(aiReadyBufferSeconds: seconds));
  }

  void dispose() {
    _controller.close();
  }
}

extension on PerformanceMetrics {
  PerformanceMetrics copyWith({
    double? playerBufferSeconds,
    double? aiReadyBufferSeconds,
    int? droppedFrameCount,
    double? sttRtf,
    double? translationThroughputCharsPerSec,
    double? ttsRtf,
    double? memoryUsageMb,
    String? thermalState,
    int? batteryLevelPercent,
    bool? isCharging,
    int? pcmQueueSize,
    int? activeJobCount,
  }) {
    return PerformanceMetrics(
      playerBufferSeconds: playerBufferSeconds ?? this.playerBufferSeconds,
      aiReadyBufferSeconds: aiReadyBufferSeconds ?? this.aiReadyBufferSeconds,
      droppedFrameCount: droppedFrameCount ?? this.droppedFrameCount,
      sttRtf: sttRtf ?? this.sttRtf,
      translationThroughputCharsPerSec: translationThroughputCharsPerSec ?? this.translationThroughputCharsPerSec,
      ttsRtf: ttsRtf ?? this.ttsRtf,
      memoryUsageMb: memoryUsageMb ?? this.memoryUsageMb,
      thermalState: thermalState ?? this.thermalState,
      batteryLevelPercent: batteryLevelPercent ?? this.batteryLevelPercent,
      isCharging: isCharging ?? this.isCharging,
      pcmQueueSize: pcmQueueSize ?? this.pcmQueueSize,
      activeJobCount: activeJobCount ?? this.activeJobCount,
    );
  }
}
