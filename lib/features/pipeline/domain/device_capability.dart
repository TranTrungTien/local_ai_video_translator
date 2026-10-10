enum ThermalStatus { nominal, fair, serious, critical }

enum AccelerationHardware { cpu, gpu, nnapi }

class DeviceCapabilityProfile {
  const DeviceCapabilityProfile({
    required this.memoryClassMb,
    required this.cpuCores,
    required this.acceleration,
    required this.thermalStatus,
    required this.recentSttRtf,
  });

  final int memoryClassMb;
  final int cpuCores;
  final AccelerationHardware acceleration;
  final ThermalStatus thermalStatus;
  final double recentSttRtf;

  bool get isCapableOfTurboStt =>
      memoryClassMb >= 2048 &&
      recentSttRtf < 1.0 &&
      thermalStatus != ThermalStatus.critical;
  bool get isLowMemoryDevice => memoryClassMb < 1536;

  DeviceCapabilityProfile copyWith({
    int? memoryClassMb,
    int? cpuCores,
    AccelerationHardware? acceleration,
    ThermalStatus? thermalStatus,
    double? recentSttRtf,
  }) {
    return DeviceCapabilityProfile(
      memoryClassMb: memoryClassMb ?? this.memoryClassMb,
      cpuCores: cpuCores ?? this.cpuCores,
      acceleration: acceleration ?? this.acceleration,
      thermalStatus: thermalStatus ?? this.thermalStatus,
      recentSttRtf: recentSttRtf ?? this.recentSttRtf,
    );
  }

  static const defaultProfile = DeviceCapabilityProfile(
    memoryClassMb: 4096,
    cpuCores: 8,
    acceleration: AccelerationHardware.nnapi,
    thermalStatus: ThermalStatus.nominal,
    recentSttRtf: 0.45,
  );
}
