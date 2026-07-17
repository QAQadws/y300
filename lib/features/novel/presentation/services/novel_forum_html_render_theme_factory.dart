import 'package:flutter/material.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

final class NovelForumHtmlRenderThemeFactory {
  const NovelForumHtmlRenderThemeFactory();

  ForumHtmlThemeContext fromPalette(NovelReaderPalette palette) {
    return ForumHtmlThemeContext(
      brightness: palette.brightness == Brightness.dark
          ? ForumHtmlBrightness.dark
          : ForumHtmlBrightness.light,
      surface: palette.background,
      foreground: palette.foreground,
      link: palette.link,
      quoteSurface: palette.quoteBackground,
      quoteForeground: palette.muted,
      codeSurface: palette.surface,
      codeForeground: palette.foreground,
    );
  }
}
