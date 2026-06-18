import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_palette.dart';

/// Central place for Material component theme construction.
///
/// A-2.1 only moves existing shell component themes here. A-2.2 will extend
/// this builder for menus, sheets, sliders, and segmented buttons.
final class AppComponentThemeBuilder {
  const AppComponentThemeBuilder._();

  static AppBarTheme appBarTheme(AppThemePalette palette) {
    return AppBarTheme(
      backgroundColor: palette.appBarBackground,
      foregroundColor: palette.appBarForeground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    );
  }

  static NavigationBarThemeData navigationBarTheme(AppThemePalette palette) {
    return NavigationBarThemeData(
      backgroundColor: palette.navigationBarBackground,
    );
  }
}
