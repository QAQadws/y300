import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/presentation/detail/unified_detail_palette.dart';

void main() {
  test('UnifiedDetailPaletteResolver uses scaffold background as gradient end', () {
    const pageBackground = Color(0xFF123456);
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      scaffoldBackgroundColor: pageBackground,
    );

    final palette = const UnifiedDetailPaletteResolver().resolve(theme);

    expect(palette.pageBackground, pageBackground);
    expect(palette.headerGradientEnd, pageBackground);
    expect(palette.collapsedAppBarBackground, pageBackground);
  });

  test('UnifiedDetailPaletteResolver keeps dark gradient end non-white', () {
    const pageBackground = Color(0xFF101214);
    final theme = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: pageBackground,
    );

    final palette = const UnifiedDetailPaletteResolver().resolve(theme);

    expect(palette.headerGradientEnd, pageBackground);
    expect(palette.headerGradientEnd, isNot(Colors.white));
    expect(palette.collapsedAppBarForeground, Colors.white);
  });

  test('UnifiedDetailPaletteResolver exposes stable light fallback colors', () {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
    );

    final palette = const UnifiedDetailPaletteResolver().resolve(theme);

    expect(palette.headerFallbackBackground, isNot(equals(Colors.white)));
    expect(palette.headerPlaceholderBackground, isNot(equals(Colors.white)));
    expect(palette.onHeader, Colors.white);
  });
}
