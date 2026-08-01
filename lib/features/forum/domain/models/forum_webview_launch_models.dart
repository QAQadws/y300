final class ForumWebViewLaunchConfig {
  const ForumWebViewLaunchConfig({
    required this.initialUri,
    this.popOnRootBack = false,
  });

  final Uri initialUri;
  final bool popOnRootBack;
}
