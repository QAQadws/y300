import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_render_theme_factory.dart';
import 'package:y300/features/thread/presentation/widgets/thread_detail_theme.dart';

void main() {
  const factory = ForumHtmlRenderThemeFactory();

  test('builds stable signatures from every render color', () {
    final first = factory.fromMaterialTheme(
      theme: AppTheme.light(),
      surface: const Color(0xFFFDF5E6),
      foreground: const Color(0xFF332211),
    );
    final same = factory.fromMaterialTheme(
      theme: AppTheme.light(),
      surface: const Color(0xFFFDF5E6),
      foreground: const Color(0xFF332211),
    );
    final changed = factory.fromMaterialTheme(
      theme: AppTheme.light(),
      surface: const Color(0xFFFDF5E5),
      foreground: const Color(0xFF332211),
    );

    expect(first.signature, same.signature);
    expect(first.signature, isNot(changed.signature));
    expect(first.signature, startsWith('forum-html-theme-v1:light:'));
  });

  test('maps the actual thread card and foreground into the context', () {
    final appTheme = AppTheme.dark();
    final palette = ThreadDetailNativePalette.resolve(appTheme);

    final context = factory.fromThreadPalette(
      palette: palette,
      brightness: appTheme.brightness,
    );

    expect(context.surface, palette.card);
    expect(context.foreground, palette.bodyText);
    expect(context.brightness.name, 'dark');
  });

  test('uses the explicitly supplied Material container surface', () {
    const surface = Color(0xFF102030);
    const foreground = Color(0xFFF0E0D0);

    final context = factory.fromMaterialTheme(
      theme: AppTheme.dark(),
      surface: surface,
      foreground: foreground,
    );

    expect(context.surface, surface);
    expect(context.foreground, foreground);
  });
}
