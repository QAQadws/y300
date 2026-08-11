import 'package:flutter/material.dart';
import 'package:y300/app/theme/app_theme_family.dart';

enum AppBrightnessPreference {
  light,
  dark,
  system;

  ThemeMode get themeMode {
    return switch (this) {
      AppBrightnessPreference.light => ThemeMode.light,
      AppBrightnessPreference.dark => ThemeMode.dark,
      AppBrightnessPreference.system => ThemeMode.system,
    };
  }
}

enum AppLanguage { system, simplifiedChinese, traditionalChinese }

class AppAppearanceSettings {
  const AppAppearanceSettings({
    this.themeFamily = AppThemeFamily.warmPaper,
    this.brightnessPreference = AppBrightnessPreference.light,
    required this.languagePreference,
  });

  factory AppAppearanceSettings.defaults() {
    return const AppAppearanceSettings(
      themeFamily: AppThemeFamily.warmPaper,
      brightnessPreference: AppBrightnessPreference.light,
      languagePreference: AppLanguage.system,
    );
  }

  final AppThemeFamily themeFamily;
  final AppBrightnessPreference brightnessPreference;
  final AppLanguage languagePreference;

  ThemeMode get themeMode => brightnessPreference.themeMode;

  AppAppearanceSettings copyWith({
    AppThemeFamily? themeFamily,
    AppBrightnessPreference? brightnessPreference,
    AppLanguage? languagePreference,
  }) {
    return AppAppearanceSettings(
      themeFamily: themeFamily ?? this.themeFamily,
      brightnessPreference: brightnessPreference ?? this.brightnessPreference,
      languagePreference: languagePreference ?? this.languagePreference,
    );
  }
}
