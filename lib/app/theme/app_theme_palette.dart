import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/app/theme/app_theme_tokens.dart';

/// Concrete light/dark color palette used to build Material semantics.
///
/// Keep stable shell colors in [AppThemeTokens]; this palette is where those
/// baselines are expanded into the Material color roles used by ThemeData.
@immutable
final class AppThemePalette {
  const AppThemePalette({
    required this.family,
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

  factory AppThemePalette.resolve(
    AppThemeFamily family,
    Brightness brightness,
  ) {
    return switch ((family, brightness)) {
      (AppThemeFamily.warmPaper, Brightness.light) => AppThemePalette.light(),
      (AppThemeFamily.warmPaper, Brightness.dark) => AppThemePalette.dark(),
      (AppThemeFamily.moonWhite, Brightness.light) =>
        AppThemePalette.moonWhiteLight(),
      (AppThemeFamily.moonWhite, Brightness.dark) =>
        AppThemePalette.moonWhiteDark(),
      (AppThemeFamily.plumPurple, Brightness.light) =>
        AppThemePalette.plumPurpleLight(),
      (AppThemeFamily.plumPurple, Brightness.dark) =>
        AppThemePalette.plumPurpleDark(),
    };
  }

  factory AppThemePalette.light() {
    return const AppThemePalette(
      family: AppThemeFamily.warmPaper,
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
      family: AppThemeFamily.warmPaper,
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

  factory AppThemePalette.moonWhiteLight() {
    return const AppThemePalette(
      family: AppThemeFamily.moonWhite,
      brightness: Brightness.light,
      seedColor: Color(0xFF4E6D93),
      scaffoldBackground: Color(0xFFF3F6FA),
      appBarBackground: Color(0xFF2E3F5A),
      appBarForeground: Color(0xFFF8FAFD),
      navigationBarBackground: Color(0xFFE4EAF2),
      primary: Color(0xFF4E6D93),
      onPrimary: Color(0xFFFFFFFF),
      surface: Color(0xFFF3F6FA),
      onSurface: Color(0xFF202934),
      surfaceContainerLowest: Color(0xFFFCFDFE),
      surfaceContainer: Color(0xFFF8FAFC),
      surfaceContainerHighest: Color(0xFFE4EAF2),
      onSurfaceVariant: Color(0xFF667487),
      outlineVariant: Color(0xFFCAD4E0),
      secondaryContainer: Color(0xFFDFE8F2),
      onSecondaryContainer: Color(0xFF263C55),
    );
  }

  factory AppThemePalette.moonWhiteDark() {
    return const AppThemePalette(
      family: AppThemeFamily.moonWhite,
      brightness: Brightness.dark,
      seedColor: Color(0xFFAFC8E6),
      scaffoldBackground: Color(0xFF121820),
      appBarBackground: Color(0xFF1B2A3D),
      appBarForeground: Color(0xFFF2F6FB),
      navigationBarBackground: Color(0xFF1D2B3A),
      primary: Color(0xFFAFC8E6),
      onPrimary: Color(0xFF18324D),
      surface: Color(0xFF121820),
      onSurface: Color(0xFFEAF0F7),
      surfaceContainerLowest: Color(0xFF0D131A),
      surfaceContainer: Color(0xFF19222D),
      surfaceContainerHighest: Color(0xFF263444),
      onSurfaceVariant: Color(0xFFB6C2D0),
      outlineVariant: Color(0xFF3D4D60),
      secondaryContainer: Color(0xFF293D53),
      onSecondaryContainer: Color(0xFFDDEAF6),
    );
  }

  factory AppThemePalette.plumPurpleLight() {
    return const AppThemePalette(
      family: AppThemeFamily.plumPurple,
      brightness: Brightness.light,
      seedColor: Color(0xFF8B5D70),
      scaffoldBackground: Color(0xFFF8F1F4),
      appBarBackground: Color(0xFF67404F),
      appBarForeground: Color(0xFFFFF8FA),
      navigationBarBackground: Color(0xFFEBDDE3),
      primary: Color(0xFF8B5D70),
      onPrimary: Color(0xFFFFFFFF),
      surface: Color(0xFFF8F1F4),
      onSurface: Color(0xFF34252B),
      surfaceContainerLowest: Color(0xFFFFFCFD),
      surfaceContainer: Color(0xFFFFF8FA),
      surfaceContainerHighest: Color(0xFFF0E1E7),
      onSurfaceVariant: Color(0xFF7D6871),
      outlineVariant: Color(0xFFDCC8D0),
      secondaryContainer: Color(0xFFECDDE3),
      onSecondaryContainer: Color(0xFF52323F),
    );
  }

  factory AppThemePalette.plumPurpleDark() {
    return const AppThemePalette(
      family: AppThemeFamily.plumPurple,
      brightness: Brightness.dark,
      seedColor: Color(0xFFD9AFC0),
      scaffoldBackground: Color(0xFF1A1216),
      appBarBackground: Color(0xFF3A2430),
      appBarForeground: Color(0xFFFFF4F8),
      navigationBarBackground: Color(0xFF2B1C23),
      primary: Color(0xFFD9AFC0),
      onPrimary: Color(0xFF472634),
      surface: Color(0xFF1A1216),
      onSurface: Color(0xFFF4E8ED),
      surfaceContainerLowest: Color(0xFF110C0F),
      surfaceContainer: Color(0xFF261A20),
      surfaceContainerHighest: Color(0xFF3A2931),
      onSurfaceVariant: Color(0xFFCDB8C1),
      outlineVariant: Color(0xFF5A414B),
      secondaryContainer: Color(0xFF49323C),
      onSecondaryContainer: Color(0xFFF2DCE5),
    );
  }

  final AppThemeFamily family;
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
