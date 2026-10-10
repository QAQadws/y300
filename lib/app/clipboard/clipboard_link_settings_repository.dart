import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';

abstract interface class ClipboardLinkSettingsRepository {
  Future<bool> loadEnabled();

  Future<void> saveEnabled(bool enabled);
}

class SharedPrefsClipboardLinkSettingsRepository
    implements ClipboardLinkSettingsRepository {
  SharedPrefsClipboardLinkSettingsRepository({
    PreferencesStore? preferencesStore,
  }) : _preferencesStore = preferencesStore ?? SharedPreferencesStore();

  final PreferencesStore _preferencesStore;

  @override
  Future<bool> loadEnabled() async =>
      await _preferencesStore.read(
        PreferenceKeys.appClipboardLinkDetectionEnabledV1,
      ) ??
      true;

  @override
  Future<void> saveEnabled(bool enabled) => _preferencesStore.write(
    PreferenceKeys.appClipboardLinkDetectionEnabledV1,
    enabled,
  );
}
