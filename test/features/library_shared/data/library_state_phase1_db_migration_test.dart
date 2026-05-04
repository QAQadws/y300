import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('ComicLocalDb phase1 migration creates library state tables', () async {
    const dbName = 'comic_shelf_test_phase1_state.db';
    await deleteDatabase(dbName);
    final db = await ComicLocalDb.open(databaseName: dbName);

    final tableRows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final tableNames = tableRows.map((row) => row['name'] as String).toSet();

    expect(tableNames.contains(ComicLocalDb.libraryWorkStateTable), isTrue);
    expect(tableNames.contains(ComicLocalDb.libraryEpisodeStateTable), isTrue);
    expect(tableNames.contains(ComicLocalDb.libraryTagsTable), isTrue);
    expect(tableNames.contains(ComicLocalDb.libraryWorkTagsTable), isTrue);
    expect(tableNames.contains(ComicLocalDb.libraryDisplaySettingsTable), isTrue);

    final indexRows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='index'");
    final indexNames = indexRows.map((row) => row['name'] as String).toSet();
    expect(indexNames.contains('idx_library_episode_state_work_read'), isTrue);
    expect(indexNames.contains('idx_library_episode_state_work_downloaded'), isTrue);
    expect(indexNames.contains('idx_library_work_tags_work'), isTrue);

    await db.close();
    await deleteDatabase(dbName);
  });
}

