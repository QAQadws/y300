import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:y300/app/theme/app_theme.dart';

class ForumWebViewBootstrapPlaceholder extends StatelessWidget {
  const ForumWebViewBootstrapPlaceholder({super.key});

  static const List<int> _sectionItemCounts = <int>[2, 2, 7];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    return ColoredBox(
      color: backgroundColor,
      child: ListView(
        key: const Key('forum-webview-bootstrap-placeholder-list'),
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
        children: [
          Container(
            key: const Key('forum-webview-placeholder-carousel'),
            margin: const EdgeInsets.only(top: 10), // 上外边距 10px
            child: AspectRatio(
              aspectRatio: 3 / 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          ...List<Widget>.generate(_sectionItemCounts.length, (sectionIndex) {
            final itemCount = _sectionItemCounts[sectionIndex];
            return _ForumPlaceholderSection(
              key: Key('forum-webview-placeholder-section-$sectionIndex'),
              sectionIndex: sectionIndex,
              itemCount: itemCount,
            );
          }),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class SubformShow extends StatelessWidget {
  const SubformShow({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: Row(
        children: [
          _PlaceholderBlock(
            width: 14,
            height: 14,
            color: colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(width: 12),
          _PlaceholderBlock(
            width: 112,
            height: 16,
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}

class SubForm extends StatelessWidget {
  const SubForm({
    super.key,
    required this.showDivider,
  });

  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PlaceholderBlock(
            width: 28,
            height: 28,
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _PlaceholderBlock(
                        height: 14,
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _PlaceholderBlock(
                      width: 40,
                      height: 12,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: 0.72,
                  alignment: Alignment.centerLeft,
                  child: _PlaceholderBlock(
                    height: 12,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ForumPlaceholderSection extends StatelessWidget {
  const _ForumPlaceholderSection({
    super.key,
    required this.sectionIndex,
    required this.itemCount,
  });

  final int sectionIndex;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SubformShow(
            key: Key('forum-webview-placeholder-section-$sectionIndex-show'),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              children: List<Widget>.generate(itemCount, (rowIndex) {
                return SubForm(
                  key: Key(
                    'forum-webview-placeholder-section-$sectionIndex-row-$rowIndex',
                  ),
                  showDivider: rowIndex != itemCount - 1,
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderBlock extends StatelessWidget {
  const _PlaceholderBlock({
    this.width,
    required this.height,
    required this.color,
    required this.borderRadius,
  });

  final double? width;
  final double height;
  final Color color;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius,
        ),
      ),
    );
  }
}

Widget forumWebViewBootstrapPlaceholderPreviewShell(Widget child) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: SafeArea(child: child),
    ),
  );
}

@Preview(
  name: 'Forum webview home placeholder',
  group: 'Forum/WebView',
  size: Size(500, 852),
  wrapper: forumWebViewBootstrapPlaceholderPreviewShell,
)
Widget forumWebViewBootstrapPlaceholderPreview() {
  return const ForumWebViewBootstrapPlaceholder();
}
