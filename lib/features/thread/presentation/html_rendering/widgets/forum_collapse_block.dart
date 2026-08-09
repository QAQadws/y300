import 'package:flutter/material.dart';
import 'package:y300/l10n/app_localizations.dart';
import 'package:y300/shared/widgets/forum_collapse_chrome.dart';

typedef ForumHtmlNestedRenderer =
    Widget Function(String html, {required String sourceId});

class ForumCollapseBlock extends StatelessWidget {
  const ForumCollapseBlock({
    super.key,
    required this.titleHtml,
    required this.contentHtml,
    required this.initiallyExpanded,
    required this.sourceId,
    required this.nestedRendererBuilder,
    this.onInteraction,
  });

  final String titleHtml;
  final String contentHtml;
  final bool initiallyExpanded;
  final String sourceId;
  final ForumHtmlNestedRenderer nestedRendererBuilder;
  final VoidCallback? onInteraction;

  @override
  Widget build(BuildContext context) {
    return ForumCollapseChrome(
      sourceId: sourceId,
      initiallyExpanded: initiallyExpanded,
      title: nestedRendererBuilder(titleHtml, sourceId: '$sourceId-title'),
      contentBuilder: (_) =>
          nestedRendererBuilder(contentHtml, sourceId: '$sourceId-content'),
      expandedSemanticsLabel: AppLocalizations.of(
        context,
      ).threadHtmlCollapseExpanded,
      collapsedSemanticsLabel: AppLocalizations.of(
        context,
      ).threadHtmlCollapseCollapsed,
      onExpandedChanged: (_) => onInteraction?.call(),
    );
  }
}
