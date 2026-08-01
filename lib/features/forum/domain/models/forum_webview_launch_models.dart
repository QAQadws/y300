enum ForumWebViewHostPurpose { browse, postEditFallback }

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
    this.completionTarget,
  });

  final Uri initialUri;
  final bool popOnRootBack;
  final ForumWebViewHostPurpose purpose;
  final ForumWebViewCompletionTarget? completionTarget;
}
