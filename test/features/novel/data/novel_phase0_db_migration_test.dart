import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('ComicLocalDb phase0 migration creates novel infrastructure tables', () async {
    await deleteDatabase(ComicLocalDb.dbName);
    final db = await ComicLocalDb.open();

    final tableRows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final tableNames = tableRows
        .map((row) => row['name'] as String)
        .toSet();

    expect(tableNames.contains(ComicLocalDb.worksTable), isTrue);
    expect(tableNames.contains(ComicLocalDb.workEpisodesTable), isTrue);
    expect(tableNames.contains(ComicLocalDb.novelEpisodeContentTable), isTrue);
    expect(tableNames.contains(ComicLocalDb.readerPreferencesTable), isTrue);

    final indexRows = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='index'");
    final indexNames = indexRows
        .map((row) => row['name'] as String)
        .toSet();

    expect(indexNames.contains('idx_work_type_updated'), isTrue);
    expect(indexNames.contains('idx_episode_work_order'), isTrue);
    expect(indexNames.contains('idx_episode_tid_pid'), isTrue);

    await db.close();
  });
}
