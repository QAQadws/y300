import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_tokens.dart';

class ForumWebViewBootstrapPlaceholder extends StatelessWidget {
  const ForumWebViewBootstrapPlaceholder({super.key});

  static const List<int> _sectionItemCounts = <int>[2, 2, 7];
  static const double _carouselColorLerp = 0.8;
  static const double _sectionHeaderColorLerp = 0.6;
  static const double _sectionBackgroundColorLerp = 0.35;
  static const double _sectionItemBlockColorLerp = 0.8;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final carouselColor =
        Color.lerp(
          AppThemeTokens.appBarBackground,
          backgroundColor,
          _carouselColorLerp,
        ) ??
        AppThemeTokens.appBarBackground;
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
                  color: carouselColor,
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
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final headerColor =
        Color.lerp(
          AppThemeTokens.appBarBackground,
          backgroundColor,
          ForumWebViewBootstrapPlaceholder._sectionHeaderColorLerp,
        ) ??
        AppThemeTokens.appBarBackground;
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: headerColor,
          borderRadius: BorderRadius.circular(3),
        ),
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
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final itemBlockColor =
        Color.lerp(
          AppThemeTokens.appBarBackground,
          backgroundColor,
          ForumWebViewBootstrapPlaceholder._sectionItemBlockColorLerp,
        ) ??
        AppThemeTokens.appBarBackground;
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
            width: 40,
            height: 44,
            color: itemBlockColor,
            borderRadius: BorderRadius.circular(4),
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
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final sectionBackgroundColor =
        Color.lerp(
          AppThemeTokens.forumWebviewSectionBackground,
          backgroundColor,
          ForumWebViewBootstrapPlaceholder._sectionBackgroundColorLerp,
        ) ??
        AppThemeTokens.forumWebviewSectionBackground;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SubformShow(
            key: Key('forum-webview-placeholder-section-$sectionIndex-show'),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: sectionBackgroundColor,
              borderRadius: BorderRadius.circular(6),
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

@Preview(
  name: 'Forum webview section header',
  group: 'Forum/WebView',
  size: Size(393, 120),
  wrapper: forumWebViewBootstrapPlaceholderPreviewShell,
)
Widget forumWebViewSectionHeaderPreview() {
  return const Padding(
    padding: EdgeInsets.symmetric(horizontal: 10),
    child: SubformShow(),
  );
}

@Preview(
  name: 'Forum webview list rows',
  group: 'Forum/WebView',
  size: Size(393, 180),
  wrapper: forumWebViewBootstrapPlaceholderPreviewShell,
)
Widget forumWebViewListRowsPreview() {
  return const Padding(
    padding: EdgeInsets.symmetric(horizontal: 10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SubForm(showDivider: true),
        SubForm(showDivider: false),
      ],
    ),
  );
}

@Preview(
  name: 'Forum webview section',
  group: 'Forum/WebView',
  size: Size(393, 320),
  wrapper: forumWebViewBootstrapPlaceholderPreviewShell,
)
Widget forumWebViewSectionPreview() {
  return const Padding(
    padding: EdgeInsets.symmetric(horizontal: 10),
    child: _ForumPlaceholderSection(
      sectionIndex: 0,
      itemCount: 3,
    ),
  );
}

@Preview(
  name: 'Forum webview placeholder block',
  group: 'Forum/WebView',
  size: Size(220, 120),
  wrapper: forumWebViewBootstrapPlaceholderPreviewShell,
)
Widget forumWebViewPlaceholderBlockPreview() {
  return Builder(
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return Center(
        child: _PlaceholderBlock(
          width: 120,
          height: 16,
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
      );
    },
  );
}
