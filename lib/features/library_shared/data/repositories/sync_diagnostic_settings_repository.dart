import 'package:flutter/foundation.dart';
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
    bool diagnosticsEnabled = kDebugMode,
  }) : _preferencesStore = preferencesStore ?? SharedPreferencesStore(),
       _diagnosticsEnabled = diagnosticsEnabled;

  final PreferencesStore _preferencesStore;
  final bool _diagnosticsEnabled;

  @override
  Future<bool> loadManualModeEnabled() async {
    if (!_diagnosticsEnabled) {
      return false;
    }
    return await _preferencesStore.read(
          PreferenceKeys.syncDiagnosticManualMode,
        ) ??
        false;
  }

  @override
  Future<void> setManualModeEnabled(bool enabled) async {
    if (!_diagnosticsEnabled) {
      return;
    }
    await _preferencesStore.write(
      PreferenceKeys.syncDiagnosticManualMode,
      enabled,
    );
  }
}
