import 'package:flutter/material.dart';

typedef ForumHtmlNestedRenderer =
    Widget Function(String html, {required String sourceId});

class ForumCollapseBlock extends StatefulWidget {
  const ForumCollapseBlock({
    super.key,
    required this.titleHtml,
    required this.contentHtml,
    required this.initiallyExpanded,
    required this.sourceId,
    required this.nestedRendererBuilder,
  });

  final String titleHtml;
  final String contentHtml;
  final bool initiallyExpanded;
  final String sourceId;
  final ForumHtmlNestedRenderer nestedRendererBuilder;

  @override
  State<ForumCollapseBlock> createState() => _ForumCollapseBlockState();
}

class _ForumCollapseBlockState extends State<ForumCollapseBlock>
    with TickerProviderStateMixin {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(ForumCollapseBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sourceId != oldWidget.sourceId ||
        widget.initiallyExpanded != oldWidget.initiallyExpanded) {
      _expanded = widget.initiallyExpanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      key: Key('forum-html-collapse-${widget.sourceId}'),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: Key('forum-html-collapse-toggle-${widget.sourceId}'),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: const Icon(Icons.chevron_right, size: 20),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: widget.nestedRendererBuilder(
                      widget.titleHtml,
                      sourceId: '${widget.sourceId}-title',
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? DecoratedBox(
                    key: Key('forum-html-collapse-content-${widget.sourceId}'),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: widget.nestedRendererBuilder(
                        widget.contentHtml,
                        sourceId: '${widget.sourceId}-content',
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
