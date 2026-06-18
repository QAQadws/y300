import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';
import 'package:y300/features/forum/presentation/webview/theme/forum_webview_theme_palette_resolver.dart';

void main() {
  const resolver = ForumWebViewThemePaletteResolver();

  test('resolves light app theme into a complete WebView palette', () {
    final theme = AppTheme.light();
    final scheme = theme.colorScheme;
    final palette = resolver.resolve(theme);

    expect(palette.brightness, Brightness.light);
    expect(palette.colorScheme, 'light');
    expect(palette.pageBackground, theme.scaffoldBackgroundColor);
    expect(palette.surface, scheme.surfaceContainer);
    expect(palette.surfaceElevated, scheme.surfaceContainerHighest);
    expect(palette.sectionHeaderBackground, scheme.surfaceContainer);
    expect(palette.text, scheme.onSurface);
    expect(palette.mutedText, scheme.onSurfaceVariant);
    expect(
      palette.subtleText,
      scheme.onSurfaceVariant.withValues(alpha: 0.72),
    );
    expect(palette.link, scheme.primary);
    expect(palette.border, scheme.outlineVariant);
    expect(palette.inputBackground, scheme.surfaceContainerHighest);
    expect(palette.inputText, scheme.onSurface);
    expect(palette.buttonBackground, scheme.secondaryContainer);
    expect(palette.buttonText, scheme.onSecondaryContainer);
    expect(palette.quoteBackground, scheme.surfaceContainer);
    expect(palette.codeBackground, scheme.surfaceContainerLowest);
    expect(
      palette.activeBackground,
      scheme.primary.withValues(alpha: 0.10),
    );
    expect(palette.signature, startsWith('light:'));
    expect(palette.signature, contains(_hex(theme.scaffoldBackgroundColor)));
    expect(palette.signature, contains(_hex(scheme.surfaceContainer)));
    expect(palette.signature, contains(_hex(scheme.onSurface)));
    expect(palette.signature, contains(_hex(scheme.outlineVariant)));
  });

  test('resolves dark app theme into a dark WebView palette', () {
    final light = resolver.resolve(AppTheme.light());
    final theme = AppTheme.dark();
    final scheme = theme.colorScheme;
    final y300 = theme.extension<Y300ThemeExtension>()!;
    final palette = resolver.resolve(theme);

    expect(palette.brightness, Brightness.dark);
    expect(palette.colorScheme, 'dark');
    expect(palette.pageBackground, theme.scaffoldBackgroundColor);
    expect(palette.surface, scheme.surfaceContainer);
    expect(palette.surfaceElevated, scheme.surfaceContainerHighest);
    expect(palette.sectionHeaderBackground, scheme.surfaceContainerHighest);
    expect(palette.text, scheme.onSurface);
    expect(palette.border, scheme.outlineVariant);
    expect(palette.activeBackground, scheme.primary.withValues(alpha: 0.14));
    expect(palette.scrim, y300.readerOverlayScrim);
    expect(palette.pageBackground, isNot(light.pageBackground));
    expect(palette.surface, isNot(light.surface));
    expect(palette.text, isNot(light.text));
    expect(palette.border, isNot(light.border));
    expect(palette.signature, startsWith('dark:'));
    expect(palette.signature, contains(_hex(theme.scaffoldBackgroundColor)));
    expect(palette.signature, contains(_hex(scheme.surfaceContainer)));
    expect(palette.signature, contains(_hex(scheme.onSurface)));
    expect(palette.signature, contains(_hex(scheme.outlineVariant)));
  });

  test('falls back when Y300ThemeExtension is absent', () {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF336699),
        brightness: Brightness.dark,
      ),
    );

    final palette = resolver.resolve(theme);

    expect(palette.brightness, Brightness.dark);
    expect(palette.colorScheme, 'dark');
    expect(palette.scrim, Colors.black.withValues(alpha: 0.44));
  });
}

String _hex(Color color) {
  final rgb = color.toARGB32() & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
