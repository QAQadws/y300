import 'package:flutter/material.dart';
import '../../contracts/forum_html_collapse_labels.dart';
import '../../helpers/forum_collapse_chrome.dart';

typedef ForumHtmlNestedRenderer =
    Widget Function(String html, {required String sourceId});

class ForumCollapseBlock extends StatelessWidget {
  const ForumCollapseBlock({
    super.key,
    required this.titleHtml,
    required this.labels,
    required this.contentHtml,
    required this.initiallyExpanded,
    required this.sourceId,
    required this.nestedRendererBuilder,
    this.onInteraction,
    this.onExpandedChanged,
  });

  final String titleHtml;
  final ForumHtmlCollapseLabels labels;
  final String contentHtml;
  final bool initiallyExpanded;
  final String sourceId;
  final ForumHtmlNestedRenderer nestedRendererBuilder;
  final VoidCallback? onInteraction;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  Widget build(BuildContext context) {
    return ForumCollapseChrome(
      sourceId: sourceId,
      initiallyExpanded: initiallyExpanded,
      title: nestedRendererBuilder(titleHtml, sourceId: '$sourceId-title'),
      contentBuilder: (_) =>
          nestedRendererBuilder(contentHtml, sourceId: '$sourceId-content'),
      expandedSemanticsLabel: labels.expandedSemanticsLabel,
      collapsedSemanticsLabel: labels.collapsedSemanticsLabel,
      onExpandedChanged: (expanded) {
        onExpandedChanged?.call(expanded);
        onInteraction?.call();
      },
    );
  }
}
