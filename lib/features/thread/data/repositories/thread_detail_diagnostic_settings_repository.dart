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
  }) : _preferencesStore = preferencesStore ?? SharedPreferencesStore();

  final PreferencesStore _preferencesStore;

  @override
  Future<bool> loadScrollDiagnosticEnabled() async {
    return await _preferencesStore.read(
          PreferenceKeys.threadDetailScrollDiagnosticEnabled,
        ) ??
        false;
  }

  @override
  Future<void> setScrollDiagnosticEnabled(bool enabled) async {
    await _preferencesStore.write(
      PreferenceKeys.threadDetailScrollDiagnosticEnabled,
      enabled,
    );
  }
}
