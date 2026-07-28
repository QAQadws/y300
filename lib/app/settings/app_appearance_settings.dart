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
}

enum AppLanguage { system, simplifiedChinese, traditionalChinese }

class AppAppearanceSettings {
  const AppAppearanceSettings({
    required this.themePreference,
    required this.languagePreference,
  });

  factory AppAppearanceSettings.defaults() {
    return const AppAppearanceSettings(
      themePreference: AppThemePreference.light,
      languagePreference: AppLanguage.system,
    );
  }

  final AppThemePreference themePreference;
  final AppLanguage languagePreference;

  ThemeMode get themeMode => themePreference.themeMode;

  AppAppearanceSettings copyWith({
    AppThemePreference? themePreference,
    AppLanguage? languagePreference,
  }) {
    return AppAppearanceSettings(
      themePreference: themePreference ?? this.themePreference,
      languagePreference: languagePreference ?? this.languagePreference,
    );
  }
}
