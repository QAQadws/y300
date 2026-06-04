class ForumWebViewVisualPolicy {
  const ForumWebViewVisualPolicy({
    required this.earlyHiddenSelectors,
    required this.lateRemovedSelectors,
    required this.extraCss,
    required this.useLoadingMaskUntilStable,
    required this.disableHorizontalOverflow,
  });

  final Set<String> earlyHiddenSelectors;
  final Set<String> lateRemovedSelectors;
  final String extraCss;
  final bool useLoadingMaskUntilStable;
  final bool disableHorizontalOverflow;
}
