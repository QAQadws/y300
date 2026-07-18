import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';

/// Retires the old custom cache-root preference without touching user files.
///
/// Cached-image records keep absolute paths, so protected covers that still
/// exist under the old root remain readable and are cleaned by their normal
/// owner lifecycle. New cache writes always use the platform temporary root.
class LegacyCacheRootPreferenceMigrator {
  const LegacyCacheRootPreferenceMigrator({
    required PreferencesStore preferencesStore,
  }) : _preferencesStore = preferencesStore;

  static const int migrationVersion = 1;

  final PreferencesStore _preferencesStore;

  Future<void> migrate() async {
    final completedVersion =
        await _preferencesStore.read(
          PreferenceKeys.legacyCacheRootMigrationVersion,
        ) ??
        0;
    if (completedVersion >= migrationVersion) {
      return;
    }

    if (await _preferencesStore.contains(
      PreferenceKeys.legacyComicCacheDirectory,
    )) {
      await _preferencesStore.remove(
        PreferenceKeys.legacyComicCacheDirectory,
      );
    }
    await _preferencesStore.write(
      PreferenceKeys.legacyCacheRootMigrationVersion,
      migrationVersion,
    );
  }
}
