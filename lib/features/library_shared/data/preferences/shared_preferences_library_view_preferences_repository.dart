import 'package:y300/core/preferences/preference_key.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/library_shared/data/preferences/library_view_preferences_legacy_source.dart';
import 'package:y300/features/library_shared/data/preferences/library_view_preferences_snapshot_codec.dart';
import 'package:y300/features/library_shared/domain/contracts/library_view_preferences_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_view_preferences.dart';

final class SharedPreferencesLibraryViewPreferencesRepository
    implements LibraryViewPreferencesRepository {
  SharedPreferencesLibraryViewPreferencesRepository({
    required PreferencesStore preferencesStore,
    required LibraryViewPreferencesLegacySource legacySource,
    LibraryViewPreferencesSnapshotCodec codec =
        const LibraryViewPreferencesSnapshotCodec(),
  }) : _preferencesStore = preferencesStore,
       _legacySource = legacySource,
       _codec = codec;

  static const int migrationVersion = 1;

  final PreferencesStore _preferencesStore;
  final LibraryViewPreferencesLegacySource _legacySource;
  final LibraryViewPreferencesSnapshotCodec _codec;

  @override
  Future<LibraryShelfViewPreferences> load({
    required LibraryShelfViewPreferences defaults,
  }) async {
    final keys = _keysFor(defaults.moduleKey);
    if (await _preferencesStore.contains(keys.snapshot)) {
      return _codec.decode(
        await _preferencesStore.read(keys.snapshot),
        defaults: defaults,
      );
    }

    final completedVersion =
        await _preferencesStore.read(keys.migrationVersion) ?? 0;
    if (completedVersion >= migrationVersion) {
      return defaults;
    }

    LegacyLibraryDisplayPreferences? legacy;
    try {
      legacy = await _legacySource.loadDisplayPreferences(
        moduleKey: defaults.moduleKey,
        defaultDisplayMode: defaults.displayMode,
        defaultGridColumnCount: defaults.gridColumnCount,
      );
    } catch (_) {
      // Legacy data must never prevent the shelf from opening. Persisting the
      // normalized defaults also prevents repeated reads of a broken source.
      legacy = null;
    }
    final migrated = _codec.normalize(
      legacy == null
          ? defaults
          : defaults.copyWith(
              displayMode: legacy.displayMode,
              gridColumnCount: legacy.gridColumnCount,
            ),
      defaults: defaults,
    );
    await _write(keys, migrated, defaults: defaults);
    return migrated;
  }

  @override
  Future<void> save(LibraryShelfViewPreferences preferences) async {
    final defaults = LibraryShelfViewPreferences.defaults(
      moduleKey: preferences.moduleKey,
      displayMode: preferences.displayMode,
      sortOption: preferences.sortOption,
    );
    await _write(
      _keysFor(preferences.moduleKey),
      preferences,
      defaults: defaults,
    );
  }

  Future<void> _write(
    _LibraryViewPreferenceKeys keys,
    LibraryShelfViewPreferences preferences, {
    required LibraryShelfViewPreferences defaults,
  }) async {
    await _preferencesStore.write(
      keys.snapshot,
      _codec.encode(preferences, defaults: defaults),
    );
    await _preferencesStore.write(keys.migrationVersion, migrationVersion);
  }

  _LibraryViewPreferenceKeys _keysFor(LibraryModuleKey moduleKey) {
    return switch (moduleKey) {
      LibraryModuleKey.comic => const _LibraryViewPreferenceKeys(
        snapshot: PreferenceKeys.libraryShelfComicSnapshotV1,
        migrationVersion: PreferenceKeys.libraryShelfComicMigrationVersion,
      ),
      LibraryModuleKey.novel => const _LibraryViewPreferenceKeys(
        snapshot: PreferenceKeys.libraryShelfNovelSnapshotV1,
        migrationVersion: PreferenceKeys.libraryShelfNovelMigrationVersion,
      ),
      LibraryModuleKey.favorite => const _LibraryViewPreferenceKeys(
        snapshot: PreferenceKeys.libraryShelfFavoriteSnapshotV1,
        migrationVersion: PreferenceKeys.libraryShelfFavoriteMigrationVersion,
      ),
    };
  }
}

class _LibraryViewPreferenceKeys {
  const _LibraryViewPreferenceKeys({
    required this.snapshot,
    required this.migrationVersion,
  });

  final PreferenceKey<String> snapshot;
  final PreferenceKey<int> migrationVersion;
}
