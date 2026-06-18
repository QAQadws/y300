import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';

/// Theme-derived color contract for the shared comic/novel detail page.
///
/// The page background is the single source of truth for header gradient
/// endings, so custom light/dark backgrounds do not leave a fixed white edge.
@immutable
class UnifiedDetailPalette {
  const UnifiedDetailPalette({
    required this.pageBackground,
    required this.headerGradientStart,
    required this.headerGradientMiddle,
    required this.headerGradientEnd,
    required this.headerFallbackBackground,
    required this.headerPlaceholderBackground,
    required this.onHeader,
    required this.collapsedAppBarBackground,
    required this.collapsedAppBarForeground,
  });

  final Color pageBackground;
  final Color headerGradientStart;
  final Color headerGradientMiddle;
  final Color headerGradientEnd;
  final Color headerFallbackBackground;
  final Color headerPlaceholderBackground;
  final Color onHeader;
  final Color collapsedAppBarBackground;
  final Color collapsedAppBarForeground;
}

class UnifiedDetailPaletteResolver {
  const UnifiedDetailPaletteResolver();

  UnifiedDetailPalette resolve(ThemeData theme) {
    final scheme = theme.colorScheme;
    final y300Theme = theme.extension<Y300ThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;
    final pageBackground = theme.scaffoldBackgroundColor;
    final detailSurface =
        y300Theme?.coverPlaceholderBackground ?? scheme.surfaceContainer;
    final fallbackBackground = Color.alphaBlend(
      scheme.primary.withAlpha(isDark ? 34 : 18),
      detailSurface,
    );

    return UnifiedDetailPalette(
      pageBackground: pageBackground,
      headerGradientStart: Colors.black.withAlpha(isDark ? 118 : 64),
      headerGradientMiddle: pageBackground.withAlpha(isDark ? 198 : 158),
      headerGradientEnd: pageBackground,
      headerFallbackBackground: fallbackBackground,
      headerPlaceholderBackground: Color.alphaBlend(
        Colors.black.withAlpha(isDark ? 20 : 8),
        fallbackBackground,
      ),
      onHeader: Colors.white,
      collapsedAppBarBackground: pageBackground,
      collapsedAppBarForeground: _readableOn(pageBackground),
    );
  }

  Color _readableOn(Color background) {
    return background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }
}
