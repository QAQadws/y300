import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/app/settings/app_appearance_settings.dart';
import 'package:y300/core/config/app_storage_keys.dart';

abstract class AppAppearanceSettingsRepository {
  Future<AppAppearanceSettings> load();

  Future<void> save(AppAppearanceSettings settings);
}

class SharedPrefsAppAppearanceSettingsRepository
    implements AppAppearanceSettingsRepository {
  @override
  Future<AppAppearanceSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppAppearanceSettings(
      themePreference: _parseThemePreference(
        prefs.getString(AppStorageKeys.appThemePreference),
      ),
    );
  }

  @override
  Future<void> save(AppAppearanceSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppStorageKeys.appThemePreference,
      settings.themePreference.name,
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
}
