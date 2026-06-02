import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local_comic_search_refresh_queue_repository.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('LocalComicSearchRefreshQueueRepository', () {
    test('latest schema creates search refresh queue table and indexes', () async {
      const dbName = 'comic_search_refresh_queue_schema_test.db';
      await deleteDatabase(dbName);

      final db = await ComicLocalDb.open(databaseName: dbName);
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
      final tableNames = tables.map((row) => row['name']).toSet();
      expect(tableNames.contains(ComicLocalDb.comicSearchRefreshQueueTable), isTrue);

      final indexes = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'index'");
      final indexNames = indexes.map((row) => row['name']).toSet();
      expect(indexNames.contains('idx_comic_search_refresh_queue_active'), isTrue);
      expect(indexNames.contains('idx_comic_search_refresh_queue_comic'), isTrue);

      await db.close();
      await deleteDatabase(dbName);
    });

    test('deduplicates active task for same comic', () async {
      const dbName = 'comic_search_refresh_queue_dedupe_test.db';
      await deleteDatabase(dbName);
      final dbFuture = ComicLocalDb.open(databaseName: dbName);
      final repository = LocalComicSearchRefreshQueueRepository(
        dbFuture,
      );
      final now = DateTime(2026, 5, 16, 12, 0, 0);

      final first = await repository.enqueue(
        _draft(title: '旧标题'),
        now: now,
      );
      final second = await repository.enqueue(
        _draft(title: '新标题'),
        now: now.add(const Duration(seconds: 1)),
      );
      final active = await repository.loadActiveEntries();

      expect(first.deduplicated, isFalse);
      expect(second.deduplicated, isTrue);
      expect(active, hasLength(1));
      expect(active.single.id, first.entry.id);
      expect(active.single.title, '新标题');

      final db = await dbFuture;
      await db.close();
      await deleteDatabase(dbName);
    });

    test('start recovery can reset running task to pending', () async {
      const dbName = 'comic_search_refresh_queue_recover_test.db';
      await deleteDatabase(dbName);
      final dbFuture = ComicLocalDb.open(databaseName: dbName);
      final repository = LocalComicSearchRefreshQueueRepository(
        dbFuture,
      );
      final now = DateTime(2026, 5, 16, 12, 0, 0);

      await repository.enqueue(_draft(), now: now);
      final running = await repository.claimNextPending(now: now);
      expect(running?.status, ComicSearchRefreshQueueStatus.running);

      await repository.resetRunningToPending(
        now: now.add(const Duration(seconds: 1)),
      );
      final active = await repository.loadActiveEntries();

      expect(active, hasLength(1));
      expect(active.single.status, ComicSearchRefreshQueueStatus.pending);

      final db = await dbFuture;
      await db.close();
      await deleteDatabase(dbName);
    });

    test('deleteByComicId removes all queue rows for target comic only', () async {
      const dbName = 'comic_search_refresh_queue_delete_test.db';
      await deleteDatabase(dbName);
      final dbFuture = ComicLocalDb.open(databaseName: dbName);
      final repository = LocalComicSearchRefreshQueueRepository(
        dbFuture,
      );
      final now = DateTime(2026, 5, 16, 12, 0, 0);

      final target = await repository.enqueue(
        _draft(title: '目标漫画'),
        now: now,
      );
      final other = await repository.enqueue(
        ComicSearchRefreshQueueDraft(
          title: '其他漫画',
          origin: ComicSearchRefreshOrigin.favoriteSync,
          request: const ComicEpisodeRefreshRequest(
            comicId: 'comic:2',
            sourceTid: '200',
            displayTitle: '其他漫画',
            sourceTitle: '其他漫画来源',
          ),
        ),
        now: now.add(const Duration(seconds: 1)),
      );
      await repository.markCompleted(
        id: target.entry.id,
        now: now.add(const Duration(seconds: 2)),
      );

      await repository.deleteByComicId('comic:1');

      final db = await dbFuture;
      expect(
        await db.query(
          ComicLocalDb.comicSearchRefreshQueueTable,
          where: 'comic_id = ?',
          whereArgs: const <Object>['comic:1'],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          ComicLocalDb.comicSearchRefreshQueueTable,
          where: 'comic_id = ?',
          whereArgs: const <Object>['comic:2'],
        ),
        hasLength(1),
      );
      expect(other.entry.comicId, 'comic:2');

      await db.close();
      await deleteDatabase(dbName);
    });
  });
}

ComicSearchRefreshQueueDraft _draft({String title = '测试漫画'}) {
  return ComicSearchRefreshQueueDraft(
    title: title,
    origin: ComicSearchRefreshOrigin.favoriteSync,
    request: const ComicEpisodeRefreshRequest(
      comicId: 'comic:1',
      sourceTid: '100',
      displayTitle: '测试漫画',
      sourceTitle: '测试漫画 来源',
    ),
  );
}
