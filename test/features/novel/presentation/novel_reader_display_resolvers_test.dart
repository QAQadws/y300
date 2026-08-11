import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';

void main() {
  const themeResolver = NovelReaderThemeResolver();
  const typographyResolver = NovelReaderTypographyResolver();

  test('NovelReaderThemeResolver resolves stable preset palettes', () {
    final theme = ThemeData.light();

    final light = themeResolver.resolve(
      preferences: NovelReaderPreferences.defaults().copyWith(
        themePreset: NovelReaderThemePreset.light,
      ),
      theme: theme,
    );
    final sepia = themeResolver.resolve(
      preferences: NovelReaderPreferences.defaults().copyWith(
        themePreset: NovelReaderThemePreset.sepia,
      ),
      theme: theme,
    );
    final dark = themeResolver.resolve(
      preferences: NovelReaderPreferences.defaults().copyWith(
        themePreset: NovelReaderThemePreset.dark,
      ),
      theme: theme,
    );

    expect(light.background, const Color(0xFFFDFDFD));
    expect(light.foreground, const Color(0xFF1F1F1F));
    expect(sepia.background, const Color(0xFFF4EAD7));
    expect(sepia.foreground, const Color(0xFF4C3A21));
    expect(dark.background, const Color(0xFF141414));
    expect(dark.foreground, const Color(0xFFE9E9E9));
  });

  test('NovelReaderThemeResolver follows the active application theme', () {
    final preferences = NovelReaderPreferences.defaults().copyWith(
      themePreset: NovelReaderThemePreset.followApp,
    );

    for (final family in AppThemeFamily.values) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.build(family: family, brightness: brightness);
        final palette = themeResolver.resolve(
          preferences: preferences,
          theme: theme,
        );

        expect(palette.brightness, theme.brightness);
        expect(palette.background, theme.scaffoldBackgroundColor);
        expect(palette.foreground, theme.colorScheme.onSurface);
        expect(palette.muted, theme.colorScheme.onSurfaceVariant);
        expect(palette.accent, theme.colorScheme.primary);
        expect(palette.surface, theme.colorScheme.surfaceContainer);
        expect(palette.link, theme.colorScheme.primary);
        expect(
          palette.quoteBackground,
          theme.colorScheme.surfaceContainerHighest,
        );
      }
    }
  });

  test('NovelReaderTypographyResolver applies advanced preferences', () {
    final theme = ThemeData.light();
    final palette = themeResolver.resolve(
      preferences: NovelReaderPreferences.defaults(),
      theme: theme,
    );
    final typography = typographyResolver.resolve(
      preferences: NovelReaderPreferences.defaults().copyWith(
        fontSize: 21,
        lineHeight: 2,
        fontWeight: 700,
        fontFamily: 'serif',
        textAlign: NovelReaderTextAlignMode.justify,
        firstLineIndent: 32,
        contentMaxWidth: 680,
      ),
      theme: theme,
      palette: palette,
    );

    expect(typography.body.fontSize, 21);
    expect(typography.body.height, 2);
    expect(typography.body.fontWeight, FontWeight.w700);
    expect(typography.body.fontFamily, 'serif');
    expect(typography.textAlign, TextAlign.justify);
    expect(typography.firstLineIndent, 32);
    expect(typography.contentMaxWidth, 680);
  });
}
