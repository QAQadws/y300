import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_tokens.dart';

/// Y300 全局主题入口。
final class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    return _buildTheme(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppThemeTokens.scaffoldBackground,
      appBarBackgroundColor: AppThemeTokens.appBarBackground,
      appBarForegroundColor: AppThemeTokens.appBarForeground,
      navigationBarBackgroundColor: AppThemeTokens.navigationBarBackground,
    );
  }

  static ThemeData dark() {
    return _buildTheme(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF17110F),
      appBarBackgroundColor: const Color(0xFF2A0903),
      appBarForegroundColor: const Color(0xFFFFEDE0),
      navigationBarBackgroundColor: const Color(0xFF241412),
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color scaffoldBackgroundColor,
    required Color appBarBackgroundColor,
    required Color appBarForegroundColor,
    required Color navigationBarBackgroundColor,
  }) {
    final colorScheme = _buildColorScheme(brightness: brightness).copyWith(
      surface: scaffoldBackgroundColor,
      onSurface: brightness == Brightness.dark
          ? const Color(0xFFF6E8DD)
          : null,
      surfaceContainerHighest: brightness == Brightness.dark
          ? const Color(0xFF3A2A25)
          : null,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      appBarTheme: _buildAppBarTheme(
        backgroundColor: appBarBackgroundColor,
        foregroundColor: appBarForegroundColor,
      ),
      navigationBarTheme: _buildNavigationBarTheme(
        backgroundColor: navigationBarBackgroundColor,
      ),
    );
  }

  static ColorScheme _buildColorScheme({
    required Brightness brightness,
  }) {
    return ColorScheme.fromSeed(
      seedColor: AppThemeTokens.seedColor,
      brightness: brightness,
    );
  }

  static AppBarTheme _buildAppBarTheme({
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return AppBarTheme(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    );
  }

  static NavigationBarThemeData _buildNavigationBarTheme({
    required Color backgroundColor,
  }) {
    return NavigationBarThemeData(
      backgroundColor: backgroundColor,
    );
  }
}
