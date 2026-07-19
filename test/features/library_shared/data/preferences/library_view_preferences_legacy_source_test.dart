import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Database;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Database;
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/data/preferences/library_view_preferences_legacy_source.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const dbName = 'library_view_preferences_legacy_source_test.db';
  late Database db;
  late SqliteLibraryViewPreferencesLegacySource source;

  setUp(() async {
    await deleteDatabase(dbName);
    final dbFuture = ComicLocalDb.open(databaseName: dbName);
    db = await dbFuture;
    source = SqliteLibraryViewPreferencesLegacySource(() => dbFuture);
    await db.update(
      ComicLocalDb.settingsTable,
      <String, Object>{'value': '5'},
      where: 'key = ?',
      whereArgs: const <Object>['grid_column_count'],
    );
  });

  tearDown(() async {
    await db.close();
    await deleteDatabase(dbName);
  });

  test(
    'explicit shared three-column row wins over old comic setting',
    () async {
      await db.insert(
        ComicLocalDb.libraryDisplaySettingsTable,
        <String, Object>{
          'module_key': 'comic',
          'display_mode': 'list',
          'grid_columns': 3,
          'updated_at': 1,
        },
      );

      final loaded = await source.loadDisplayPreferences(
        moduleKey: LibraryModuleKey.comic,
        defaultDisplayMode: LibraryDisplayMode.grid,
        defaultGridColumnCount: 3,
      );

      expect(loaded?.displayMode, LibraryDisplayMode.list);
      expect(loaded?.gridColumnCount, 3);
    },
  );

  test(
    'old comic column setting is used only when shared row is absent',
    () async {
      final loaded = await source.loadDisplayPreferences(
        moduleKey: LibraryModuleKey.comic,
        defaultDisplayMode: LibraryDisplayMode.grid,
        defaultGridColumnCount: 3,
      );

      expect(loaded?.displayMode, LibraryDisplayMode.grid);
      expect(loaded?.gridColumnCount, 5);
    },
  );

  test('modules without either legacy source return null', () async {
    final loaded = await source.loadDisplayPreferences(
      moduleKey: LibraryModuleKey.novel,
      defaultDisplayMode: LibraryDisplayMode.list,
      defaultGridColumnCount: 3,
    );

    expect(loaded, isNull);
  });
}
