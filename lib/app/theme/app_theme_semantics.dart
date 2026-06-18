import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_palette.dart';

/// Cross-feature semantic colors that do not map cleanly to Material roles.
@immutable
final class Y300ThemeExtension extends ThemeExtension<Y300ThemeExtension> {
  const Y300ThemeExtension({
    required this.shelfCategoryBarBackground,
    required this.shelfCategorySelectedBackground,
    required this.shelfCategorySelectedForeground,
    required this.shelfCategoryDivider,
    required this.readerChromeBackground,
    required this.readerChromeForeground,
    required this.readerProgressTrackBackground,
    required this.readerOverlayScrim,
    required this.contentHighlightBackground,
    required this.coverPlaceholderBackground,
  });

  factory Y300ThemeExtension.light(AppThemePalette palette) {
    return Y300ThemeExtension(
      shelfCategoryBarBackground: palette.surfaceContainer,
      shelfCategorySelectedBackground: palette.primary,
      shelfCategorySelectedForeground: palette.onPrimary,
      shelfCategoryDivider: palette.outlineVariant,
      readerChromeBackground: palette.surfaceContainer,
      readerChromeForeground: palette.onSurface,
      readerProgressTrackBackground: palette.surfaceContainerHighest,
      readerOverlayScrim: Colors.black.withValues(alpha: 0.18),
      contentHighlightBackground: const Color(0x66FFD54F),
      coverPlaceholderBackground: palette.surfaceContainerHighest,
    );
  }

  factory Y300ThemeExtension.dark(AppThemePalette palette) {
    return Y300ThemeExtension(
      shelfCategoryBarBackground: palette.surfaceContainer,
      shelfCategorySelectedBackground: palette.primary,
      shelfCategorySelectedForeground: palette.onPrimary,
      shelfCategoryDivider: palette.outlineVariant,
      readerChromeBackground: palette.surfaceContainer,
      readerChromeForeground: palette.onSurface,
      readerProgressTrackBackground: palette.surfaceContainerHighest,
      readerOverlayScrim: Colors.black.withValues(alpha: 0.44),
      contentHighlightBackground: const Color(0x668A6500),
      coverPlaceholderBackground: palette.surfaceContainerHighest,
    );
  }

  final Color shelfCategoryBarBackground;
  final Color shelfCategorySelectedBackground;
  final Color shelfCategorySelectedForeground;
  final Color shelfCategoryDivider;
  final Color readerChromeBackground;
  final Color readerChromeForeground;
  final Color readerProgressTrackBackground;
  final Color readerOverlayScrim;
  final Color contentHighlightBackground;
  final Color coverPlaceholderBackground;

  @override
  Y300ThemeExtension copyWith({
    Color? shelfCategoryBarBackground,
    Color? shelfCategorySelectedBackground,
    Color? shelfCategorySelectedForeground,
    Color? shelfCategoryDivider,
    Color? readerChromeBackground,
    Color? readerChromeForeground,
    Color? readerProgressTrackBackground,
    Color? readerOverlayScrim,
    Color? contentHighlightBackground,
    Color? coverPlaceholderBackground,
  }) {
    return Y300ThemeExtension(
      shelfCategoryBarBackground:
          shelfCategoryBarBackground ?? this.shelfCategoryBarBackground,
      shelfCategorySelectedBackground:
          shelfCategorySelectedBackground ??
              this.shelfCategorySelectedBackground,
      shelfCategorySelectedForeground:
          shelfCategorySelectedForeground ??
              this.shelfCategorySelectedForeground,
      shelfCategoryDivider: shelfCategoryDivider ?? this.shelfCategoryDivider,
      readerChromeBackground:
          readerChromeBackground ?? this.readerChromeBackground,
      readerChromeForeground:
          readerChromeForeground ?? this.readerChromeForeground,
      readerProgressTrackBackground:
          readerProgressTrackBackground ?? this.readerProgressTrackBackground,
      readerOverlayScrim: readerOverlayScrim ?? this.readerOverlayScrim,
      contentHighlightBackground:
          contentHighlightBackground ?? this.contentHighlightBackground,
      coverPlaceholderBackground:
          coverPlaceholderBackground ?? this.coverPlaceholderBackground,
    );
  }

  @override
  Y300ThemeExtension lerp(
    ThemeExtension<Y300ThemeExtension>? other,
    double t,
  ) {
    if (other is! Y300ThemeExtension) {
      return this;
    }
    return Y300ThemeExtension(
      shelfCategoryBarBackground: Color.lerp(
        shelfCategoryBarBackground,
        other.shelfCategoryBarBackground,
        t,
      )!,
      shelfCategorySelectedBackground: Color.lerp(
        shelfCategorySelectedBackground,
        other.shelfCategorySelectedBackground,
        t,
      )!,
      shelfCategorySelectedForeground: Color.lerp(
        shelfCategorySelectedForeground,
        other.shelfCategorySelectedForeground,
        t,
      )!,
      shelfCategoryDivider: Color.lerp(
        shelfCategoryDivider,
        other.shelfCategoryDivider,
        t,
      )!,
      readerChromeBackground: Color.lerp(
        readerChromeBackground,
        other.readerChromeBackground,
        t,
      )!,
      readerChromeForeground: Color.lerp(
        readerChromeForeground,
        other.readerChromeForeground,
        t,
      )!,
      readerProgressTrackBackground: Color.lerp(
        readerProgressTrackBackground,
        other.readerProgressTrackBackground,
        t,
      )!,
      readerOverlayScrim: Color.lerp(
        readerOverlayScrim,
        other.readerOverlayScrim,
        t,
      )!,
      contentHighlightBackground: Color.lerp(
        contentHighlightBackground,
        other.contentHighlightBackground,
        t,
      )!,
      coverPlaceholderBackground: Color.lerp(
        coverPlaceholderBackground,
        other.coverPlaceholderBackground,
        t,
      )!,
    );
  }
}

extension Y300ThemeContext on BuildContext {
  Y300ThemeExtension get y300Theme {
    return Theme.of(this).extension<Y300ThemeExtension>()!;
  }
}
