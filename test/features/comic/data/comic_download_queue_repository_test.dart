import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/local_comic_download_queue_repository.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('LocalComicDownloadQueueRepository', () {
    test('latest schema creates the persistent queue and FIFO index', () async {
      const dbName = 'comic_download_queue_schema_test.db';
      await deleteDatabase(dbName);
      final db = await ComicLocalDb.open(databaseName: dbName);
      addTearDown(() async {
        await db.close();
        await deleteDatabase(dbName);
      });

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );

      expect(
        tables.map((row) => row['name']),
        contains(ComicLocalDb.comicDownloadQueueTable),
      );
      expect(
        indexes.map((row) => row['name']),
        contains('idx_comic_download_queue_status'),
      );
    });

    test('upgrades a version 35 database with the queue table', () async {
      const dbName = 'comic_download_queue_migration_test.db';
      await deleteDatabase(dbName);
      final legacy = await openDatabase(
        dbName,
        version: 35,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE ${ComicLocalDb.comicsTable} (
              comic_id TEXT PRIMARY KEY
            )
          ''');
          await db.execute('''
            CREATE TABLE ${ComicLocalDb.episodesTable} (
              episode_id TEXT PRIMARY KEY,
              comic_id TEXT NOT NULL
            )
          ''');
        },
      );
      await legacy.close();

      final upgraded = await ComicLocalDb.open(databaseName: dbName);
      addTearDown(() async {
        await upgraded.close();
        await deleteDatabase(dbName);
      });
      final tables = await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );

      expect(await upgraded.getVersion(), ComicLocalDb.dbVersion);
      expect(
        tables.map((row) => row['name']),
        contains(ComicLocalDb.comicDownloadQueueTable),
      );
    });

    test('deduplicates active entries and requeues a failed entry', () async {
      const dbName = 'comic_download_queue_dedupe_test.db';
      await deleteDatabase(dbName);
      final dbFuture = ComicLocalDb.open(databaseName: dbName);
      final db = await dbFuture;
      addTearDown(() async {
        await db.close();
        await deleteDatabase(dbName);
      });
      await _seedEpisode(db, comicId: 'comic:1', episodeId: 'comic:1:10');
      final repository = LocalComicDownloadQueueRepository.lazy(() => dbFuture);
      final now = DateTime(2026, 7, 22, 10);
      const original = ComicDownloadTarget(
        comicId: 'comic:1',
        episodeId: 'comic:1:10',
        comicTitle: '作品',
        episodeTitle: '第 1 话',
      );

      final first = await repository.enqueueTargets(<ComicDownloadTarget>[
        original,
        original,
      ], now: now);
      final duplicate = await repository
          .enqueueTargets(const <ComicDownloadTarget>[
            ComicDownloadTarget(
              comicId: 'comic:1',
              episodeId: 'comic:1:10',
              comicTitle: '新作品名',
              episodeTitle: '新章节名',
            ),
          ], now: now.add(const Duration(seconds: 1)));
      final entry = (await repository.loadVisibleEntries()).single;
      await repository.updateProgress(
        id: entry.id,
        completedImages: 1,
        totalImages: 3,
        now: now.add(const Duration(seconds: 2)),
      );
      await repository.markFailed(
        id: entry.id,
        error: 'network failed',
        now: now.add(const Duration(seconds: 3)),
      );
      final retried = await repository
          .enqueueTargets(const <ComicDownloadTarget>[
            ComicDownloadTarget(
              comicId: 'comic:1',
              episodeId: 'comic:1:10',
              comicTitle: '新作品名',
              episodeTitle: '新章节名',
            ),
          ], now: now.add(const Duration(seconds: 4)));
      final visible = (await repository.loadVisibleEntries()).single;

      expect(first.enqueuedCount, 1);
      expect(first.deduplicatedCount, 1);
      expect(duplicate.enqueuedCount, 0);
      expect(duplicate.deduplicatedCount, 1);
      expect(retried.enqueuedCount, 1);
      expect(visible.id, entry.id);
      expect(visible.status, ComicDownloadQueueStatus.pending);
      expect(visible.comicTitle, '新作品名');
      expect(visible.totalImages, isNull);
      expect(visible.lastError, isNull);
    });

    test('claims FIFO and recovers interrupted states on startup', () async {
      const dbName = 'comic_download_queue_recovery_test.db';
      await deleteDatabase(dbName);
      final dbFuture = ComicLocalDb.open(databaseName: dbName);
      final db = await dbFuture;
      addTearDown(() async {
        await db.close();
        await deleteDatabase(dbName);
      });
      await _seedEpisode(db, comicId: 'comic:1', episodeId: 'comic:1:10');
      await _seedEpisode(db, comicId: 'comic:1', episodeId: 'comic:1:20');
      await _seedEpisode(db, comicId: 'comic:1', episodeId: 'comic:1:30');
      final repository = LocalComicDownloadQueueRepository.lazy(() => dbFuture);
      final now = DateTime(2026, 7, 22, 11);
      await repository.enqueueTargets(<ComicDownloadTarget>[
        _target('comic:1:10'),
        _target('comic:1:20'),
        _target('comic:1:30'),
      ], now: now);

      final first = await repository.claimNext(now: now);
      final second = await repository.claimNext(
        now: now.add(const Duration(seconds: 1)),
      );
      await repository.requestCancel(
        id: second!.id,
        now: now.add(const Duration(seconds: 2)),
      );
      final third = await repository.claimNext(
        now: now.add(const Duration(seconds: 3)),
      );
      await repository.markFailed(
        id: third!.id,
        error: 'failed',
        now: now.add(const Duration(seconds: 4)),
      );

      await repository.recoverInterrupted(
        now: now.add(const Duration(minutes: 1)),
      );
      final visible = await repository.loadVisibleEntries();

      expect(first?.episodeId, 'comic:1:10');
      expect(second.episodeId, 'comic:1:20');
      expect(third.episodeId, 'comic:1:30');
      expect(visible.map((entry) => entry.episodeId), <String>[
        'comic:1:10',
        'comic:1:30',
      ]);
      expect(visible.first.status, ComicDownloadQueueStatus.pending);
      expect(visible.last.status, ComicDownloadQueueStatus.failed);
    });
  });
}

ComicDownloadTarget _target(String episodeId) {
  return ComicDownloadTarget(
    comicId: 'comic:1',
    episodeId: episodeId,
    comicTitle: '作品',
    episodeTitle: episodeId,
  );
}

Future<void> _seedEpisode(
  Database db, {
  required String comicId,
  required String episodeId,
}) async {
  final now = DateTime(2026, 7, 22).millisecondsSinceEpoch;
  await db.insert(ComicLocalDb.comicsTable, <String, Object?>{
    'comic_id': comicId,
    'source_tid': comicId,
    'source_fid': '30',
    'title': comicId,
    'created_at': now,
    'updated_at': now,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  await db.insert(ComicLocalDb.episodesTable, <String, Object?>{
    'episode_id': episodeId,
    'comic_id': comicId,
    'source_tid': episodeId,
    'source_url': 'thread-$episodeId.html',
    'order_index': int.tryParse(episodeId.split(':').last) ?? 0,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
}
