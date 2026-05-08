import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('ComicLocalDb creates source tag columns for comic and novel works', () async {
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

  test('ComicLocalDb upgrades v9 database with source tag columns', () async {
    const dbName = 'comic_shelf_test_source_tag_columns_upgrade.db';
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
          await db.execute('''
            CREATE TABLE ${ComicLocalDb.worksTable} (
              work_id TEXT PRIMARY KEY,
              content_type TEXT NOT NULL,
              source_tid TEXT NOT NULL,
              source_fid TEXT NOT NULL,
              title TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
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

    expect(comicNames.contains('source_typeid'), isTrue);
    expect(comicNames.contains('source_tag_name'), isTrue);
    expect(workNames.contains('source_typeid'), isTrue);
    expect(workNames.contains('source_tag_name'), isTrue);

    await db.close();
    await deleteDatabase(dbName);
  });
}
