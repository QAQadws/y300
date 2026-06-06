import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_tokens.dart';

/// Y300 全局主题入口。
final class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: _buildColorScheme(),
      scaffoldBackgroundColor: AppThemeTokens.scaffoldBackground,
      appBarTheme: _buildAppBarTheme(),
      navigationBarTheme: _buildNavigationBarTheme(),
    );
  }

  static ColorScheme _buildColorScheme() {
    return ColorScheme.fromSeed(
      seedColor: AppThemeTokens.seedColor,
      brightness: Brightness.light,
    );
  }

  static AppBarTheme _buildAppBarTheme() {
    return const AppBarTheme(
      backgroundColor: AppThemeTokens.appBarBackground,
      foregroundColor: AppThemeTokens.appBarForeground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    );
  }

  static NavigationBarThemeData _buildNavigationBarTheme() {
    return const NavigationBarThemeData(
      backgroundColor: AppThemeTokens.navigationBarBackground,
    );
  }
}
