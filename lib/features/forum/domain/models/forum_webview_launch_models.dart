enum ForumWebViewHostPurpose { browse, form, postEditFallback, selfProfile }

/// A browser fallback keeps its navigation local to avoid native/browser loops.
enum ForumWebViewNavigationPolicy { preferNative, keepWebView }

bool prefersNativeForumNavigation({
  required ForumWebViewHostPurpose purpose,
  required ForumWebViewNavigationPolicy policy,
}) =>
    purpose == ForumWebViewHostPurpose.browse &&
    policy == ForumWebViewNavigationPolicy.preferNative;

final class ForumWebViewCompletionTarget {
  const ForumWebViewCompletionTarget({required this.tid, required this.pid});

  final String tid;
  final String pid;
}

enum ForumWebViewRouteOutcome { returned, observedTargetRedirect }

final class ForumWebViewRouteResult {
  const ForumWebViewRouteResult({
    required this.outcome,
    this.serverMutationPossible = false,
  });

  final ForumWebViewRouteOutcome outcome;
  final bool serverMutationPossible;
}

final class ForumWebViewLaunchConfig {
  const ForumWebViewLaunchConfig({
    required this.initialUri,
    this.popOnRootBack = false,
    this.purpose = ForumWebViewHostPurpose.browse,
    this.navigationPolicy = ForumWebViewNavigationPolicy.preferNative,
    this.completionTarget,
    this.expectedAccountId,
  });

  final Uri initialUri;
  final bool popOnRootBack;
  final ForumWebViewHostPurpose purpose;
  final ForumWebViewNavigationPolicy navigationPolicy;
  final ForumWebViewCompletionTarget? completionTarget;

  /// Optional actor binding for forms and authenticated browser fallbacks.
  /// Losing this actor disposes the browser; switching back does not revive it.
  final String? expectedAccountId;
}
