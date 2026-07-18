import 'package:flutter/foundation.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';

abstract class ThreadDetailDiagnosticSettingsRepository {
  Future<bool> loadScrollDiagnosticEnabled();

  Future<void> setScrollDiagnosticEnabled(bool enabled);
}

class SharedPrefsThreadDetailDiagnosticSettingsRepository
    implements ThreadDetailDiagnosticSettingsRepository {
  SharedPrefsThreadDetailDiagnosticSettingsRepository({
    PreferencesStore? preferencesStore,
    bool diagnosticsEnabled = kDebugMode,
  }) : _preferencesStore = preferencesStore ?? SharedPreferencesStore(),
       _diagnosticsEnabled = diagnosticsEnabled;

  final PreferencesStore _preferencesStore;
  final bool _diagnosticsEnabled;

  @override
  Future<bool> loadScrollDiagnosticEnabled() async {
    if (!_diagnosticsEnabled) {
      return false;
    }
    return await _preferencesStore.read(
          PreferenceKeys.threadDetailScrollDiagnosticEnabled,
        ) ??
        false;
  }

  @override
  Future<void> setScrollDiagnosticEnabled(bool enabled) async {
    if (!_diagnosticsEnabled) {
      return;
    }
    await _preferencesStore.write(
      PreferenceKeys.threadDetailScrollDiagnosticEnabled,
      enabled,
    );
  }
}
