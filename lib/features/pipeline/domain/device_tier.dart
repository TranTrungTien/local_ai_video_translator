enum DeviceTier { lite, balanced, performance }

class DeviceTierClassifier {
  const DeviceTierClassifier();

  DeviceTier classify({
    required int memoryClassMb,
    required int cpuCores,
    required double recentSttRtf,
  }) {
    if (memoryClassMb < 2048 || cpuCores <= 4 || recentSttRtf > 1.2) {
      return DeviceTier.lite;
    }
    if (memoryClassMb >= 4096 && cpuCores >= 8 && recentSttRtf < 0.6) {
      return DeviceTier.performance;
    }
    return DeviceTier.balanced;
  }
}
