import 'package:flutter/material.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_image.dart';
import 'package:y300/shared/widgets/shelf/shelf_theme_palette.dart';

typedef ShelfCoverLayerBuilder = Widget Function(
  BuildContext context,
  ShelfCoverLayerConfig config,
);

class ShelfCoverLayerConfig {
  const ShelfCoverLayerConfig({
    required this.localPath,
    required this.remoteUrl,
    required this.placeholder,
    required this.fit,
    this.imageHeaderBuilder,
  });

  final String? localPath;
  final String? remoteUrl;
  final Widget placeholder;
  final BoxFit fit;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
}

/// 通用书架封面卡片。
///
/// 设计目标：
/// 1. 统一漫画/小说卡片基础结构（封面、兜底底图、底部标题遮罩）。
/// 2. 将“视觉骨架”沉淀到 shared，业务模块只传入数据与行为。
class ShelfCoverCard extends StatelessWidget {
  const ShelfCoverCard({
    super.key,
    this.coverKey,
    required this.title,
    required this.coverImageUrl,
    required this.onTap,
    this.coverLocalPath,
    this.customCoverLocalPath,
    this.onLongPress,
    this.topLeftBadge,
    this.showTwoLineCustomEllipsis = false,
    this.placeholderIcon = Icons.image_not_supported_outlined,
    this.fallbackBackground,
    this.imageHeaderBuilder,
    this.coverLayerBuilder,
    this.selected = false,
  });

  final String? coverKey;
  final String title;
  final String? coverImageUrl;
  final String? coverLocalPath;
  final String? customCoverLocalPath;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? topLeftBadge;
  final bool showTwoLineCustomEllipsis;
  final IconData placeholderIcon;
  final Decoration? fallbackBackground;
  final ImageRequestHeaderBuilder? imageHeaderBuilder;
  final ShelfCoverLayerBuilder? coverLayerBuilder;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette =
        const ShelfThemePaletteResolver().resolve(Theme.of(context));
    final borderColor = selected
        ? palette.selectedBorder
        : Colors.transparent;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
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
      ),
    );
  }

  Widget _buildCoverLayer(BuildContext context) {
    final placeholder = _buildFallback(context);
    final builder = coverLayerBuilder;
    if (builder != null) {
      return builder(
        context,
        ShelfCoverLayerConfig(
          localPath: _preferredLocalPath,
          remoteUrl: coverImageUrl,
          fit: BoxFit.cover,
          placeholder: placeholder,
          imageHeaderBuilder: imageHeaderBuilder,
        ),
      );
    }
    return ShelfCoverImage(
      coverKey: coverKey ?? title,
      localPath: _preferredLocalPath,
      remoteUrl: coverImageUrl,
      imageHeaderBuilder: imageHeaderBuilder,
      fit: BoxFit.cover,
      placeholder: placeholder,
    );
  }

  String? get _preferredLocalPath {
    final custom = customCoverLocalPath?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    final cover = coverLocalPath?.trim();
    return cover == null || cover.isEmpty ? null : cover;
  }

  Widget _buildFallback(BuildContext context) {
    final palette =
        const ShelfThemePaletteResolver().resolve(Theme.of(context));
    return Container(
      decoration: fallbackBackground,
      color: fallbackBackground == null
          ? palette.coverPlaceholderBackground
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

