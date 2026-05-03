import 'package:flutter/material.dart';

/// 通用书架封面卡片。
///
/// 设计目标：
/// 1. 统一漫画/小说卡片基础结构（封面、兜底底图、底部标题遮罩）。
/// 2. 将“视觉骨架”沉淀到 shared，业务模块只传入数据与行为。
class ShelfCoverCard extends StatelessWidget {
  const ShelfCoverCard({
    super.key,
    required this.title,
    required this.coverImageUrl,
    required this.onTap,
    this.onLongPress,
    this.topLeftBadge,
    this.showTwoLineCustomEllipsis = false,
    this.placeholderIcon = Icons.image_not_supported_outlined,
    this.fallbackBackground,
  });

  final String title;
  final String? coverImageUrl;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? topLeftBadge;
  final bool showTwoLineCustomEllipsis;
  final IconData placeholderIcon;
  final Decoration? fallbackBackground;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildCoverLayer(context),
            if (topLeftBadge != null)
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: topLeftBadge,
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildTitleOverlay(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverLayer(BuildContext context) {
    if (coverImageUrl != null && coverImageUrl!.trim().isNotEmpty) {
      return Image.network(
        coverImageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildFallback(context);
        },
      );
    }
    return _buildFallback(context);
  }

  Widget _buildFallback(BuildContext context) {
    return Container(
      decoration: fallbackBackground,
      color: fallbackBackground == null
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : null,
      child: Icon(placeholderIcon),
    );
  }

  Widget _buildTitleOverlay(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00000000),
            Color(0xA6000000),
            Color(0xCC000000),
          ],
        ),
      ),
      child: showTwoLineCustomEllipsis
          ? _TwoLineEllipsisText(title, style: style)
          : Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
    );
  }
}

class _TwoLineEllipsisText extends StatelessWidget {
  const _TwoLineEllipsisText(
    this.text, {
    this.style,
  });

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final defaultStyle = DefaultTextStyle.of(context).style;
        final effectiveStyle = style ?? defaultStyle;

        final painter = TextPainter(
          text: TextSpan(text: text, style: effectiveStyle),
          textDirection: Directionality.of(context),
          maxLines: 2,
          ellipsis: '···',
        )..layout(maxWidth: constraints.maxWidth);

        final displayText = painter.didExceedMaxLines
            ? _truncateToTwoLines(
                source: text,
                maxWidth: constraints.maxWidth,
                style: effectiveStyle,
                textDirection: Directionality.of(context),
              )
            : text;

        return Text(
          displayText,
          maxLines: 2,
          overflow: TextOverflow.clip,
          style: effectiveStyle,
        );
      },
    );
  }

  String _truncateToTwoLines({
    required String source,
    required double maxWidth,
    required TextStyle style,
    required TextDirection textDirection,
  }) {
    if (source.isEmpty) {
      return source;
    }

    var low = 0;
    var high = source.length;
    var best = '';

    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final candidate = '${source.substring(0, mid)}···';
      final painter = TextPainter(
        text: TextSpan(text: candidate, style: style),
        textDirection: textDirection,
        maxLines: 2,
      )..layout(maxWidth: maxWidth);

      if (painter.didExceedMaxLines) {
        high = mid - 1;
      } else {
        best = candidate;
        low = mid + 1;
      }
    }

    return best.isEmpty ? '···' : best;
  }
}
