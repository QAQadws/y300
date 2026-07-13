import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_source_metadata_repository.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_source_state_repository.dart';
import 'package:y300/features/novel/data/services/default_novel_source_metadata_recovery_service.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/services/novel_source_metadata_parser.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'legacy recovery loads one version=4 first page and keeps rebuild state',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'y300-novel-recovery-',
      );
      final dbPath = p.join(temp.path, 'recovery.db');
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
        'source_typeid': '295',
        'source_tag_name': '長篇連載',
        'title': '旧小说',
        'author': '旧发布者',
        'updated_at': 1,
      });
      await db.insert(ComicLocalDb.novelSourceStateTable, <String, Object?>{
        'novel_id': 'novel:55:521519',
        'publisher_name': '旧发布者',
        'source_catalog_json': '[]',
        'hydration_state': NovelChapterHydrationState.legacyNeedsRebuild.name,
        'last_completed_author_page': 0,
      });
      await db.insert(ComicLocalDb.novelCategoriesTable, <String, Object?>{
        'category_id': 'custom',
        'name': '自定义分类',
        'sort_order': 1,
        'created_at': 1,
      });
      await db.insert(ComicLocalDb.novelShelfItemsTable, <String, Object?>{
        'category_id': 'custom',
        'novel_id': 'novel:55:521519',
        'added_at': 1,
        'sort_order': 0,
      });
      final gateway = _FakeRecoveryGateway();
      final service = DefaultNovelSourceMetadataRecoveryService(
        database: Future<Database>.value(db),
        gateway: gateway,
        parser: const DefaultNovelSourceMetadataParser(),
        repository: SqfliteNovelSourceMetadataRepository(
          Future<Database>.value(db),
        ),
        clock: () => DateTime(2026, 7, 13),
      );

      final metadata = await service.recover('novel:55:521519');

      expect(gateway.requestedTids, <String>['521519']);
      expect(metadata.publisherId, '406769');
      expect(metadata.sourceApiVersion, 4);
      final sourceState = await SqfliteNovelSourceStateRepository(
        Future<Database>.value(db),
      ).getSourceState(novelId: 'novel:55:521519');
      expect(sourceState?.publisherId, '406769');
      expect(
        sourceState?.hydrationState,
        NovelChapterHydrationState.legacyNeedsRebuild,
      );
      expect(
        await db.query(
          ComicLocalDb.workEpisodesTable,
          where: 'work_id = ?',
          whereArgs: const <Object?>['novel:55:521519'],
        ),
        isEmpty,
      );
      final shelfRows = await db.query(
        ComicLocalDb.novelShelfItemsTable,
        where: 'novel_id = ?',
        whereArgs: const <Object?>['novel:55:521519'],
      );
      expect(shelfRows, hasLength(1));
      expect(shelfRows.single['category_id'], 'custom');
    },
  );
}

class _FakeRecoveryGateway implements NovelSourceMetadataRecoveryGateway {
  final List<String> requestedTids = <String>[];

  @override
  Future<ThreadDetailData> loadFirstPage({required String tid}) async {
    requestedTids.add(tid);
    return ThreadDetailData(
      tid: tid,
      fid: '55',
      typeid: '295',
      subject: '恢复后的小说标题',
      author: 'INCSKY16',
      replies: 100,
      views: 1,
      currentPage: 1,
      perPage: 20,
      posts: <ThreadPost>[
        ThreadPost(
          pid: '40213901',
          author: 'INCSKY16',
          authorId: '406769',
          message: '<p>简介</p><p>恢复后的来源简介。</p>',
          number: 1,
          isFirst: true,
          dateline: '2026-07-13',
        ),
      ],
    );
  }
}
