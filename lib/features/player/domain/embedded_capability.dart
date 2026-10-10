class EmbeddedCapabilityProbe {
  const EmbeddedCapabilityProbe({
    required this.canPlay,
    required this.canPause,
    required this.canReadPosition,
    required this.canObserveSeek,
    required this.canAccessAudio,
  });

  final bool canPlay;
  final bool canPause;
  final bool canReadPosition;
  final bool canObserveSeek;
  final bool canAccessAudio;

  bool get isEmbeddedAiSupported =>
      canPlay &&
      canPause &&
      canReadPosition &&
      canObserveSeek &&
      canAccessAudio;

  static const unsupported = EmbeddedCapabilityProbe(
    canPlay: false,
    canPause: false,
    canReadPosition: false,
    canObserveSeek: false,
    canAccessAudio: false,
  );

  static const standardWeb = EmbeddedCapabilityProbe(
    canPlay: true,
    canPause: true,
    canReadPosition: true,
    canObserveSeek: true,
    canAccessAudio:
        false, // Requires explicit user audio capture permission consent
  );
}
