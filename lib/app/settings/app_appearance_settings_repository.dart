import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/app/theme/app_theme_family.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';

abstract class AppAppearanceSettingsRepository {
  Future<AppAppearanceSettings> load();

  Future<void> save(AppAppearanceSettings settings);
}

class SharedPrefsAppAppearanceSettingsRepository
    implements AppAppearanceSettingsRepository {
  SharedPrefsAppAppearanceSettingsRepository({
    PreferencesStore? preferencesStore,
  }) : _preferencesStore = preferencesStore ?? SharedPreferencesStore();

  final PreferencesStore _preferencesStore;

  @override
  Future<AppAppearanceSettings> load() async {
    return AppAppearanceSettings(
      themeFamily: _parseThemeFamily(
        await _preferencesStore.read(PreferenceKeys.appThemeFamily),
      ),
      brightnessPreference: _parseBrightnessPreference(
        await _preferencesStore.read(PreferenceKeys.appThemePreference),
      ),
      languagePreference: _parseLanguage(
        await _preferencesStore.read(PreferenceKeys.appLanguagePreference),
      ),
    );
  }

  @override
  Future<void> save(AppAppearanceSettings settings) async {
    await _preferencesStore.write(
      PreferenceKeys.appThemeFamily,
      settings.themeFamily.name,
    );
    await _preferencesStore.write(
      PreferenceKeys.appThemePreference,
      settings.brightnessPreference.name,
    );
    await _preferencesStore.write(
      PreferenceKeys.appLanguagePreference,
      settings.languagePreference.name,
    );
  }

  AppThemeFamily _parseThemeFamily(String? raw) {
    for (final family in AppThemeFamily.values) {
      if (family.name == raw) {
        return family;
      }
    }
    return AppThemeFamily.warmPaper;
  }

  AppBrightnessPreference _parseBrightnessPreference(String? raw) {
    for (final preference in AppBrightnessPreference.values) {
      if (preference.name == raw) {
        return preference;
      }
    }
    return AppBrightnessPreference.light;
  }

  AppLanguage _parseLanguage(String? raw) {
    for (final language in AppLanguage.values) {
      if (language.name == raw) {
        return language;
      }
    }
    return AppLanguage.system;
  }
}
