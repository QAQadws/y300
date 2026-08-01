import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/forum/presentation/webview/theme/forum_webview_theme_palette.dart';

final class ForumWebViewThemePaletteResolver {
  const ForumWebViewThemePaletteResolver();

  ForumWebViewThemePalette resolve(ThemeData theme) {
    final scheme = theme.colorScheme;
    final y300 = theme.extension<Y300ThemeExtension>();
    final isDark = scheme.brightness == Brightness.dark;

    return ForumWebViewThemePalette(
      brightness: scheme.brightness,
      colorScheme: isDark ? 'dark' : 'light',
      pageBackground: theme.scaffoldBackgroundColor,
      surface: scheme.surfaceContainer,
      surfaceElevated: scheme.surfaceContainerHighest,
      sectionHeaderBackground: isDark
          ? scheme.surfaceContainerHighest
          : scheme.surfaceContainer,
      text: scheme.onSurface,
      mutedText: scheme.onSurfaceVariant,
      subtleText: scheme.onSurfaceVariant.withValues(alpha: 0.72),
      link: scheme.primary,
      border: scheme.outlineVariant,
      inputBackground: scheme.surfaceContainerHighest,
      inputText: scheme.onSurface,
      buttonBackground: scheme.secondaryContainer,
      buttonText: scheme.onSecondaryContainer,
      quoteBackground: scheme.surfaceContainer,
      codeBackground: scheme.surfaceContainerLowest,
      activeBackground: scheme.primary.withValues(alpha: isDark ? 0.14 : 0.10),
      scrim:
          y300?.readerOverlayScrim ??
          Colors.black.withValues(alpha: isDark ? 0.44 : 0.18),
    );
  }
}
