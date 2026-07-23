import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_chapter_sync_repository.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_source_metadata_repository.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_source_state_repository.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory temp;
  late String dbPath;
  late Database db;
  late SqfliteNovelChapterSyncRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('y300-novel-chapter-sync-');
    dbPath = p.join(temp.path, 'chapter-sync.db');
    db = await ComicLocalDb.open(databaseName: dbPath);
    await SqfliteNovelSourceMetadataRepository(
      Future<Database>.value(db),
    ).saveFromFavoriteDetail(
      seed: const NovelSourceSeed(fid: '55', tid: '521519'),
      metadata: _metadata(),
      favoriteAddedAt: DateTime(2026, 7, 1),
    );
    repository = SqfliteNovelChapterSyncRepository(Future<Database>.value(db));
  });

  tearDown(() async {
    await db.close();
    await deleteDatabase(dbPath);
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('initial promotion preserves matching episode bookmarks', () async {
    await _insertOfficialEpisode(db, episodeId: 'novel:55:521519:2');
    await _insertOfficialEpisode(db, episodeId: 'novel:55:521519:stale');
    await db.insert(ComicLocalDb.readerBookmarksTable, <String, Object?>{
      'bookmark_id': 'bookmark-1',
      'novel_id': 'novel:55:521519',
      'episode_id': 'novel:55:521519:2',
      'node_id': null,
      'text_offset': 0,
      'page_index': 0,
      'scroll_offset': 0.0,
      'progress_percent': 0.1,
      'title': '保留书签',
      'snippet': '摘要',
      'note': null,
      'created_at': 1,
      'updated_at': 1,
    });

    await repository.beginRun(
      runId: 'run-1',
      novelId: 'novel:55:521519',
      mode: NovelChapterSyncMode.initialFull,
    );
    await repository.stageEpisodes(
      runId: 'run-1',
      episodes: <NovelEpisodeDraft>[
        _draft(pid: '2', title: '更新后的第一章', orderIndex: 0),
        _draft(pid: '3', title: '新增第二章', orderIndex: 1),
      ],
    );
    final completedAt = DateTime(2026, 7, 13, 12);
    final result = await repository.promote(
      runId: 'run-1',
      request: _request(),
      checkpoint: NovelChapterSyncCheckpoint(
        novelId: 'novel:55:521519',
        publisherId: '406769',
        lastCompletedAuthorPage: 3,
        lastSeenPid: '3',
        completedAt: completedAt,
      ),
      fetchedPages: 3,
    );

    final episodes = await db.query(
      ComicLocalDb.workEpisodesTable,
      where: 'work_id = ?',
      whereArgs: const <Object?>['novel:55:521519'],
      orderBy: 'order_index ASC',
    );
    expect(episodes.map((row) => row['episode_id']), <String>[
      'novel:55:521519:2',
      'novel:55:521519:3',
    ]);
    expect(episodes.first['episode_title'], '更新后的第一章');
    expect(
      await db.query(
        ComicLocalDb.readerBookmarksTable,
        where: 'bookmark_id = ?',
        whereArgs: const <Object?>['bookmark-1'],
      ),
      hasLength(1),
      reason: 'DO UPDATE must not cascade-delete the existing bookmark.',
    );
    expect(result.insertedCount, 1);
    expect(result.updatedCount, 1);
    expect(result.totalCount, 2);
    expect(await db.query(ComicLocalDb.novelEpisodeSyncStagingTable), isEmpty);
    final sourceState = await SqfliteNovelSourceStateRepository(
      Future<Database>.value(db),
    ).getSourceState(novelId: 'novel:55:521519');
    expect(sourceState?.hydrationState, NovelChapterHydrationState.ready);
    expect(sourceState?.checkpoint?.lastCompletedAuthorPage, 3);
    expect(sourceState?.chaptersHydratedAt, completedAt);
  });

  test('failed promotion rolls back all official episode changes', () async {
    await _insertOfficialEpisode(db, episodeId: 'novel:55:521519:old');
    await repository.beginRun(
      runId: 'run-failure',
      novelId: 'novel:55:521519',
      mode: NovelChapterSyncMode.initialFull,
    );
    await repository.stageEpisodes(
      runId: 'run-failure',
      episodes: <NovelEpisodeDraft>[
        _draft(pid: 'new', title: '不应暴露', orderIndex: 0),
      ],
    );
    await db.execute('''
      CREATE TRIGGER fail_novel_chapter_promote
      BEFORE UPDATE ON ${ComicLocalDb.novelSourceStateTable}
      WHEN NEW.hydration_state = 'ready'
      BEGIN
        SELECT RAISE(ABORT, 'forced promotion failure');
      END
    ''');

    await expectLater(
      repository.promote(
        runId: 'run-failure',
        request: _request(),
        checkpoint: NovelChapterSyncCheckpoint(
          novelId: 'novel:55:521519',
          publisherId: '406769',
          lastCompletedAuthorPage: 1,
          lastSeenPid: 'new',
          completedAt: DateTime(2026, 7, 13),
        ),
        fetchedPages: 1,
      ),
      throwsA(anything),
    );

    final officialRows = await db.query(
      ComicLocalDb.workEpisodesTable,
      where: 'work_id = ?',
      whereArgs: const <Object?>['novel:55:521519'],
    );
    expect(officialRows.map((row) => row['episode_id']), <String>[
      'novel:55:521519:old',
    ]);
    expect(
      await db.query(
        ComicLocalDb.novelEpisodeSyncStagingTable,
        where: 'run_id = ?',
        whereArgs: const <Object?>['run-failure'],
      ),
      hasLength(1),
    );
    await repository.discardRun('run-failure');
    expect(await db.query(ComicLocalDb.novelEpisodeSyncStagingTable), isEmpty);
  });

  test(
    'incremental promotion preserves order and user state while appending new PID',
    () async {
      await _insertOfficialEpisode(
        db,
        episodeId: 'novel:55:521519:1',
        orderIndex: 0,
      );
      await _insertOfficialEpisode(
        db,
        episodeId: 'novel:55:521519:2',
        orderIndex: 1,
      );
      await _insertOfficialEpisode(
        db,
        episodeId: 'novel:55:521519:absent',
        orderIndex: 2,
      );
      await db.insert(ComicLocalDb.libraryEpisodeStateTable, <String, Object?>{
        'content_type': 'novel',
        'episode_id': 'novel:55:521519:2',
        'work_id': 'novel:55:521519',
        'is_read': 1,
        'is_downloaded': 1,
        'is_bookmarked': 1,
        'read_at': 10,
        'downloaded_at': 11,
      });
      final previousCheckpoint = NovelChapterSyncCheckpoint(
        novelId: 'novel:55:521519',
        publisherId: '406769',
        lastCompletedAuthorPage: 3,
        lastSeenPid: '2',
        completedAt: DateTime(2026, 7, 13),
      );
      await SqfliteNovelSourceStateRepository(
        Future<Database>.value(db),
      ).saveCheckpoint(previousCheckpoint);

      await repository.beginRun(
        runId: 'run-incremental',
        novelId: 'novel:55:521519',
        mode: NovelChapterSyncMode.incremental,
      );
      await repository.stageEpisodes(
        runId: 'run-incremental',
        episodes: <NovelEpisodeDraft>[
          _draft(pid: '2', title: '重叠页修订标题', orderIndex: 0, sourcePage: 3),
          _draft(pid: '4', title: '页尾新增章节', orderIndex: 1, sourcePage: 4),
        ],
      );
      final nextCheckpoint = NovelChapterSyncCheckpoint(
        novelId: 'novel:55:521519',
        publisherId: '406769',
        lastCompletedAuthorPage: 4,
        lastSeenPid: '4',
        completedAt: DateTime(2026, 7, 14),
      );
      final result = await repository.promote(
        runId: 'run-incremental',
        request: _incrementalRequest(previousCheckpoint),
        checkpoint: nextCheckpoint,
        fetchedPages: 2,
      );

      final episodes = await db.query(
        ComicLocalDb.workEpisodesTable,
        where: 'work_id = ?',
        whereArgs: const <Object?>['novel:55:521519'],
        orderBy: 'order_index ASC',
      );
      expect(episodes.map((row) => row['episode_id']), <String>[
        'novel:55:521519:1',
        'novel:55:521519:2',
        'novel:55:521519:absent',
        'novel:55:521519:4',
      ]);
      expect(episodes[1]['order_index'], 1);
      expect(episodes[1]['episode_title'], '重叠页修订标题');
      expect(episodes.last['order_index'], 3);
      final content = await db.query(
        ComicLocalDb.novelEpisodeContentTable,
        where: 'episode_id = ?',
        whereArgs: const <Object?>['novel:55:521519:2'],
      );
      expect(content.single['plain_text'], '重叠页修订标题 正文');
      final userState = await db.query(
        ComicLocalDb.libraryEpisodeStateTable,
        where: 'content_type = ? AND episode_id = ?',
        whereArgs: const <Object?>['novel', 'novel:55:521519:2'],
      );
      expect(userState.single['is_read'], 1);
      expect(userState.single['is_downloaded'], 1);
      expect(userState.single['is_bookmarked'], 1);
      expect(result.insertedCount, 1);
      expect(result.updatedCount, 1);
      expect(result.totalCount, 4);
      final sourceState = await SqfliteNovelSourceStateRepository(
        Future<Database>.value(db),
      ).getSourceState(novelId: 'novel:55:521519');
      expect(sourceState?.hydrationState, NovelChapterHydrationState.ready);
      expect(sourceState?.checkpoint?.lastCompletedAuthorPage, 4);
      expect(sourceState?.checkpoint?.lastSeenPid, '4');
    },
  );
}

NovelChapterSyncRequest _request() {
  return const NovelChapterSyncRequest(
    novelId: 'novel:55:521519',
    tid: '521519',
    publisherId: '406769',
    mode: NovelChapterSyncMode.initialFull,
  );
}

NovelChapterSyncRequest _incrementalRequest(
  NovelChapterSyncCheckpoint checkpoint,
) {
  return NovelChapterSyncRequest(
    novelId: 'novel:55:521519',
    tid: '521519',
    publisherId: '406769',
    mode: NovelChapterSyncMode.incremental,
    checkpoint: checkpoint,
  );
}

NovelEpisodeDraft _draft({
  required String pid,
  required String title,
  required int orderIndex,
  int sourcePage = 1,
}) {
  return NovelEpisodeDraft(
    episodeId: 'novel:55:521519:$pid',
    novelId: 'novel:55:521519',
    sourceTid: '521519',
    sourcePid: pid,
    sourcePage: sourcePage,
    episodeTitle: title,
    orderIndex: orderIndex,
    datelineText: '2026-07-13',
    rawHtml: '<p>$title 正文</p>',
    plainText: '$title 正文',
    paragraphs: <String>['$title 正文'],
  );
}

Future<void> _insertOfficialEpisode(
  Database db, {
  required String episodeId,
  int orderIndex = 0,
}) async {
  await db.insert(ComicLocalDb.workEpisodesTable, <String, Object?>{
    'episode_id': episodeId,
    'work_id': 'novel:55:521519',
    'content_type': 'novel',
    'source_tid': '521519',
    'source_pid': episodeId.split(':').last,
    'source_page': 1,
    'episode_title': '旧章节',
    'order_index': orderIndex,
    'dateline_text': '2026-07-12',
  });
  await db.insert(ComicLocalDb.novelEpisodeContentTable, <String, Object?>{
    'episode_id': episodeId,
    'raw_html': '<p>旧正文</p>',
    'plain_text': '旧正文',
    'paragraph_json': '["旧正文"]',
    'updated_at': 1,
  });
}

NovelSourceMetadata _metadata() {
  return NovelSourceMetadata(
    novelId: 'novel:55:521519',
    tid: '521519',
    fid: '55',
    subject: '测试小说',
    publisherName: 'INCSKY16',
    publisherId: '406769',
    firstPostPid: '1',
    catalogEntries: const <NovelSourceCatalogEntry>[],
    sourceIntro: '来源简介',
    coverImageUrl: null,
    sourceApiVersion: 4,
    ingestedAt: DateTime(2026, 7, 13),
  );
}
