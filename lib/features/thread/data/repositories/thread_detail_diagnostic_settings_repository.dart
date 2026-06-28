import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/app_storage_keys.dart';

abstract class ThreadDetailDiagnosticSettingsRepository {
  Future<bool> loadScrollDiagnosticEnabled();

  Future<void> setScrollDiagnosticEnabled(bool enabled);
}

class SharedPrefsThreadDetailDiagnosticSettingsRepository
    implements ThreadDetailDiagnosticSettingsRepository {
  const SharedPrefsThreadDetailDiagnosticSettingsRepository();

  @override
  Future<bool> loadScrollDiagnosticEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppStorageKeys.threadDetailScrollDiagnosticEnabled) ??
        false;
  }

  @override
  Future<void> setScrollDiagnosticEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      AppStorageKeys.threadDetailScrollDiagnosticEnabled,
      enabled,
    );
  }
}
