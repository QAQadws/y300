import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';

abstract class SyncDiagnosticSettingsRepository {
  Future<bool> loadManualModeEnabled();

  Future<void> setManualModeEnabled(bool enabled);
}

class SharedPrefsSyncDiagnosticSettingsRepository
    implements SyncDiagnosticSettingsRepository {
  SharedPrefsSyncDiagnosticSettingsRepository({
    PreferencesStore? preferencesStore,
  }) : _preferencesStore = preferencesStore ?? SharedPreferencesStore();

  final PreferencesStore _preferencesStore;

  @override
  Future<bool> loadManualModeEnabled() async {
    return await _preferencesStore.read(
          PreferenceKeys.syncDiagnosticManualMode,
        ) ??
        false;
  }

  @override
  Future<void> setManualModeEnabled(bool enabled) async {
    await _preferencesStore.write(
      PreferenceKeys.syncDiagnosticManualMode,
      enabled,
    );
  }
}
