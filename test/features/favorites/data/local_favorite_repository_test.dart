import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('SqfliteLocalFavoriteRepository', () {
    const dbName = 'comic_shelf_test_favorite_repo.db';
    late SqfliteLocalFavoriteRepository repository;

    setUp(() async {
      await deleteDatabase(dbName);
      repository = SqfliteLocalFavoriteRepository(
        AppDatabase.open(databaseName: dbName),
      );
    });

    tearDown(() async {
      await deleteDatabase(dbName);
    });

    test(
      'loads visible system categories and keeps default free from comic and novel',
      () async {
        await repository.upsertRemoteThreads(<FavoriteThreadCacheUpsert>[
          _thread(tid: '100', title: '漫画'),
          _thread(tid: '200', title: '小说'),
          _thread(tid: '300', title: '论坛'),
        ]);
        await repository.updateThreadDetailMeta(
          tid: '100',
          fid: '30',
          typeid: '398',
          tagName: '韩国漫画',
          contentKind: ThreadContentKind.comic,
          workId: 'yamibo:100',
        );
        await repository.updateThreadDetailMeta(
          tid: '200',
          fid: '49',
          typeid: '293',
          tagName: '原创',
          contentKind: ThreadContentKind.novel,
          workId: 'novel:49:200',
        );
        await repository.updateThreadDetailMeta(
          tid: '300',
          fid: '1',
          typeid: '',
          tagName: null,
          contentKind: ThreadContentKind.forum,
          workId: 'thread:300',
        );

        final categories = await repository.loadVisibleCategories();
        final comicItems = await repository.loadCategoryItems(
          favoriteComicCategoryId,
        );
        final novelItems = await repository.loadCategoryItems(
          favoriteNovelCategoryId,
        );
        final defaultItems = await repository.loadCategoryItems(
          favoriteDefaultCategoryId,
        );

        expect(
          categories.map((category) => category.categoryId),
          containsAll(<String>[
            favoriteComicCategoryId,
            favoriteNovelCategoryId,
            favoriteDefaultCategoryId,
          ]),
        );
        expect(comicItems.single.title, '漫画');
        expect(novelItems.single.title, '小说');
        expect(defaultItems.single.title, '论坛');
      },
    );

    test('custom category overrides system category', () async {
      await repository.upsertRemoteThreads(<FavoriteThreadCacheUpsert>[
        _thread(tid: '100', title: '漫画'),
      ]);
      await repository.updateThreadDetailMeta(
        tid: '100',
        fid: '30',
        typeid: '398',
        tagName: '韩国漫画',
        contentKind: ThreadContentKind.comic,
        workId: 'yamibo:100',
      );
      final customId = await repository.createCategory(name: '追更');
      await repository.moveThreadToCategory(tid: '100', toCategoryId: customId);

      final comicItems = await repository.loadCategoryItems(
        favoriteComicCategoryId,
      );
      final customItems = await repository.loadCategoryItems(customId);

      expect(comicItems, isEmpty);
      expect(customItems.single.workId, FavoriteShelfWorkId.fromTid('100'));
    });

    test(
      'invalid system category appears on demand and preserves custom assignment',
      () async {
        await repository.upsertRemoteThreads(<FavoriteThreadCacheUpsert>[
          _thread(tid: '100', title: '自定义分类中的无效帖'),
          _thread(tid: '200', title: '无效帖'),
          _thread(tid: '300', title: '普通帖'),
        ]);
        final customId = await repository.createCategory(name: '保留分类');
        await repository.moveThreadToCategory(
          tid: '100',
          toCategoryId: customId,
        );
        await repository.updateThreadDetailMeta(
          tid: '300',
          fid: '1',
          typeid: '',
          tagName: null,
          contentKind: ThreadContentKind.forum,
          workId: 'thread:300',
        );

        expect(
          (await repository.loadVisibleCategories()).map(
            (category) => category.categoryId,
          ),
          isNot(contains(favoriteInvalidCategoryId)),
        );

        await repository.markThreadDetailInvalid(tid: '100');
        await repository.markThreadDetailInvalid(tid: '200');

        final categories = await repository.loadVisibleCategories();
        final invalidItems = await repository.loadCategoryItems(
          favoriteInvalidCategoryId,
        );
        final defaultItems = await repository.loadCategoryItems(
          favoriteDefaultCategoryId,
        );
        final customItems = await repository.loadCategoryItems(customId);

        expect(
          categories
              .where(
                (category) => category.categoryId == favoriteInvalidCategoryId,
              )
              .single
              .name,
          '无效',
        );
        expect(invalidItems.map((item) => item.title), <String>[
          '自定义分类中的无效帖',
          '无效帖',
        ]);
        expect(defaultItems.single.title, '普通帖');
        expect(customItems, isEmpty);

        await repository.updateThreadDetailMeta(
          tid: '100',
          fid: '1',
          typeid: '',
          tagName: null,
          contentKind: ThreadContentKind.forum,
          workId: 'thread:100',
        );

        expect(
          (await repository.loadCategoryItems(customId)).single.title,
          '自定义分类中的无效帖',
        );
      },
    );

    test('markRemovedTids returns removed active records', () async {
      await repository.upsertRemoteThreads(<FavoriteThreadCacheUpsert>[
        _thread(tid: '100', title: '保留'),
        _thread(tid: '200', title: '移除'),
      ]);

      final removed = await repository.markRemovedTids(const <String>{'100'});
      final active = await repository.getActiveTids();

      expect(removed.map((record) => record.tid), <String>['200']);
      expect(active, <String>{'100'});
    });

    test(
      'markRemovedByWorkId marks only matching active rows removed',
      () async {
        await repository.upsertRemoteThreads(<FavoriteThreadCacheUpsert>[
          _thread(tid: '100', title: '漫画一'),
          _thread(tid: '101', title: '漫画二'),
          _thread(tid: '102', title: '漫画三'),
          _thread(tid: '200', title: '小说一'),
        ]);
        await repository.updateThreadDetailMeta(
          tid: '100',
          fid: '30',
          typeid: '398',
          tagName: '韩国漫画',
          contentKind: ThreadContentKind.comic,
          workId: 'yamibo:shared',
        );
        await repository.updateThreadDetailMeta(
          tid: '101',
          fid: '30',
          typeid: '398',
          tagName: '韩国漫画',
          contentKind: ThreadContentKind.comic,
          workId: 'yamibo:shared',
        );
        await repository.updateThreadDetailMeta(
          tid: '102',
          fid: '30',
          typeid: '398',
          tagName: '韩国漫画',
          contentKind: ThreadContentKind.comic,
          workId: 'yamibo:shared',
        );
        await repository.updateThreadDetailMeta(
          tid: '200',
          fid: '49',
          typeid: '293',
          tagName: '原创',
          contentKind: ThreadContentKind.novel,
          workId: 'novel:49:200',
        );
        await repository.markRemovedTids(const <String>{'100', '101', '200'});

        final changed = await repository.markRemovedByWorkId('yamibo:shared');
        final shared = await repository.getActiveThreadsByWorkId(
          'yamibo:shared',
        );
        final other = await repository.getActiveThreadByTid('200');

        expect(changed, 2);
        expect(shared, isEmpty);
        expect(other, isNotNull);
        expect(other?.workId, 'novel:49:200');
      },
    );

    test('markRemovedByTids marks only target active tids removed', () async {
      await repository.upsertRemoteThreads(<FavoriteThreadCacheUpsert>[
        _thread(tid: '100', title: '漫画一'),
        _thread(tid: '101', title: '漫画二'),
        _thread(tid: '102', title: '漫画三'),
        _thread(tid: '200', title: '小说一'),
      ]);
      await repository.updateThreadDetailMeta(
        tid: '100',
        fid: '30',
        typeid: '398',
        tagName: '韩国漫画',
        contentKind: ThreadContentKind.comic,
        workId: 'yamibo:shared',
      );
      await repository.updateThreadDetailMeta(
        tid: '101',
        fid: '30',
        typeid: '398',
        tagName: '韩国漫画',
        contentKind: ThreadContentKind.comic,
        workId: 'yamibo:shared',
      );
      await repository.updateThreadDetailMeta(
        tid: '102',
        fid: '30',
        typeid: '398',
        tagName: '韩国漫画',
        contentKind: ThreadContentKind.comic,
        workId: 'yamibo:shared',
      );
      await repository.updateThreadDetailMeta(
        tid: '200',
        fid: '49',
        typeid: '293',
        tagName: '原创',
        contentKind: ThreadContentKind.novel,
        workId: 'novel:49:200',
      );
      await repository.markRemovedTids(const <String>{
        '100',
        '101',
        '102',
        '200',
      });

      final changed = await repository.markRemovedByTids(const <String>{
        '100',
        '102',
        '999',
      });
      final activeShared = await repository.getActiveThreadsByWorkId(
        'yamibo:shared',
      );
      final other = await repository.getActiveThreadByTid('200');

      expect(changed, 2);
      expect(activeShared.map((record) => record.tid), <String>['101']);
      expect(other, isNotNull);
      expect(other?.workId, 'novel:49:200');
    });

    test(
      'countMissingDetailRecords ignores loaded and removed favorites',
      () async {
        await repository.upsertRemoteThreads(<FavoriteThreadCacheUpsert>[
          _thread(tid: '100', title: '已解析'),
          _thread(tid: '200', title: '待解析'),
          _thread(tid: '300', title: '已移除'),
        ]);
        await repository.updateThreadDetailMeta(
          tid: '100',
          fid: '30',
          typeid: '398',
          tagName: '韩国漫画',
          contentKind: ThreadContentKind.comic,
          workId: 'yamibo:100',
        );
        await repository.markRemovedTids(const <String>{'100', '200'});

        expect(await repository.countMissingDetailRecords(), 1);
      },
    );

    test(
      'comic auto refresh backfill selects active comics with empty or current-only episodes',
      () async {
        final db = await AppDatabase.open(databaseName: dbName);
        await repository.upsertRemoteThreads(<FavoriteThreadCacheUpsert>[
          _thread(tid: '100', title: '空章节漫画'),
          _thread(tid: '200', title: '当前帖漫画'),
          _thread(tid: '300', title: '已补全漫画'),
        ]);
        for (final tid in <String>['100', '200', '300']) {
          await repository.updateThreadDetailMeta(
            tid: tid,
            fid: '30',
            typeid: '398',
            tagName: '韩国漫画',
            contentKind: ThreadContentKind.comic,
            workId: 'yamibo:$tid',
          );
          await db.insert(AppDatabase.comicsTable, <String, Object?>{
            'comic_id': 'yamibo:$tid',
            'source_tid': tid,
            'source_fid': '30',
            'title': '漫画$tid',
            'created_at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
            'updated_at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
          });
        }
        await db.insert(AppDatabase.episodesTable, <String, Object?>{
          'episode_id': 'yamibo:200:200',
          'comic_id': 'yamibo:200',
          'episode_title': '当前帖',
          'source_tid': '200',
          'source_url': 'thread-200-1-1.html',
          'order_index': 0,
        });
        await db.insert(AppDatabase.episodesTable, <String, Object?>{
          'episode_id': 'yamibo:300:301',
          'comic_id': 'yamibo:300',
          'episode_title': '第1话',
          'source_tid': '301',
          'source_url': 'thread-301-1-1.html',
          'order_index': 0,
        });
        await db.insert(AppDatabase.episodesTable, <String, Object?>{
          'episode_id': 'yamibo:300:302',
          'comic_id': 'yamibo:300',
          'episode_title': '第2话',
          'source_tid': '302',
          'source_url': 'thread-302-1-1.html',
          'order_index': 1,
        });

        final candidates = await repository
            .getComicAutoRefreshBackfillCandidates();

        expect(candidates.map((record) => record.tid), <String>['100', '200']);
        expect(
          await repository.hasCompletedComicAutoRefreshBackfill(),
          isFalse,
        );
        await repository.markComicAutoRefreshBackfillCompleted(
          checkedCount: candidates.length,
        );
        expect(await repository.hasCompletedComicAutoRefreshBackfill(), isTrue);
      },
    );

    test('favorite shelf item reuses comic and novel module covers', () async {
      final db = await AppDatabase.open(databaseName: dbName);
      await db.insert(AppDatabase.comicsTable, <String, Object?>{
        'comic_id': 'yamibo:100',
        'source_tid': '100',
        'source_fid': '30',
        'title': '漫画',
        'cover_image_url': 'https://img.test/comic.jpg',
        'custom_cover_image_url': 'https://img.test/comic-custom-network.jpg',
        'cover_local_path': '/cache/comic.jpg',
        'custom_cover_local_path': '/cache/comic-custom.jpg',
        'created_at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
        'updated_at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
      });
      await db.insert(AppDatabase.worksTable, <String, Object?>{
        'work_id': 'novel:49:200',
        'content_type': 'novel',
        'source_tid': '200',
        'source_fid': '49',
        'title': '小说',
        'cover_image_url': 'https://img.test/novel.jpg',
        'cover_local_path': '/cache/novel.jpg',
        'custom_cover_local_path': '/cache/novel-custom.jpg',
        'updated_at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
      });
      await repository.upsertRemoteThreads(<FavoriteThreadCacheUpsert>[
        _thread(tid: '100', title: '漫画'),
        _thread(tid: '200', title: '小说'),
      ]);
      await repository.updateThreadDetailMeta(
        tid: '100',
        fid: '30',
        typeid: '398',
        tagName: '韩国漫画',
        contentKind: ThreadContentKind.comic,
        workId: 'yamibo:100',
      );
      await repository.updateThreadDetailMeta(
        tid: '200',
        fid: '49',
        typeid: '293',
        tagName: '原创',
        contentKind: ThreadContentKind.novel,
        workId: 'novel:49:200',
      );

      final comicItems = await repository.loadCategoryItems(
        favoriteComicCategoryId,
      );
      final novelItems = await repository.loadCategoryItems(
        favoriteNovelCategoryId,
      );

      expect(
        comicItems.single.coverImageUrl,
        'https://img.test/comic-custom-network.jpg',
      );
      expect(
        comicItems.single.customCoverImageUrl,
        'https://img.test/comic-custom-network.jpg',
      );
      expect(comicItems.single.coverLocalPath, '/cache/comic.jpg');
      expect(comicItems.single.customCoverLocalPath, '/cache/comic-custom.jpg');
      expect(novelItems.single.coverImageUrl, 'https://img.test/novel.jpg');
      expect(novelItems.single.coverLocalPath, '/cache/novel.jpg');
      expect(novelItems.single.customCoverLocalPath, '/cache/novel-custom.jpg');

      await db.update(
        AppDatabase.worksTable,
        <String, Object?>{'cover_hidden': 1},
        where: 'work_id = ?',
        whereArgs: <Object?>['novel:49:200'],
      );
      final hiddenNovelItems = await repository.loadCategoryItems(
        favoriteNovelCategoryId,
      );
      final hiddenSnapshot = await repository.queryShelfSnapshot(
        filters: LibraryFilterSet.defaults,
        sortOption: LibraryShelfSortOption.defaults,
        keyword: '',
      );

      expect(hiddenNovelItems.single.coverImageUrl, isNull);
      expect(hiddenNovelItems.single.coverLocalPath, isNull);
      expect(hiddenNovelItems.single.customCoverLocalPath, isNull);
      final hiddenSnapshotNovel =
          hiddenSnapshot.itemsByCategory[favoriteNovelCategoryId]!.single;
      expect(hiddenSnapshotNovel.coverImageUrl, isNull);
      expect(hiddenSnapshotNovel.coverLocalPath, isNull);
      expect(hiddenSnapshotNovel.customCoverLocalPath, isNull);
    });

    test(
      'queryShelfSnapshot batches category counts, tags, and module covers',
      () async {
        final db = await AppDatabase.open(databaseName: dbName);
        await db.insert(AppDatabase.comicsTable, <String, Object?>{
          'comic_id': 'yamibo:100',
          'source_tid': '100',
          'source_fid': '30',
          'title': '漫画模块标题',
          'cover_image_url': 'https://img.test/comic.jpg',
          'custom_cover_image_url': 'https://img.test/comic-custom.jpg',
          'cover_local_path': '/cache/comic.jpg',
          'custom_cover_local_path': '/cache/comic-custom.jpg',
          'created_at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
          'updated_at': DateTime(2026, 1, 1).millisecondsSinceEpoch,
        });
        await repository.upsertRemoteThreads(<FavoriteThreadCacheUpsert>[
          _thread(tid: '100', title: '收藏漫画'),
        ]);
        await repository.updateThreadDetailMeta(
          tid: '100',
          fid: '30',
          typeid: '398',
          tagName: '韩国漫画',
          contentKind: ThreadContentKind.comic,
          workId: 'yamibo:100',
        );
        final stateRepository = LocalLibraryStateRepository(
          AppDatabase.open(databaseName: dbName),
        );
        final tagId = await stateRepository.createTag(name: '收藏标签');
        await stateRepository.bindTagToWork(
          moduleKey: LibraryModuleKey.favorite,
          workId: FavoriteShelfWorkId.fromTid('100'),
          tagId: tagId,
        );

        final snapshot = await repository.queryShelfSnapshot(
          filters: LibraryFilterSet.defaults,
          sortOption: LibraryShelfSortOption.defaults,
          keyword: '收藏',
        );
        final comicItems = snapshot.itemsByCategory[favoriteComicCategoryId]!;

        expect(
          snapshot.categories.map((category) => category.categoryId),
          contains(favoriteComicCategoryId),
        );
        expect(
          snapshot.visibleMatchCountByCategory[favoriteComicCategoryId],
          1,
        );
        expect(comicItems.single.workId, FavoriteShelfWorkId.fromTid('100'));
        expect(
          comicItems.single.coverImageUrl,
          'https://img.test/comic-custom.jpg',
        );
        expect(
          comicItems.single.customCoverImageUrl,
          'https://img.test/comic-custom.jpg',
        );
        expect(comicItems.single.coverLocalPath, '/cache/comic.jpg');
        expect(
          comicItems.single.customCoverLocalPath,
          '/cache/comic-custom.jpg',
        );
        expect(comicItems.single.hasTags, isTrue);
      },
    );

    test(
      'remote upsert rolls back earlier updates and inserts when one row fails',
      () async {
        await repository.upsertRemoteThreads(<FavoriteThreadCacheUpsert>[
          _thread(tid: '100', title: 'original favorite'),
        ]);
        final db = await AppDatabase.open(databaseName: dbName);
        await db.execute("""
        CREATE TRIGGER favorite_test_reject_insert
        BEFORE INSERT ON ${AppDatabase.favoriteThreadsTable}
        WHEN NEW.tid = '200'
        BEGIN
          SELECT RAISE(ABORT, 'injected row failure');
        END
        """);

        await expectLater(
          repository.upsertRemoteThreads(<FavoriteThreadCacheUpsert>[
            _thread(tid: '100', title: 'changed favorite'),
            _thread(tid: '150', title: 'new favorite'),
            _thread(tid: '200', title: 'rejected favorite'),
          ]),
          throwsA(isA<DatabaseException>()),
        );

        expect(await repository.getActiveTids(), <String>{'100'});
        expect(
          (await repository.getActiveThreadByTid('100'))?.title,
          'original favorite',
        );
      },
    );

    test(
      'category deletion rolls back assignments and later returns items to their system category',
      () async {
        await repository.upsertRemoteThreads(<FavoriteThreadCacheUpsert>[
          _thread(tid: '100', title: 'favorite'),
        ]);
        final categoryId = await repository.createCategory(name: 'custom');
        await repository.moveThreadToCategory(
          tid: '100',
          toCategoryId: categoryId,
        );
        final db = await AppDatabase.open(databaseName: dbName);
        await db.execute("""
        CREATE TRIGGER favorite_test_reject_category_delete
        BEFORE DELETE ON ${AppDatabase.favoriteCategoriesTable}
        BEGIN
          SELECT RAISE(ABORT, 'injected category failure');
        END
        """);

        await expectLater(
          repository.deleteCategory(categoryId: categoryId),
          throwsA(isA<DatabaseException>()),
        );

        expect(
          (await repository.getActiveThreadByTid('100'))?.customCategoryId,
          categoryId,
        );
        expect(
          (await repository.loadCategoryItems(categoryId)).single.workId,
          FavoriteShelfWorkId.fromTid('100'),
        );
        expect(
          (await repository.loadVisibleCategories()).map(
            (category) => category.categoryId,
          ),
          contains(categoryId),
        );

        await db.execute('DROP TRIGGER favorite_test_reject_category_delete');
        await repository.deleteCategory(categoryId: categoryId);

        expect(
          (await repository.getActiveThreadByTid('100'))?.customCategoryId,
          isNull,
        );
        expect(
          (await repository.loadVisibleCategories()).map(
            (category) => category.categoryId,
          ),
          isNot(contains(categoryId)),
        );
        expect(
          (await repository.loadCategoryItems(
            favoriteDefaultCategoryId,
          )).single.workId,
          FavoriteShelfWorkId.fromTid('100'),
        );
      },
    );

    test(
      'incremental completion and failure preserve the last full-sync baseline',
      () async {
        final lastFullSync = DateTime.utc(2025, 1, 1);
        final db = await AppDatabase.open(databaseName: dbName);
        await db.insert(AppDatabase.favoriteSyncStateTable, <String, Object?>{
          'sync_key': favoriteSyncKey,
          'remote_count': 2,
          'local_active_count': 2,
          'last_synced_at': lastFullSync.millisecondsSinceEpoch,
          'last_full_synced_at': lastFullSync.millisecondsSinceEpoch,
          'status': 'ok',
        });
        await repository.upsertRemoteThreads(<FavoriteThreadCacheUpsert>[
          _thread(tid: '100', title: 'active'),
          _thread(tid: '200', title: 'removed'),
        ]);
        await repository.markRemovedByTids(<String>{'200'});

        await repository.finishSync(
          mode: FavoriteSyncMode.incremental,
          remoteCount: 3,
          status: 'partial',
          message: 'detail issue',
        );
        final completed = (await repository.getSyncSnapshot())!;
        expect(completed.remoteCount, 3);
        expect(completed.localActiveCount, 1);
        expect(completed.status, 'partial');
        expect(
          completed.lastFullSyncedAt?.millisecondsSinceEpoch,
          lastFullSync.millisecondsSinceEpoch,
        );

        await repository.markSyncFailure('network failure');
        final failed = (await repository.getSyncSnapshot())!;
        expect(failed.remoteCount, completed.remoteCount);
        expect(failed.localActiveCount, completed.localActiveCount);
        expect(failed.status, 'failed');
        expect(
          failed.lastFullSyncedAt?.millisecondsSinceEpoch,
          lastFullSync.millisecondsSinceEpoch,
        );

        await repository.finishSync(
          mode: FavoriteSyncMode.fullDiff,
          remoteCount: 1,
        );
        final recovered = (await repository.getSyncSnapshot())!;
        expect(recovered.status, 'ok');
        expect(recovered.remoteCount, 1);
        expect(recovered.localActiveCount, 1);
        expect(recovered.lastFullSyncedAt, recovered.lastSyncedAt);
        expect(recovered.lastFullSyncedAt!.isAfter(lastFullSync), isTrue);
      },
    );

    test('snapshot query count stays constant as the shelf grows', () async {
      final db = await AppDatabase.open(databaseName: dbName);
      final counted = _QueryCountingDatabase(db);
      final snapshotRepository = SqfliteLocalFavoriteRepository(
        Future<Database>.value(counted),
      );
      Future<int> queryCountFor(int expectedPerModule) async {
        counted.queryCount = 0;
        final snapshot = await snapshotRepository.queryShelfSnapshot(
          filters: LibraryFilterSet.defaults,
          sortOption: LibraryShelfSortOption.defaults,
          keyword: '',
        );
        for (final categoryId in [
          favoriteComicCategoryId,
          favoriteNovelCategoryId,
        ]) {
          final items = snapshot.itemsByCategory[categoryId]!;
          expect(items, hasLength(expectedPerModule));
          expect(items.every((item) => item.coverImageUrl != null), isTrue);
          expect(items.every((item) => item.hasTags), isTrue);
        }
        return counted.queryCount;
      }

      await _seedSnapshotRange(db, 0, 10);
      final smallShelfQueries = await queryCountFor(5);
      await _seedSnapshotRange(db, 10, 100);
      final largeShelfQueries = await queryCountFor(50);

      expect(smallShelfQueries, greaterThan(0));
      expect(largeShelfQueries, smallShelfQueries);
    });
  });
}

