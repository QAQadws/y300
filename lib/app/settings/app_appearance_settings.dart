import 'package:flutter/material.dart';

enum AppThemePreference {
  light,
  dark,
  system;

  ThemeMode get themeMode {
    return switch (this) {
      AppThemePreference.light => ThemeMode.light,
      AppThemePreference.dark => ThemeMode.dark,
      AppThemePreference.system => ThemeMode.system,
    };
  }

  String get displayLabel {
    return switch (this) {
      AppThemePreference.light => '浅色',
      AppThemePreference.dark => '深色',
      AppThemePreference.system => '跟随系统',
    };
  }
}

class AppAppearanceSettings {
  const AppAppearanceSettings({
    required this.themePreference,
  });

  factory AppAppearanceSettings.defaults() {
    return const AppAppearanceSettings(
      themePreference: AppThemePreference.light,
    );
  }

  final AppThemePreference themePreference;

  ThemeMode get themeMode => themePreference.themeMode;

  AppAppearanceSettings copyWith({
    AppThemePreference? themePreference,
  }) {
    return AppAppearanceSettings(
      themePreference: themePreference ?? this.themePreference,
    );
  }
}
