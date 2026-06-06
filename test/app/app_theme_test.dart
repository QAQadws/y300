import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/app/theme/app_theme_tokens.dart';
import 'package:y300/app/y300_app.dart';

void main() {
  test('AppTheme.light exposes the expected scaffold, app bar, and navigation bar colors', () {
    final theme = AppTheme.light();
    final expectedColorScheme = ColorScheme.fromSeed(
      seedColor: AppThemeTokens.seedColor,
      brightness: Brightness.light,
    );

    expect(theme.useMaterial3, isTrue);
    expect(theme.scaffoldBackgroundColor, AppThemeTokens.scaffoldBackground);
    expect(theme.appBarTheme.backgroundColor, AppThemeTokens.appBarBackground);
    expect(theme.appBarTheme.foregroundColor, AppThemeTokens.appBarForeground);
    expect(
      theme.navigationBarTheme.backgroundColor,
      AppThemeTokens.navigationBarBackground,
    );
    expect(theme.colorScheme.primary, expectedColorScheme.primary);
  });

  testWidgets('Y300App wires AppTheme.light into MaterialApp', (tester) async {
    MaterialApp? materialApp;

    await tester.pumpWidget(
      Builder(
        builder: (context) {
          materialApp = const Y300App().build(context) as MaterialApp;
          return const SizedBox.shrink();
        },
      ),
    );

    final theme = materialApp!.theme!;

    expect(theme.scaffoldBackgroundColor, AppThemeTokens.scaffoldBackground);
    expect(theme.appBarTheme.backgroundColor, AppThemeTokens.appBarBackground);
    expect(
      theme.navigationBarTheme.backgroundColor,
      AppThemeTokens.navigationBarBackground,
    );
  });
}