class _QueryCountingDatabase implements Database {
  _QueryCountingDatabase(this.delegate);

  final Database delegate;
  int queryCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #query || invocation.memberName == #rawQuery) {
      queryCount++;
      return Function.apply(
        invocation.memberName == #query ? delegate.query : delegate.rawQuery,
        invocation.positionalArguments,
        invocation.namedArguments,
      );
    }
    return super.noSuchMethod(invocation);
  }
}

Future<void> _seedSnapshotRange(Database db, int start, int end) async {
  final batch = db.batch();
  batch.insert(AppDatabase.libraryTagsTable, <String, Object?>{
    'tag_id': 'snapshot-tag',
    'name': 'tag',
    'created_at': 1,
  }, conflictAlgorithm: ConflictAlgorithm.ignore);
  for (var index = start; index < end; index++) {
    final comic = index.isEven;
    final tid = '${1000 + index}';
    final workId = '${comic ? 'comic' : 'novel'}:$tid';
    final module = comic ? 'comic' : 'novel';
    batch.insert(
      comic ? AppDatabase.comicsTable : AppDatabase.worksTable,
      <String, Object?>{
        if (comic) 'comic_id': workId else 'work_id': workId,
        if (!comic) 'content_type': 'novel',
        'source_tid': tid,
        'source_fid': comic ? '30' : '49',
        'title': '$module $tid',
        'cover_image_url': 'https://img.test/$tid.jpg',
        if (comic) 'created_at': 1,
        'updated_at': 1,
      },
    );
    batch.insert(AppDatabase.favoriteThreadsTable, <String, Object?>{
      'tid': tid,
      'title': 'favorite $tid',
      'content_kind': module,
      'work_id': workId,
      'first_seen_at': 1,
      'last_seen_at': 1,
    });
    batch.insert(AppDatabase.libraryWorkTagsTable, <String, Object?>{
      'content_type': 'favorite',
      'work_id': FavoriteShelfWorkId.fromTid(tid),
      'tag_id': 'snapshot-tag',
    });
  }
  await batch.commit(noResult: true);
}

FavoriteThreadCacheUpsert _thread({
  required String tid,
  required String title,
}) {
  return FavoriteThreadCacheUpsert(
    remoteFavoriteId: 'fav-$tid',
    tid: tid,
    title: title,
    description: '',
    authorName: '作者',
    replyCount: 0,
    favoritedAt: DateTime.fromMillisecondsSinceEpoch(
      1767225600 * Duration.millisecondsPerSecond,
      isUtc: true,
    ),
  );
}
