import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_component_theme_builder.dart';
import 'package:y300/app/theme/app_theme_palette.dart';
import 'package:y300/app/theme/app_theme_semantics.dart';

/// Y300 全局主题入口。
final class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    return _buildTheme(AppThemePalette.light());
  }

  static ThemeData dark() {
    return _buildTheme(AppThemePalette.dark());
  }

  static ThemeData _buildTheme(AppThemePalette palette) {
    final colorScheme = _buildColorScheme(palette).copyWith(
      primary: palette.primary,
      onPrimary: palette.onPrimary,
      surface: palette.surface,
      onSurface: palette.onSurface,
      surfaceContainerLowest: palette.surfaceContainerLowest,
      surfaceContainer: palette.surfaceContainer,
      surfaceContainerHighest: palette.surfaceContainerHighest,
      onSurfaceVariant: palette.onSurfaceVariant,
      outlineVariant: palette.outlineVariant,
      secondaryContainer: palette.secondaryContainer,
      onSecondaryContainer: palette.onSecondaryContainer,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: palette.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: palette.scaffoldBackground,
      appBarTheme: AppComponentThemeBuilder.appBarTheme(palette),
      navigationBarTheme: AppComponentThemeBuilder.navigationBarTheme(palette),
      popupMenuTheme: AppComponentThemeBuilder.popupMenuTheme(colorScheme),
      menuTheme: AppComponentThemeBuilder.menuTheme(colorScheme),
      dropdownMenuTheme: AppComponentThemeBuilder.dropdownMenuTheme(
        colorScheme,
      ),
      bottomSheetTheme: AppComponentThemeBuilder.bottomSheetTheme(colorScheme),
      dialogTheme: AppComponentThemeBuilder.dialogTheme(colorScheme),
      snackBarTheme: AppComponentThemeBuilder.snackBarTheme(colorScheme),
      segmentedButtonTheme: AppComponentThemeBuilder.segmentedButtonTheme(
        colorScheme,
      ),
      sliderTheme: AppComponentThemeBuilder.sliderTheme(colorScheme),
      listTileTheme: AppComponentThemeBuilder.listTileTheme(colorScheme),
      dividerTheme: AppComponentThemeBuilder.dividerTheme(colorScheme),
      iconButtonTheme: AppComponentThemeBuilder.iconButtonTheme(colorScheme),
      inputDecorationTheme: AppComponentThemeBuilder.inputDecorationTheme(
        colorScheme,
      ),
      chipTheme: AppComponentThemeBuilder.chipTheme(colorScheme),
      cardTheme: AppComponentThemeBuilder.cardTheme(colorScheme),
      extensions: <ThemeExtension<dynamic>>[
        palette.brightness == Brightness.dark
            ? Y300ThemeExtension.dark(palette)
            : Y300ThemeExtension.light(palette),
      ],
    );
  }

  static ColorScheme _buildColorScheme(AppThemePalette palette) {
    return ColorScheme.fromSeed(
      seedColor: palette.seedColor,
      brightness: palette.brightness,
    );
  }
}
