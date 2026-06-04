enum ForumWebViewEngine {
  legacy,
  advanced,
}

enum ForumWebViewDocumentStartMode {
  reliable,
  bestEffort,
  unavailable,
}

class ForumWebViewCapabilityProfile {
  const ForumWebViewCapabilityProfile({
    required this.engine,
    required this.documentStartMode,
    required this.supportsContentBlockers,
    required this.supportsTransparentBackground,
    required this.supportsPlatformScrollTuning,
    required this.supportsCookieHooks,
  });

  final ForumWebViewEngine engine;
  final ForumWebViewDocumentStartMode documentStartMode;
  final bool supportsContentBlockers;
  final bool supportsTransparentBackground;
  final bool supportsPlatformScrollTuning;
  final bool supportsCookieHooks;
}

class ForumWebViewBootstrapConfig {
  const ForumWebViewBootstrapConfig({
    required this.initialUri,
    required this.capabilityProfile,
  });

  final Uri initialUri;
  final ForumWebViewCapabilityProfile capabilityProfile;
}
