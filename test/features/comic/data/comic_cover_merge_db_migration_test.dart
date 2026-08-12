import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v39 to v40 keeps comics and creates cover merge journal', () async {
    const dbName = 'comic_cover_merge_v40_migration.db';
    await deleteDatabase(dbName);
    final oldDb = await databaseFactory.openDatabase(
      dbName,
      options: OpenDatabaseOptions(
        version: 39,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE ${ComicLocalDb.comicsTable} (
              comic_id TEXT PRIMARY KEY,
              source_tid TEXT NOT NULL,
              source_fid TEXT NOT NULL,
              title TEXT NOT NULL,
              cover_image_url TEXT,
              cover_revision INTEGER NOT NULL DEFAULT 0,
              custom_cover_revision INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.insert(ComicLocalDb.comicsTable, <String, Object?>{
            'comic_id': 'legacy-comic',
            'source_tid': '100',
            'source_fid': '30',
            'title': '升级前漫画',
            'cover_image_url': 'https://img.test/legacy.jpg',
            'cover_revision': 7,
            'custom_cover_revision': 2,
            'created_at': 1,
            'updated_at': 2,
          });
        },
      ),
    );
    await oldDb.close();

    final db = await ComicLocalDb.open(databaseName: dbName);
    addTearDown(() async {
      await db.close();
      await deleteDatabase(dbName);
    });

    expect(await db.getVersion(), 40);
    final legacy = (await db.query(
      ComicLocalDb.comicsTable,
      where: 'comic_id = ?',
      whereArgs: const <Object>['legacy-comic'],
    )).single;
    expect(legacy['cover_revision'], 7);
    expect(legacy['custom_cover_revision'], 2);

    final tables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    )).map((row) => row['name']).toSet();
    expect(
      tables,
      containsAll(<String>{
        ComicLocalDb.comicCoverMergeOperationsTable,
        ComicLocalDb.comicCoverMergeMembersTable,
        ComicLocalDb.comicCoverMergeAssetsTable,
      }),
    );
    final indexes = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    )).map((row) => row['name']).toSet();
    expect(indexes, contains('idx_comic_cover_merge_state'));
  });
}
