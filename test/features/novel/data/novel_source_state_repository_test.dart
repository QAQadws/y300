import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_source_state_repository.dart';
import 'package:y300/features/novel/domain/models/novel_chapter_sync_models.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('source metadata, hydration state, and checkpoint round trip', () async {
    final temp = await Directory.systemTemp.createTemp(
      'y300-novel-source-state-',
    );
    final dbPath = p.join(temp.path, 'source-state.db');
    final db = await ComicLocalDb.open(databaseName: dbPath);
    addTearDown(() async {
      await db.close();
      await deleteDatabase(dbPath);
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });
    await db.insert(ComicLocalDb.worksTable, <String, Object?>{
      'work_id': 'novel:55:521519',
      'content_type': 'novel',
      'source_tid': '521519',
      'source_fid': '55',
      'title': '测试小说',
      'author': 'INCSKY16',
      'updated_at': 1783900800000,
    });
    final repository = SqfliteNovelSourceStateRepository(Future.value(db));
    final ingestedAt = DateTime(2026, 7, 13, 12);

    await repository.saveMetadata(
      NovelSourceMetadata(
        novelId: 'novel:55:521519',
        tid: '521519',
        fid: '55',
        subject: '测试小说',
        publisherName: 'INCSKY16',
        publisherId: '406769',
        firstPostPid: '40213901',
        catalogEntries: const <NovelSourceCatalogEntry>[
          NovelSourceCatalogEntry(
            position: 1,
            pid: '40213901',
            title: '第一章',
            url: 'forum.php?mod=redirect&goto=findpost&pid=40213901',
          ),
        ],
        sourceIntro: '来源简介',
        coverImageUrl: 'https://img.example.test/cover.jpg',
        sourceApiVersion: 4,
        ingestedAt: ingestedAt,
      ),
    );

    var state = await repository.getSourceState(novelId: 'novel:55:521519');
    expect(state, isNotNull);
    expect(state?.publisherId, '406769');
    expect(state?.publisherName, 'INCSKY16');
    expect(state?.sourceIntro, '来源简介');
    expect(state?.metadataSourceVersion, 4);
    expect(state?.hydrationState, NovelChapterHydrationState.metadataOnly);
    expect(state?.catalogEntries.single.pid, '40213901');
    expect(state?.metadataIngestedAt, ingestedAt);
    expect(state?.checkpoint, isNull);

    await repository.setHydrationState(
      novelId: 'novel:55:521519',
      state: NovelChapterHydrationState.failed,
      lastError: 'network failure',
    );
    state = await repository.getSourceState(novelId: 'novel:55:521519');
    expect(state?.hydrationState, NovelChapterHydrationState.failed);
    expect(state?.lastError, 'network failure');

    final completedAt = DateTime(2026, 7, 13, 13);
    await repository.saveCheckpoint(
      NovelChapterSyncCheckpoint(
        novelId: 'novel:55:521519',
        publisherId: '406769',
        lastCompletedAuthorPage: 3,
        lastSeenPid: '41397522',
        completedAt: completedAt,
      ),
    );
    state = await repository.getSourceState(novelId: 'novel:55:521519');
    expect(state?.hydrationState, NovelChapterHydrationState.ready);
    expect(state?.lastError, isNull);
    expect(state?.chaptersHydratedAt, completedAt);
    expect(state?.checkpoint?.lastCompletedAuthorPage, 3);
    expect(state?.checkpoint?.lastSeenPid, '41397522');
    expect(state?.checkpoint?.publisherId, '406769');
    expect(state?.checkpoint?.completedAt, completedAt);
  });
}
