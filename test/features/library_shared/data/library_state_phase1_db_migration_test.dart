import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/persistence/app_database.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('AppDatabase phase1 migration creates library state tables', () async {
    const dbName = 'comic_shelf_test_phase1_state.db';
    await deleteDatabase(dbName);
    final db = await AppDatabase.open(databaseName: dbName);

    final tableRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    );
    final tableNames = tableRows.map((row) => row['name'] as String).toSet();

    expect(tableNames.contains(AppDatabase.libraryWorkStateTable), isTrue);
    expect(tableNames.contains(AppDatabase.libraryEpisodeStateTable), isTrue);
    expect(tableNames.contains(AppDatabase.libraryTagsTable), isTrue);
    expect(tableNames.contains(AppDatabase.libraryWorkTagsTable), isTrue);
    expect(
      tableNames.contains(AppDatabase.libraryDisplaySettingsTable),
      isTrue,
    );

    final indexRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index'",
    );
    final indexNames = indexRows.map((row) => row['name'] as String).toSet();
    expect(indexNames.contains('idx_library_episode_state_work_read'), isTrue);
    expect(
      indexNames.contains('idx_library_episode_state_work_downloaded'),
      isTrue,
    );
    expect(indexNames.contains('idx_library_work_tags_work'), isTrue);
    expect(
      indexNames.contains('idx_library_episode_state_work_bookmarked'),
      isTrue,
    );
    expect(indexNames.contains('idx_work_episodes_type_work_order'), isTrue);
    expect(indexNames.contains('idx_episodes_comic_order'), isTrue);
    expect(indexNames.contains('idx_shelf_items_comic'), isTrue);
    expect(indexNames.contains('idx_novel_shelf_items_novel'), isTrue);
    expect(
      indexNames.contains('idx_favorite_threads_active_kind_order'),
      isTrue,
    );

    await db.close();
    await deleteDatabase(dbName);
  });
}
