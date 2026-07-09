class ForumWebViewVisualPolicy {
  const ForumWebViewVisualPolicy({
    required this.earlyHiddenSelectors,
    required this.lateRemovedSelectors,
    required this.extraCss,
    required this.disableHorizontalOverflow,
  });

  final Set<String> earlyHiddenSelectors;
  final Set<String> lateRemovedSelectors;
  final String extraCss;
  final bool disableHorizontalOverflow;
}
