import 'package:flutter/material.dart';

import '../contracts/forum_collapse_header_metrics.dart';

BoxDecoration forumCollapseOutline(Color outline) => BoxDecoration(
  border: Border.all(color: outline),
  borderRadius: BorderRadius.circular(8),
);

class ForumCollapseHeaderControl extends StatelessWidget {
  const ForumCollapseHeaderControl({
    super.key,
    required this.toggleKey,
    required this.expanded,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final Key toggleKey;
  final bool expanded;
  final String? label;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    expanded: expanded,
    label: label,
    onExpand: expanded ? null : onTap,
    onCollapse: expanded ? onTap : null,
    child: InkWell(key: toggleKey, onTap: onTap, child: child),
  );
}

class ForumCollapseChevron extends StatelessWidget {
  const ForumCollapseChevron({super.key, required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: expanded ? 0.25 : 0,
    duration: const Duration(milliseconds: 160),
    child: const Icon(
      Icons.chevron_right,
      size: ForumCollapseHeaderMetrics.iconSize,
    ),
  );
}

/// Shared visual/interaction chrome for Discuz-style collapse blocks.
///
/// Thread HTML and composer previews both supply rendered title/content
/// widgets. Composer editing happens on a separate route; this chrome stays a
/// presentation-only expand/collapse shell.
class ForumCollapseChrome extends StatefulWidget {
  const ForumCollapseChrome({
    super.key,
    required this.initiallyExpanded,
    required this.sourceId,
    required this.title,
    required this.contentBuilder,
    this.expandedSemanticsLabel,
    this.collapsedSemanticsLabel,
    this.keyPrefix = 'forum-html-collapse',
    this.headerTrailing,
    this.expanded,
    this.onExpandedChanged,
  });

  final bool initiallyExpanded;
  final String sourceId;
  final Widget title;
  final WidgetBuilder contentBuilder;
  final String? expandedSemanticsLabel;
  final String? collapsedSemanticsLabel;
  final String keyPrefix;

  /// Optional action outside the arrow/title expansion hit target.
  final Widget? headerTrailing;

  /// When non-null, expansion is controlled by the caller. Existing thread
  /// renderers omit this value and retain the original self-managed behavior.
  final bool? expanded;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<ForumCollapseChrome> createState() => _ForumCollapseChromeState();
}

class _ForumCollapseChromeState extends State<ForumCollapseChrome>
    with TickerProviderStateMixin {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.expanded ?? widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(covariant ForumCollapseChrome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != null) {
      _expanded = widget.expanded!;
    } else if (oldWidget.expanded != null ||
        widget.sourceId != oldWidget.sourceId ||
        widget.initiallyExpanded != oldWidget.initiallyExpanded) {
      _expanded = widget.initiallyExpanded;
    }
  }

  bool get _effectiveExpanded => widget.expanded ?? _expanded;

  void _toggleExpanded() {
    final next = !_effectiveExpanded;
    if (widget.expanded == null) {
      setState(() => _expanded = next);
    }
    widget.onExpandedChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseKey = '${widget.keyPrefix}-${widget.sourceId}';
    final toggleKey = widget.keyPrefix == 'forum-html-collapse'
        ? '${widget.keyPrefix}-toggle-${widget.sourceId}'
        : '$baseKey-toggle';
    final contentKey = widget.keyPrefix == 'forum-html-collapse'
        ? '${widget.keyPrefix}-content-${widget.sourceId}'
        : '$baseKey-content';
    final expanded = _effectiveExpanded;
    final header = Row(
      children: [
        Expanded(
          child: ForumCollapseHeaderControl(
            toggleKey: Key(toggleKey),
            expanded: expanded,
            label: expanded
                ? widget.expandedSemanticsLabel
                : widget.collapsedSemanticsLabel,
            onTap: _toggleExpanded,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                ForumCollapseHeaderMetrics.inset,
                ForumCollapseHeaderMetrics.verticalInset,
                widget.headerTrailing == null
                    ? ForumCollapseHeaderMetrics.inset
                    : ForumCollapseHeaderMetrics.iconGap,
                ForumCollapseHeaderMetrics.verticalInset,
              ),
              child: Row(
                children: [
                  ForumCollapseChevron(expanded: expanded),
                  const SizedBox(width: ForumCollapseHeaderMetrics.iconGap),
                  Expanded(child: widget.title),
                ],
              ),
            ),
          ),
        ),
        if (widget.headerTrailing case final trailing?)
          Padding(padding: const EdgeInsets.only(right: 4), child: trailing),
      ],
    );
    return DecoratedBox(
      key: Key(baseKey),
      decoration: forumCollapseOutline(colorScheme.outlineVariant),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? DecoratedBox(
                    key: Key(contentKey),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(
                        ForumCollapseHeaderMetrics.inset,
                      ),
                      child: widget.contentBuilder(context),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
