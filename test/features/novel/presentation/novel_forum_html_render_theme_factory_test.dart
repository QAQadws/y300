import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/presentation/services/novel_forum_html_render_theme_factory.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  const paletteResolver = NovelReaderThemeResolver();
  const themeFactory = NovelForumHtmlRenderThemeFactory();

  for (final preset in <NovelReaderThemePreset>[
    NovelReaderThemePreset.followApp,
    NovelReaderThemePreset.light,
    NovelReaderThemePreset.sepia,
    NovelReaderThemePreset.dark,
  ]) {
    test('maps the resolved ${preset.name} reader palette directly', () {
      final palette = paletteResolver.resolve(
        preferences: NovelReaderPreferences.defaults().copyWith(
          themePreset: preset,
        ),
        theme: ThemeData.light(),
      );

      final context = themeFactory.fromPalette(palette);

      expect(context.surface, palette.background);
      expect(context.foreground, palette.foreground);
      expect(context.link, palette.link);
      expect(context.quoteSurface, palette.quoteBackground);
      expect(context.quoteForeground, palette.muted);
      expect(context.codeSurface, palette.surface);
      expect(
        context.brightness,
        palette.brightness == Brightness.dark
            ? ForumHtmlBrightness.dark
            : ForumHtmlBrightness.light,
      );
    });
  }
}
