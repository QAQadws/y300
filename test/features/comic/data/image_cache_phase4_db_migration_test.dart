import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('ComicLocalDb latest schema includes image cache table and local cover columns', () async {
    const dbName = 'comic_shelf_test_image_cache_phase4.db';
    await deleteDatabase(dbName);
    final db = await ComicLocalDb.open(databaseName: dbName);

    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
    final tableNames = tables.map((row) => row['name']).toSet();
    expect(tableNames.contains(ComicLocalDb.cachedImagesTable), isTrue);

    final comicColumns = await db.rawQuery('PRAGMA table_info(${ComicLocalDb.comicsTable})');
    final workColumns = await db.rawQuery('PRAGMA table_info(${ComicLocalDb.worksTable})');
    final imageColumns = await db.rawQuery('PRAGMA table_info(${ComicLocalDb.episodeImagesTable})');
    final comicNames = comicColumns.map((row) => row['name']).toSet();
    final workNames = workColumns.map((row) => row['name']).toSet();
    final imageNames = imageColumns.map((row) => row['name']).toSet();

    expect(comicNames.contains('cover_local_path'), isTrue);
    expect(comicNames.contains('custom_cover_local_path'), isTrue);
    expect(comicNames.contains('source_title'), isTrue);
    expect(comicNames.contains('custom_title'), isTrue);
    expect(comicNames.contains('source_author'), isTrue);
    expect(comicNames.contains('custom_author'), isTrue);
    expect(comicNames.contains('source_translation_group'), isTrue);
    expect(comicNames.contains('custom_translation_group'), isTrue);
    expect(comicNames.contains('custom_search_title'), isTrue);
    expect(comicNames.contains('custom_cover_source_episode_id'), isTrue);
    expect(comicNames.contains('custom_cover_source_image_index'), isTrue);
    expect(comicNames.contains('custom_cover_source_image_url'), isTrue);
    expect(workNames.contains('cover_local_path'), isTrue);
    expect(workNames.contains('custom_cover_local_path'), isTrue);
    expect(imageNames.contains('stable_cache_key'), isTrue);
    expect(imageNames.contains('last_source_url'), isTrue);
    expect(imageNames.contains('local_path'), isTrue);
    expect(imageNames.contains('protected'), isTrue);

    await db.close();
    await deleteDatabase(dbName);
  });

  test('ComicLocalDb rebuilds outdated image cache schema instead of preserving legacy rows', () async {
    const dbName = 'comic_shelf_test_image_cache_phase4_rebuild.db';
    await deleteDatabase(dbName);
    final oldDb = await databaseFactory.openDatabase(
      dbName,
      options: OpenDatabaseOptions(
        version: 11,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE ${ComicLocalDb.episodeImagesTable} (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              episode_id TEXT NOT NULL,
              image_url TEXT NOT NULL,
              image_index INTEGER NOT NULL,
              cache_local_path TEXT,
              cache_status TEXT NOT NULL DEFAULT 'none'
            )
          ''');
          await db.insert(ComicLocalDb.episodeImagesTable, <String, Object?>{
            'episode_id': 'old-episode',
            'image_url': 'https://example.invalid/old.jpg',
            'image_index': 0,
            'cache_local_path': '/tmp/old.jpg',
            'cache_status': 'done',
          });
        },
      ),
    );
    await oldDb.close();

    final db = await ComicLocalDb.open(databaseName: dbName);
    final imageColumns = await db.rawQuery('PRAGMA table_info(${ComicLocalDb.episodeImagesTable})');
    final imageNames = imageColumns.map((row) => row['name']).toSet();
    final oldRows = await db.query(
      ComicLocalDb.episodeImagesTable,
      where: 'episode_id = ?',
      whereArgs: <Object>['old-episode'],
    );

    expect(imageNames.contains('stable_cache_key'), isTrue);
    expect(imageNames.contains('last_source_url'), isTrue);
    expect(imageNames.contains('local_path'), isTrue);
    expect(imageNames.contains('bytes'), isTrue);
    expect(imageNames.contains('mime_type'), isTrue);
    expect(imageNames.contains('last_accessed_at'), isTrue);
    expect(imageNames.contains('protected'), isTrue);
    expect(oldRows, isEmpty);

    await db.close();
    await deleteDatabase(dbName);
  });
}
