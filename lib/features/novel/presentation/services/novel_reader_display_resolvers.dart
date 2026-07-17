import 'package:flutter/material.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';

class NovelReaderPalette {
  const NovelReaderPalette({
    required this.brightness,
    required this.background,
    required this.foreground,
    required this.muted,
    required this.accent,
    required this.surface,
    required this.link,
    required this.quoteBackground,
  });

  final Brightness brightness;
  final Color background;
  final Color foreground;
  final Color muted;
  final Color accent;
  final Color surface;
  final Color link;
  final Color quoteBackground;
}

class NovelReaderThemeResolver {
  const NovelReaderThemeResolver();

  NovelReaderPalette resolve({
    required NovelReaderPreferences preferences,
    required ThemeData theme,
    required Brightness platformBrightness,
  }) {
    final preset =
        preferences.themePreset == NovelReaderThemePreset.followSystem
        ? (platformBrightness == Brightness.dark
              ? NovelReaderThemePreset.dark
              : NovelReaderThemePreset.light)
        : preferences.themePreset;
    switch (preset) {
      case NovelReaderThemePreset.dark:
        return NovelReaderPalette(
          brightness: Brightness.dark,
          background: const Color(0xFF141414),
          foreground: const Color(0xFFE9E9E9),
          muted: const Color(0xFFAAA39A),
          accent: theme.colorScheme.primary,
          surface: const Color(0xFF202020),
          link: const Color(0xFF8DB7FF),
          quoteBackground: const Color(0xFF242424),
        );
      case NovelReaderThemePreset.sepia:
        return NovelReaderPalette(
          brightness: Brightness.light,
          background: const Color(0xFFF4EAD7),
          foreground: const Color(0xFF4C3A21),
          muted: const Color(0xFF8B7355),
          accent: const Color(0xFF7A5A28),
          surface: const Color(0xFFEFE0C4),
          link: const Color(0xFF6A55A3),
          quoteBackground: const Color(0xFFE8D8B8),
        );
      case NovelReaderThemePreset.followSystem:
      case NovelReaderThemePreset.light:
        return NovelReaderPalette(
          brightness: Brightness.light,
          background: const Color(0xFFFDFDFD),
          foreground: const Color(0xFF1F1F1F),
          muted: const Color(0xFF737373),
          accent: theme.colorScheme.primary,
          surface: theme.colorScheme.surface,
          link: theme.colorScheme.primary,
          quoteBackground: const Color(0xFFF1F1F1),
        );
    }
  }
}

class NovelReaderTypography {
  const NovelReaderTypography({
    required this.body,
    required this.chapterTitle,
    required this.quote,
    required this.link,
    required this.textAlign,
    required this.firstLineIndent,
    required this.contentMaxWidth,
  });

  final TextStyle body;
  final TextStyle chapterTitle;
  final TextStyle quote;
  final TextStyle link;
  final TextAlign textAlign;
  final double firstLineIndent;
  final double contentMaxWidth;
}

class NovelReaderTypographyResolver {
  const NovelReaderTypographyResolver();

  NovelReaderTypography resolve({
    required NovelReaderPreferences preferences,
    required ThemeData theme,
    required NovelReaderPalette palette,
  }) {
    final fontFamily = preferences.fontFamily == 'system'
        ? null
        : preferences.fontFamily;
    final body = TextStyle(
      color: palette.foreground,
      fontSize: preferences.fontSize,
      height: preferences.lineHeight,
      fontFamily: fontFamily,
      fontWeight: _resolveFontWeight(preferences.fontWeight),
    );
    return NovelReaderTypography(
      body: body,
      chapterTitle:
          theme.textTheme.headlineSmall?.copyWith(
            color: palette.foreground,
            fontFamily: fontFamily,
            fontWeight: FontWeight.w700,
          ) ??
          TextStyle(
            color: palette.foreground,
            fontSize: preferences.fontSize + 4,
            fontWeight: FontWeight.w700,
            fontFamily: fontFamily,
          ),
      quote: body.copyWith(color: palette.muted),
      link: body.copyWith(color: palette.link),
      textAlign: _resolveTextAlign(preferences.textAlign),
      firstLineIndent: preferences.firstLineIndent,
      contentMaxWidth: preferences.contentMaxWidth,
    );
  }

  TextAlign _resolveTextAlign(NovelReaderTextAlignMode mode) {
    switch (mode) {
      case NovelReaderTextAlignMode.justify:
        return TextAlign.justify;
      case NovelReaderTextAlignMode.center:
        return TextAlign.center;
      case NovelReaderTextAlignMode.start:
        return TextAlign.start;
    }
  }

  FontWeight _resolveFontWeight(int value) {
    switch (value) {
      case 500:
        return FontWeight.w500;
      case 700:
        return FontWeight.w700;
      case 400:
      default:
        return FontWeight.w400;
    }
  }
}
