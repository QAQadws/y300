import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/legacy_cache_root_preference_migrator.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('retires the legacy cache override once without reviving it', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferenceKeys.legacyComicCacheDirectory.name: '/legacy/cache/root',
    });
    final preferences = await SharedPreferences.getInstance();
    final migrator = LegacyCacheRootPreferenceMigrator(
      preferencesStore: SharedPreferencesStore(loader: () async => preferences),
    );

    await migrator.migrate();

    expect(
      preferences.containsKey(PreferenceKeys.legacyComicCacheDirectory.name),
      isFalse,
    );
    expect(
      preferences.getInt(PreferenceKeys.legacyCacheRootMigrationVersion.name),
      LegacyCacheRootPreferenceMigrator.migrationVersion,
    );

    await preferences.setString(
      PreferenceKeys.legacyComicCacheDirectory.name,
      '/stale/restored/root',
    );
    await migrator.migrate();

    expect(
      preferences.getString(PreferenceKeys.legacyComicCacheDirectory.name),
      '/stale/restored/root',
    );
  });
}
