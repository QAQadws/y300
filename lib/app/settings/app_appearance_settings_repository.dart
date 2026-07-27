import 'package:y300/app/settings/app_appearance_settings.dart';
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
      themePreference: _parseThemePreference(
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
      PreferenceKeys.appThemePreference,
      settings.themePreference.name,
    );
    await _preferencesStore.write(
      PreferenceKeys.appLanguagePreference,
      settings.languagePreference.name,
    );
  }

  AppThemePreference _parseThemePreference(String? raw) {
    for (final preference in AppThemePreference.values) {
      if (preference.name == raw) {
        return preference;
      }
    }
    return AppThemePreference.light;
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
