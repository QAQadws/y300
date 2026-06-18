import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_tokens.dart';

/// Concrete light/dark color palette used to build Material semantics.
///
/// Keep stable shell colors in [AppThemeTokens]; this palette is where those
/// baselines are expanded into the Material color roles used by ThemeData.
@immutable
final class AppThemePalette {
  const AppThemePalette({
    required this.brightness,
    required this.seedColor,
    required this.scaffoldBackground,
    required this.appBarBackground,
    required this.appBarForeground,
    required this.navigationBarBackground,
    required this.primary,
    required this.onPrimary,
    required this.surface,
    required this.onSurface,
    required this.surfaceContainerLowest,
    required this.surfaceContainer,
    required this.surfaceContainerHighest,
    required this.onSurfaceVariant,
    required this.outlineVariant,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
  });

  factory AppThemePalette.light() {
    return const AppThemePalette(
      brightness: Brightness.light,
      seedColor: AppThemeTokens.seedColor,
      scaffoldBackground: AppThemeTokens.scaffoldBackground,
      appBarBackground: AppThemeTokens.appBarBackground,
      appBarForeground: AppThemeTokens.appBarForeground,
      navigationBarBackground: AppThemeTokens.navigationBarBackground,
      primary: AppThemeTokens.seedColor,
      onPrimary: Color(0xFFFFF8EE),
      surface: AppThemeTokens.scaffoldBackground,
      onSurface: Color(0xFF2F2117),
      surfaceContainerLowest: Color(0xFFFFFCF0),
      surfaceContainer: AppThemeTokens.forumWebviewSectionBackground,
      surfaceContainerHighest: Color(0xFFEFE1CD),
      onSurfaceVariant: Color(0xFF6F5B46),
      outlineVariant: Color(0xFFE0C9A8),
      secondaryContainer: AppThemeTokens.navigationBarBackground,
      onSecondaryContainer: Color(0xFF3F230F),
    );
  }

  factory AppThemePalette.dark() {
    return const AppThemePalette(
      brightness: Brightness.dark,
      seedColor: AppThemeTokens.seedColor,
      scaffoldBackground: Color(0xFF17110F),
      appBarBackground: Color(0xFF2A0903),
      appBarForeground: Color(0xFFFFEDE0),
      navigationBarBackground: Color(0xFF241412),
      primary: Color(0xFFE8B884),
      onPrimary: Color(0xFF3A1604),
      surface: Color(0xFF17110F),
      onSurface: Color(0xFFF6E8DD),
      surfaceContainerLowest: Color(0xFF100B09),
      surfaceContainer: Color(0xFF241916),
      surfaceContainerHighest: Color(0xFF3A2A25),
      onSurfaceVariant: Color(0xFFD7C2B6),
      outlineVariant: Color(0xFF5A453D),
      secondaryContainer: Color(0xFF4A342C),
      onSecondaryContainer: Color(0xFFFFE1D2),
    );
  }

  final Brightness brightness;
  final Color seedColor;
  final Color scaffoldBackground;
  final Color appBarBackground;
  final Color appBarForeground;
  final Color navigationBarBackground;
  final Color primary;
  final Color onPrimary;
  final Color surface;
  final Color onSurface;
  final Color surfaceContainerLowest;
  final Color surfaceContainer;
  final Color surfaceContainerHighest;
  final Color onSurfaceVariant;
  final Color outlineVariant;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
}
