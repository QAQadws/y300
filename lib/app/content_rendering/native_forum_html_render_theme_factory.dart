import 'package:flutter/material.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';

/// Host mapping keeps the thread card palette as the single native color source.
extension ForumHtmlNativeThemeHostAdapter on ForumHtmlRenderThemeFactory {
  ForumHtmlThemeContext fromNativeTheme({required ThemeData theme}) {
    return fromThreadPalette(
      palette: ThreadDetailNativePalette.resolve(theme),
      brightness: theme.brightness,
    );
  }

  ForumHtmlThemeContext fromThreadPalette({
    required ThreadDetailNativePalette palette,
    required Brightness brightness,
  }) {
    return fromPalette(
      palette: ForumHtmlRenderPalette(
        background: palette.background,
        card: palette.card,
        cardElevated: palette.cardElevated,
        panelBackground: palette.panelBackground,
        accent: palette.accent,
        bodyText: palette.bodyText,
      ),
      brightness: brightness,
    );
  }
}
