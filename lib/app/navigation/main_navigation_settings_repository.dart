import 'package:y300/app/navigation/main_navigation_settings.dart';
import 'package:y300/app/navigation/main_navigation_settings_snapshot_codec.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';

abstract interface class MainNavigationSettingsRepository {
  Future<MainNavigationSettings> load();

  Future<void> save(MainNavigationSettings settings);
}

final class SharedPrefsMainNavigationSettingsRepository
    implements MainNavigationSettingsRepository {
  SharedPrefsMainNavigationSettingsRepository({
    PreferencesStore? preferencesStore,
  }) : _preferencesStore = preferencesStore ?? SharedPreferencesStore();

  final PreferencesStore _preferencesStore;

  @override
  Future<MainNavigationSettings> load() async {
    return MainNavigationSettingsSnapshotCodec.decode(
      await _preferencesStore.read(PreferenceKeys.appNavigationSnapshotV1),
    );
  }

  @override
  Future<void> save(MainNavigationSettings settings) {
    return _preferencesStore.write(
      PreferenceKeys.appNavigationSnapshotV1,
      MainNavigationSettingsSnapshotCodec.encode(settings),
    );
  }
}
