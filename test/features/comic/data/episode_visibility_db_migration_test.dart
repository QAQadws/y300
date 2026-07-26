import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/local_comic_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('v37 upgrade keeps existing episodes visible as parsed chapters', () async {
    const dbName = 'comic_episode_visibility_migration.db';
    await deleteDatabase(dbName);
    final oldDb = await databaseFactory.openDatabase(
      dbName,
      options: OpenDatabaseOptions(
        version: 36,
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
            CREATE TABLE ${ComicLocalDb.episodesTable} (
              episode_id TEXT PRIMARY KEY,
              comic_id TEXT NOT NULL,
              episode_title TEXT,
              source_tid TEXT NOT NULL,
              source_url TEXT NOT NULL,
              order_index INTEGER NOT NULL,
              publish_time_text TEXT
            )
          ''');
          await db.insert(ComicLocalDb.comicsTable, <String, Object?>{
            'comic_id': 'legacy-comic',
            'source_tid': '100',
            'source_fid': '30',
            'title': '升级前漫画',
            'created_at': 1,
            'updated_at': 1,
          });
          await db.insert(ComicLocalDb.episodesTable, <String, Object?>{
            'episode_id': 'legacy-comic:100',
            'comic_id': 'legacy-comic',
            'episode_title': '升级前章节',
            'source_tid': '100',
            'source_url': 'https://bbs.yamibo.com/thread-100-1-1.html',
            'order_index': 0,
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

    final columns = (await db.rawQuery(
      'PRAGMA table_info(${ComicLocalDb.episodesTable})',
    )).map((row) => row['name'] as String).toSet();
    expect(columns, containsAll(<String>['is_manual', 'is_hidden']));

    // 存量章节必须落在“解析且可见”这一侧：默认值写错会让老用户整部漫画消失，
    // 或者把不可移除的解析章节显示成可移除。
    final repository = LocalComicRepository(Future<Database>.value(db));
    final visible = await repository.getComicEpisodes(comicId: 'legacy-comic');
    expect(visible.single.episodeId, 'legacy-comic:100');
    expect(visible.single.isHidden, isFalse);
    expect(visible.single.isManual, isFalse);
  });
}
