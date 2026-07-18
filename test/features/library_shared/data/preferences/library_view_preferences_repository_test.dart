import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/core/preferences/preference_keys.dart';
import 'package:y300/core/preferences/preferences_store.dart';
import 'package:y300/features/library_shared/data/preferences/library_view_preferences_legacy_source.dart';
import 'package:y300/features/library_shared/data/preferences/shared_preferences_library_view_preferences_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_view_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLegacySource legacySource;
  late SharedPreferencesLibraryViewPreferencesRepository repository;

  final defaults = LibraryShelfViewPreferences.defaults(
    moduleKey: LibraryModuleKey.comic,
    displayMode: LibraryDisplayMode.grid,
    sortOption: const LibraryShelfSortOption(
      field: LibraryShelfSortField.favoriteAddedAt,
      direction: LibrarySortDirection.asc,
    ),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    legacySource = _FakeLegacySource();
    repository = SharedPreferencesLibraryViewPreferencesRepository(
      preferencesStore: SharedPreferencesStore(),
      legacySource: legacySource,
    );
  });

  test(
    'first load migrates legacy display and records migration version',
    () async {
      legacySource.value = const LegacyLibraryDisplayPreferences(
        displayMode: LibraryDisplayMode.list,
        gridColumnCount: 6,
      );

      final loaded = await repository.load(defaults: defaults);
      final preferences = await SharedPreferences.getInstance();
      final snapshot =
          jsonDecode(
                preferences.getString(
                  PreferenceKeys.libraryShelfComicSnapshotV1.name,
                )!,
              )
              as Map<String, dynamic>;

      expect(loaded.displayMode, LibraryDisplayMode.list);
      expect(loaded.gridColumnCount, 6);
      expect(loaded.sortOption, isNotNull);
      expect(legacySource.callCount, 1);
      expect(snapshot['moduleKey'], 'comic');
      expect(
        preferences.getInt(
          PreferenceKeys.libraryShelfComicMigrationVersion.name,
        ),
        1,
      );
    },
  );

  test('new snapshot wins without reading stale legacy values', () async {
    final saved = defaults.copyWith(
      gridColumnCount: 4,
      filters: const LibraryFilterSet(unread: TriStateFilterValue.include),
      lastCategoryId: 'custom',
    );
    await repository.save(saved);
    legacySource.value = const LegacyLibraryDisplayPreferences(
      displayMode: LibraryDisplayMode.list,
      gridColumnCount: 9,
    );

    final loaded = await repository.load(defaults: defaults);

    expect(loaded, saved);
    expect(legacySource.callCount, 0);
  });

  test(
    'completed migration marker prevents stale fallback resurrection',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        PreferenceKeys.libraryShelfComicMigrationVersion.name: 1,
      });
      repository = SharedPreferencesLibraryViewPreferencesRepository(
        preferencesStore: SharedPreferencesStore(),
        legacySource: legacySource,
      );
      legacySource.value = const LegacyLibraryDisplayPreferences(
        displayMode: LibraryDisplayMode.list,
        gridColumnCount: 8,
      );

      final loaded = await repository.load(defaults: defaults);

      expect(loaded, defaults);
      expect(legacySource.callCount, 0);
    },
  );

  test('malformed new snapshot does not revive legacy storage', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PreferenceKeys.libraryShelfComicSnapshotV1.name: '{broken',
    });
    repository = SharedPreferencesLibraryViewPreferencesRepository(
      preferencesStore: SharedPreferencesStore(),
      legacySource: legacySource,
    );
    legacySource.value = const LegacyLibraryDisplayPreferences(
      displayMode: LibraryDisplayMode.list,
      gridColumnCount: 8,
    );

    final loaded = await repository.load(defaults: defaults);

    expect(loaded, defaults);
    expect(legacySource.callCount, 0);
  });
}

final class _FakeLegacySource implements LibraryViewPreferencesLegacySource {
  LegacyLibraryDisplayPreferences? value;
  int callCount = 0;

  @override
  Future<LegacyLibraryDisplayPreferences?> loadDisplayPreferences({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
    required int defaultGridColumnCount,
  }) async {
    callCount += 1;
    return value;
  }
}
