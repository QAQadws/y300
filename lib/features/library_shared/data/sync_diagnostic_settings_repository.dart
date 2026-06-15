import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/config/app_storage_keys.dart';

abstract class SyncDiagnosticSettingsRepository {
  Future<bool> loadManualModeEnabled();

  Future<void> setManualModeEnabled(bool enabled);
}

class SharedPrefsSyncDiagnosticSettingsRepository
    implements SyncDiagnosticSettingsRepository {
  @override
  Future<bool> loadManualModeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(AppStorageKeys.syncDiagnosticManualMode) ?? false;
  }

  @override
  Future<void> setManualModeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppStorageKeys.syncDiagnosticManualMode, enabled);
  }
}
