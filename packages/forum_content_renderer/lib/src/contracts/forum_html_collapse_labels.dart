/// Host-localized labels used by HTML collapse controls.
final class ForumHtmlCollapseLabels {
  const ForumHtmlCollapseLabels({
    required this.fallbackTitle,
    required this.expandedSemanticsLabel,
    required this.collapsedSemanticsLabel,
  });

  final String fallbackTitle;
  final String expandedSemanticsLabel;
  final String collapsedSemanticsLabel;

  @override
  bool operator ==(Object other) {
    return other is ForumHtmlCollapseLabels &&
        fallbackTitle == other.fallbackTitle &&
        expandedSemanticsLabel == other.expandedSemanticsLabel &&
        collapsedSemanticsLabel == other.collapsedSemanticsLabel;
  }

  @override
  int get hashCode => Object.hash(
    fallbackTitle,
    expandedSemanticsLabel,
    collapsedSemanticsLabel,
  );
}
