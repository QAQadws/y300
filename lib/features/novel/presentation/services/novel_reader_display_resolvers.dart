import 'package:flutter/material.dart';
import 'package:y300/features/fonts/fonts.dart' show ResolvedFont;
import 'package:y300/features/novel/data/models/novel_models.dart';

import 'novel_reader_color_contrast.dart';

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
    Color? codeForeground,
  }) : _codeForeground = codeForeground;

  final Brightness brightness;
  final Color background;
  final Color foreground;
  final Color muted;
  final Color accent;
  final Color surface;
  final Color link;
  final Color quoteBackground;
  final Color? _codeForeground;
  Color get codeForeground => _codeForeground ?? foreground;
}

class NovelReaderThemeResolver {
  const NovelReaderThemeResolver();

  NovelReaderPalette resolve({
    required NovelReaderPreferences preferences,
    required ThemeData theme,
  }) {
    final base = _preset(preferences: preferences, theme: theme);
    final colors = preferences.colors;
    // Stored native requests survive a visit to the legacy scrolling reader.
    if (colors.isEmpty ||
        preferences.flowMode == NovelReaderFlowMode.vertical) {
      return base;
    }
    if (!colors.isValid) throw ArgumentError('Invalid reader colors');
    final background = colors.background == null
        ? base.background
        : Color(0xff000000 | colors.background!);
    final foreground = colors.foreground == null
        ? readableNovelReaderRole(base.foreground, [background])
        : Color(0xff000000 | colors.foreground!);
    final brightness = ThemeData.estimateBrightnessForColor(background);
    // Keep generated surfaces on the same contrast side as the canvas. Around
    // middle gray, shading across that boundary can leave no shared legible ink.
    final ink = background.computeLuminance() >= .179
        ? const Color(0xffffffff)
        : const Color(0xff000000);
    final surface = Color.alphaBlend(ink.withValues(alpha: .05), background);
    final quote = Color.alphaBlend(ink.withValues(alpha: .08), background);
    final roleBackgrounds = [background, surface, quote];
    return NovelReaderPalette(
      brightness: brightness,
      background: background,
      foreground: foreground,
      muted: readableNovelReaderRole(
        Color.lerp(foreground, background, .26)!,
        roleBackgrounds,
      ),
      accent: readableNovelReaderRole(base.accent, roleBackgrounds),
      surface: surface,
      link: readableNovelReaderRole(base.link, roleBackgrounds),
      quoteBackground: quote,
      codeForeground: readableNovelReaderRole(foreground, [surface]),
    );
  }

  NovelReaderPalette _preset({
    required NovelReaderPreferences preferences,
    required ThemeData theme,
  }) {
    switch (preferences.themePreset) {
      case NovelReaderThemePreset.followApp:
        final scheme = theme.colorScheme;
        return NovelReaderPalette(
          brightness: theme.brightness,
          background: theme.scaffoldBackgroundColor,
          foreground: scheme.onSurface,
          muted: scheme.onSurfaceVariant,
          accent: scheme.primary,
          surface: scheme.surfaceContainer,
          link: scheme.primary,
          quoteBackground: scheme.surfaceContainerHighest,
        );
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
        return const NovelReaderPalette(
          brightness: Brightness.light,
          background: Color(0xFFF4EAD7),
          foreground: Color(0xFF4C3A21),
          muted: Color(0xFF8B7355),
          accent: Color(0xFF7A5A28),
          surface: Color(0xFFEFE0C4),
          link: Color(0xFF6A55A3),
          quoteBackground: Color(0xFFE8D8B8),
        );
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
    ResolvedFont? resolvedFont,
  }) {
    // Preferences store content identity. Only a completed runtime resolution
    // may provide a family name to the renderer or its measurement paths.
    final fontFamily = (resolvedFont ?? ResolvedFont.system).fontFamily;
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
      case NovelReaderTextAlignMode.end:
        return TextAlign.end;
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
