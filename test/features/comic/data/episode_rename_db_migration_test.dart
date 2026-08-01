import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/local_comic_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'v38 upgrade backfills existing episode titles as source names',
    () async {
      const dbName = 'comic_episode_rename_migration.db';
      await deleteDatabase(dbName);
      final oldDb = await databaseFactory.openDatabase(
        dbName,
        options: OpenDatabaseOptions(
          version: 37,
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
              publish_time_text TEXT,
              is_manual INTEGER NOT NULL DEFAULT 0,
              is_hidden INTEGER NOT NULL DEFAULT 0
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
              'episode_title': '第一话',
              'source_tid': '100',
              'source_url': 'https://bbs.yamibo.com/thread-100-1-1.html',
              'order_index': 0,
            });
            // 早期解析没拿到标题的存量行：回填后来源名仍然为空，清空重命名时得由
            // 展示层兜底，而不是被回填成空字符串。
            await db.insert(ComicLocalDb.episodesTable, <String, Object?>{
              'episode_id': 'legacy-comic:101',
              'comic_id': 'legacy-comic',
              'episode_title': null,
              'source_tid': '101',
              'source_url': 'https://bbs.yamibo.com/thread-101-1-1.html',
              'order_index': 1,
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
      expect(
        columns,
        containsAll(<String>['source_episode_title', 'custom_episode_title']),
      );

      // 存量标题必须落进来源列：漏了这步回填，用户清空一次重命名就再也拿不回
      // 原本的解析名，只会退成空标题。
      final repository = LocalComicRepository(Future<Database>.value(db));
      final episodes = await repository.getComicEpisodes(
        comicId: 'legacy-comic',
      );
      final titled = episodes.firstWhere(
        (item) => item.episodeId == 'legacy-comic:100',
      );
      expect(titled.episodeTitle, '第一话');
      expect(titled.sourceEpisodeTitle, '第一话');
      expect(titled.customEpisodeTitle, isNull);

      final untitled = episodes.firstWhere(
        (item) => item.episodeId == 'legacy-comic:101',
      );
      expect(untitled.sourceEpisodeTitle, isNull);
      expect(untitled.customEpisodeTitle, isNull);
    },
  );

  test(
    'v38 upgrade survives a legacy episodes table without a title column',
    () async {
      // 历史库不保证有 `episode_title`：这个库和小说共用，早期精简 schema 也真的
      // 存在。回填一旦无条件读那一列，整条升级链会在这里断掉、库打不开。
      const dbName = 'comic_episode_rename_partial_schema.db';
      await deleteDatabase(dbName);
      final oldDb = await databaseFactory.openDatabase(
        dbName,
        options: OpenDatabaseOptions(
          version: 37,
          onCreate: (db, version) async {
            await db.execute('''
            CREATE TABLE ${ComicLocalDb.episodesTable} (
              episode_id TEXT PRIMARY KEY,
              comic_id TEXT NOT NULL
            )
          ''');
          },
        ),
      );
      await oldDb.close();

      final db = await ComicLocalDb.open(databaseName: dbName);
      addTearDown(() async {
        await db.close();
        await deleteDatabase(dbName);
      });

      expect(await db.getVersion(), ComicLocalDb.dbVersion);
      final columns = (await db.rawQuery(
        'PRAGMA table_info(${ComicLocalDb.episodesTable})',
      )).map((row) => row['name'] as String).toSet();
      expect(
        columns,
        containsAll(<String>['source_episode_title', 'custom_episode_title']),
      );
    },
  );
}
