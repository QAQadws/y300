import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/presentation/services/novel_forum_html_render_theme_factory.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_color_contrast.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';

void main() {
  const resolver = NovelReaderThemeResolver();
  test('every preset/custom RGB extreme keeps generated role contrast', () {
    for (final preset in NovelReaderThemePreset.values) {
      for (final rgb in [
        0x000000,
        0xffffff,
        0xf4ead7,
        0x123456,
        0x777777,
        0x727272,
        0x00ff00,
        0xff00ff,
      ]) {
        final prefs = NovelReaderPreferences.defaults().copyWith(
          themePreset: preset,
          colors: NovelReaderColorOverrides(background: rgb),
        );
        final palette = resolver.resolve(
          preferences: prefs,
          theme: ThemeData.light(),
        );
        expect(palette.background, Color(0xff000000 | rgb));
        expect(
          novelReaderColorContrast(palette.foreground, palette.background),
          greaterThanOrEqualTo(4.5),
        );
        for (final ink in [palette.muted, palette.link, palette.accent]) {
          for (final bg in [
            palette.background,
            palette.surface,
            palette.quoteBackground,
          ]) {
            expect(
              novelReaderColorContrast(ink, bg),
              greaterThanOrEqualTo(4.5),
              reason: '$preset/$rgb',
            );
          }
        }
        expect(
          novelReaderColorContrast(palette.codeForeground, palette.surface),
          greaterThanOrEqualTo(4.5),
        );
        final html = const NovelForumHtmlRenderThemeFactory().fromPalette(
          palette,
        );
        expect(html.codeForeground, palette.codeForeground);
        expect(html.quoteForeground, palette.muted);
      }
    }
  });
  test('explicit low-contrast body choice is exact while generated roles remain readable', () {
    final palette = resolver.resolve(
      preferences: NovelReaderPreferences.defaults().copyWith(
        colors: const NovelReaderColorOverrides(foreground: 0, background: 0),
      ),
      theme: ThemeData.light(),
    );
    expect(palette.foreground, const Color(0xff000000));
    expect(palette.background, const Color(0xff000000));
    expect(novelReaderColorContrast(palette.foreground, palette.background), 1);
    expect(palette.brightness, Brightness.dark);
    expect(
      novelReaderColorContrast(palette.link, palette.background),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      novelReaderColorContrast(palette.codeForeground, palette.surface),
      greaterThanOrEqualTo(4.5),
    );
  });
  test('reset and vertical mode retain existing preset behavior and stored requests', () {
    final prefs = NovelReaderPreferences.defaults().copyWith(
      themePreset: NovelReaderThemePreset.sepia,
      colors: const NovelReaderColorOverrides(
        foreground: 0xabcdef,
        background: 0x123456,
      ),
    );
    final vertical = resolver.resolve(
      preferences: prefs.copyWith(flowMode: NovelReaderFlowMode.vertical),
      theme: ThemeData.dark(),
    );
    final reset = resolver.resolve(
      preferences: prefs.copyWith(colors: const NovelReaderColorOverrides()),
      theme: ThemeData.dark(),
    );
    expect(vertical.foreground, reset.foreground);
    expect(vertical.background, reset.background);
    expect(
      prefs.copyWith(flowMode: NovelReaderFlowMode.vertical).colors,
      prefs.colors,
    );
    expect(
      readableNovelReaderRole(const Color(0xff123456), [
        const Color(0xffffffff),
      ]),
      const Color(0xff123456),
    );
  });
}
