import 'package:y300/features/forum/domain/models/forum_webview_network_policy_models.dart';
import 'package:y300/features/forum/domain/models/forum_webview_visual_policy_models.dart';

enum ForumWebViewEngine { legacy, advanced }

enum ForumWebViewDocumentStartMode { reliable, bestEffort, unavailable }

class ForumWebViewCapabilityProfile {
  const ForumWebViewCapabilityProfile({
    required this.engine,
    required this.documentStartMode,
    required this.supportsContentBlockers,
    required this.supportsTransparentBackground,
    required this.supportsPlatformScrollTuning,
    required this.supportsCookieHooks,
    this.supportsPageCommitVisible = false,
  });

  final ForumWebViewEngine engine;
  final ForumWebViewDocumentStartMode documentStartMode;
  final bool supportsContentBlockers;
  final bool supportsTransparentBackground;
  final bool supportsPlatformScrollTuning;
  final bool supportsCookieHooks;
  final bool supportsPageCommitVisible;
}

enum ForumWebViewInitialUserScriptInjectionTime { documentStart, documentEnd }

class ForumWebViewInitialUserScript {
  const ForumWebViewInitialUserScript({
    required this.source,
    required this.injectionTime,
    this.forMainFrameOnly = true,
  });

  final String source;
  final ForumWebViewInitialUserScriptInjectionTime injectionTime;
  final bool forMainFrameOnly;
}

class ForumWebViewBootstrapConfig {
  const ForumWebViewBootstrapConfig({
    required this.initialUri,
    required this.capabilityProfile,
    required this.visualPolicy,
    required this.initialUserScripts,
    required this.networkPolicy,
  });

  final Uri initialUri;
  final ForumWebViewCapabilityProfile capabilityProfile;
  final ForumWebViewVisualPolicy visualPolicy;
  final List<ForumWebViewInitialUserScript> initialUserScripts;
  final ForumWebViewNetworkPolicy networkPolicy;
}
