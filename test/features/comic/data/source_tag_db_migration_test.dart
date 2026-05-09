import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('ComicLocalDb latest schema includes source tag columns', () async {
    const dbName = 'comic_shelf_test_source_tag_columns.db';
    await deleteDatabase(dbName);
    final db = await ComicLocalDb.open(databaseName: dbName);

    final comicColumns = await db.rawQuery(
      'PRAGMA table_info(${ComicLocalDb.comicsTable})',
    );
    final workColumns = await db.rawQuery(
      'PRAGMA table_info(${ComicLocalDb.worksTable})',
    );
    final comicNames = comicColumns.map((row) => row['name'] as String).toSet();
    final workNames = workColumns.map((row) => row['name'] as String).toSet();

    expect(comicNames.contains('source_typeid'), isTrue);
    expect(comicNames.contains('source_tag_name'), isTrue);
    expect(workNames.contains('source_typeid'), isTrue);
    expect(workNames.contains('source_tag_name'), isTrue);

    await db.close();
    await deleteDatabase(dbName);
  });

  test('ComicLocalDb rebuilds outdated development database to latest schema', () async {
    const dbName = 'comic_shelf_test_source_tag_columns_rebuild.db';
    await deleteDatabase(dbName);
    final oldDb = await databaseFactory.openDatabase(
      dbName,
      options: OpenDatabaseOptions(
        version: 9,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE ${ComicLocalDb.comicsTable} (
              comic_id TEXT PRIMARY KEY,
              source_tid TEXT NOT NULL,
              source_fid TEXT NOT NULL,
              title TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.insert(ComicLocalDb.comicsTable, <String, Object?>{
            'comic_id': 'old-comic',
            'source_tid': '1',
            'source_fid': '30',
            'title': '旧开发期数据',
            'created_at': 1,
            'updated_at': 1,
          });
        },
      ),
    );
    await oldDb.close();

    final db = await ComicLocalDb.open(databaseName: dbName);
    final comicColumns = await db.rawQuery(
      'PRAGMA table_info(${ComicLocalDb.comicsTable})',
    );
    final workColumns = await db.rawQuery(
      'PRAGMA table_info(${ComicLocalDb.worksTable})',
    );
    final comicNames = comicColumns.map((row) => row['name'] as String).toSet();
    final workNames = workColumns.map((row) => row['name'] as String).toSet();
    final oldRows = await db.query(
      ComicLocalDb.comicsTable,
      where: 'comic_id = ?',
      whereArgs: <Object>['old-comic'],
    );

    expect(comicNames.contains('source_typeid'), isTrue);
    expect(comicNames.contains('source_tag_name'), isTrue);
    expect(workNames.contains('source_typeid'), isTrue);
    expect(workNames.contains('source_tag_name'), isTrue);
    expect(oldRows, isEmpty);

    await db.close();
    await deleteDatabase(dbName);
  });
}
