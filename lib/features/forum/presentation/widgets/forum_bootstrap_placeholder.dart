import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_tokens.dart';

/// Neutral forum placeholder shared by shell loading and native/webview first paint.
class ForumBootstrapPlaceholder extends StatelessWidget {
  const ForumBootstrapPlaceholder({
    super.key,
    this.listKey,
    this.keyPrefix = 'forum-bootstrap-placeholder',
  });

  static const List<int> _sectionItemCounts = <int>[2, 2, 7];
  static const double _carouselColorLerp = 0.8;
  static const double _sectionHeaderColorLerp = 0.6;
  static const double _sectionBackgroundColorLerp = 0.35;
  static const double _sectionItemBlockColorLerp = 0.8;

  final Key? listKey;
  final String keyPrefix;

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
        key: listKey,
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
        children: [
          Container(
            key: Key('$keyPrefix-carousel'),
            margin: const EdgeInsets.only(top: 10),
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
              key: Key('$keyPrefix-section-$sectionIndex'),
              keyPrefix: keyPrefix,
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

class _ForumPlaceholderSection extends StatelessWidget {
  const _ForumPlaceholderSection({
    super.key,
    required this.keyPrefix,
    required this.sectionIndex,
    required this.itemCount,
  });

  final String keyPrefix;
  final int sectionIndex;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final sectionBackgroundColor =
        Color.lerp(
          AppThemeTokens.forumWebviewSectionBackground,
          backgroundColor,
          ForumBootstrapPlaceholder._sectionBackgroundColorLerp,
        ) ??
        AppThemeTokens.forumWebviewSectionBackground;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ForumPlaceholderSectionHeader(
            key: Key('$keyPrefix-section-$sectionIndex-show'),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: sectionBackgroundColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              children: List<Widget>.generate(itemCount, (rowIndex) {
                return _ForumPlaceholderRow(
                  key: Key('$keyPrefix-section-$sectionIndex-row-$rowIndex'),
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

class _ForumPlaceholderSectionHeader extends StatelessWidget {
  const _ForumPlaceholderSectionHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final headerColor =
        Color.lerp(
          AppThemeTokens.appBarBackground,
          backgroundColor,
          ForumBootstrapPlaceholder._sectionHeaderColorLerp,
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

class _ForumPlaceholderRow extends StatelessWidget {
  const _ForumPlaceholderRow({super.key, required this.showDivider});

  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final itemBlockColor =
        Color.lerp(
          AppThemeTokens.appBarBackground,
          backgroundColor,
          ForumBootstrapPlaceholder._sectionItemBlockColorLerp,
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
        decoration: BoxDecoration(color: color, borderRadius: borderRadius),
      ),
    );
  }
}
