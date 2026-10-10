enum EntitlementTier { free, premiumSubscriber, developerUnlocked }

class FeatureEntitlement {
  const FeatureEntitlement({
    required this.tier,
    required this.canUseVoiceOver,
    required this.maxVoicesAvailable,
  });

  final EntitlementTier tier;
  final bool canUseVoiceOver;
  final int maxVoicesAvailable;

  static const defaultFree = FeatureEntitlement(
    tier: EntitlementTier.free,
    canUseVoiceOver: false,
    maxVoicesAvailable: 1,
  );

  static const defaultDeveloperUnlocked = FeatureEntitlement(
    tier: EntitlementTier.developerUnlocked,
    canUseVoiceOver: true,
    maxVoicesAvailable: 5,
  );
}
