import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/novel/data/repositories/local_novel_repository.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_source_models.dart';

import '../test_support/novel_repository_seed.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  const testDbName = 'comic_shelf_test_novel_repo.db';

  group('LocalNovelRepository', () {
    late LocalNovelRepository repository;
    late Future<Database> dbFuture;

    setUp(() async {
      await deleteDatabase(testDbName);
      dbFuture = ComicLocalDb.open(databaseName: testDbName);
      repository = LocalNovelRepository(dbFuture);
    });

    tearDown(() async {
      await (await dbFuture).close();
      await deleteDatabase(testDbName);
    });

    test('reads seeded shelf metadata, chapters and content', () async {
      await seedNovelRepository(
        await dbFuture,
        seed: const NovelSourceSeed(
          fid: '49',
          tid: '200',
          typeid: '293',
          tagName: '原创',
        ),
      );

      final shelf = await repository.getShelfItems();
      final episodes = await repository.getEpisodes(novelId: 'novel:49:200');
      final content = await repository.getChapterContent(
        episodeId: episodes.first.episodeId,
      );

      expect(episodes, hasLength(2));
      expect(shelf.length, 1);
      expect(shelf.first.sourceFid, '49');
      expect(shelf.first.sourceTypeId, '293');
      expect(shelf.first.sourceTagName, '原创');
      expect(shelf.first.coverImageUrl, 'https://img.test/novel-cover.jpg');
      expect(shelf.first.categoryId, 'default');
      expect(episodes.first.sourceTid, '200');
      expect(episodes.first.sourcePid, '5001');
      expect(content, isNotNull);
      expect(content!.paragraphs, isNotEmpty);
    });

    test('custom title and cover survive source refresh', () async {
      const novelId = 'novel:49:200';
      await seedNovelRepository(
        await dbFuture,
        seed: const NovelSourceSeed(fid: '49', tid: '200'),
      );
      await repository.updateCustomMetadata(
        novelId: novelId,
        customTitle: '自定义标题',
      );
      await repository.updateCustomCover(
        novelId: novelId,
        customCoverLocalPath: 'cache/novel-cover.jpg',
        focusX: 0.25,
        focusY: -0.5,
      );

      await seedNovelRepository(
        await dbFuture,
        seed: const NovelSourceSeed(fid: '49', tid: '200'),
      );

      var detail = await repository.getDetail(novelId: novelId);
      expect(detail?.displayTitle, '自定义标题');
      expect(detail?.publisherName, '楼主A');
      expect(detail?.customCoverLocalPath, 'cache/novel-cover.jpg');
      expect(detail?.customCoverFocusX, 0.25);
      expect(detail?.customCoverFocusY, -0.5);

      await repository.removeCustomCover(novelId: novelId);
      detail = await repository.getDetail(novelId: novelId);

      expect(detail?.publisherName, '楼主A');
      expect(detail?.customCoverLocalPath, isNull);
      expect(detail?.customCoverFocusX, isNull);
      expect(detail?.customCoverFocusY, isNull);
      expect(detail?.coverHidden, isTrue);

      await seedNovelRepository(
        await dbFuture,
        seed: const NovelSourceSeed(fid: '49', tid: '200'),
      );
      detail = await repository.getDetail(novelId: novelId);
      expect(detail?.coverHidden, isTrue);

      await repository.updateCustomCover(
        novelId: novelId,
        customCoverLocalPath: 'cache/replacement-cover.jpg',
      );
      detail = await repository.getDetail(novelId: novelId);
      expect(detail?.coverHidden, isFalse);
      expect(detail?.customCoverLocalPath, 'cache/replacement-cover.jpg');
    });

    test('reading progress can persist', () async {
      await seedNovelRepository(
        await dbFuture,
        seed: const NovelSourceSeed(fid: '55', tid: '300'),
      );

      final episodes = await repository.getEpisodes(novelId: 'novel:55:300');

      await repository.saveReadingProgress(
        novelId: 'novel:55:300',
        episodeId: episodes.first.episodeId,
        scrollOffset: 222.5,
        flowMode: NovelReaderFlowMode.pagedLtr,
        pageIndex: 3,
        pageCount: 10,
        anchorNodeId: 'node-3',
        anchorTextOffset: 17,
        paginationKey: 'layout-key-3',
        progressPercent: 0.42,
      );

      final progress = await repository.getReadingProgress(
        novelId: 'novel:55:300',
      );

      expect(progress, isNotNull);
      expect(progress!.episodeId, episodes.first.episodeId);
      expect(progress.scrollOffset, 222.5);
      expect(progress.flowMode, NovelReaderFlowMode.pagedLtr);
      expect(progress.pageIndex, 3);
      expect(progress.pageCount, 10);
      expect(progress.anchorNodeId, 'node-3');
      expect(progress.anchorTextOffset, 17);
      expect(progress.paginationKey, 'layout-key-3');
      expect(progress.progressPercent, 0.42);
    });

    test('reading progress reads old rows with defaults', () async {
      final db = await dbFuture;
      await db.insert(ComicLocalDb.novelReadingProgressTable, <String, Object?>{
        'novel_id': 'novel:old:progress',
        'episode_id': 'episode-old',
        'scroll_offset': 128.0,
        'updated_at': DateTime(2026, 6, 1).millisecondsSinceEpoch,
      });

      final progress = await repository.getReadingProgress(
        novelId: 'novel:old:progress',
      );

      expect(progress, isNotNull);
      expect(progress!.episodeId, 'episode-old');
      expect(progress.scrollOffset, 128);
      expect(progress.flowMode, NovelReaderFlowMode.vertical);
      expect(progress.pageIndex, 0);
      expect(progress.pageCount, isNull);
      expect(progress.anchorNodeId, isNull);
      expect(progress.anchorTextOffset, 0);
      expect(progress.paginationKey, isNull);
      expect(progress.progressPercent, 0);
    });

    test('reading progress keeps exactly one row per novel', () async {
      await repository.saveReadingProgress(
        novelId: 'novel:single-progress',
        episodeId: 'episode-1',
        scrollOffset: 20,
      );
      await repository.saveReadingProgress(
        novelId: 'novel:single-progress',
        episodeId: 'episode-2',
        scrollOffset: 0,
        flowMode: NovelReaderFlowMode.pagedRtl,
        pageIndex: 0,
        pageCount: 8,
      );

      final db = await dbFuture;
      final rows = await db.query(
        ComicLocalDb.novelReadingProgressTable,
        where: 'novel_id = ?',
        whereArgs: const <Object>['novel:single-progress'],
      );
      final progress = await repository.getReadingProgress(
        novelId: 'novel:single-progress',
      );

      expect(rows, hasLength(1));
      expect(progress?.episodeId, 'episode-2');
      expect(progress?.pageCount, 8);
    });

    test('reader bookmarks can persist and are purged with work', () async {
      await seedNovelRepository(
        await dbFuture,
        seed: const NovelSourceSeed(fid: '49', tid: '200'),
      );

      final episodes = await repository.getEpisodes(novelId: 'novel:49:200');
      final now = DateTime(2026, 6, 8);
      final bookmark = NovelReaderBookmark(
        bookmarkId: 'bookmark-1',
        novelId: 'novel:49:200',
        episodeId: episodes.first.episodeId,
        anchor: NovelReaderTextAnchor(
          episodeId: episodes.first.episodeId,
          nodeId: 'node-1',
          textOffset: 3,
          pageIndex: 2,
          scrollOffset: 88,
          progressPercent: 0.5,
        ),
        title: '第1章',
        snippet: '这是书签片段',
        createdAt: now,
        updatedAt: now,
      );

      await repository.addReaderBookmark(bookmark: bookmark);
      var bookmarks = await repository.listReaderBookmarks(
        novelId: 'novel:49:200',
      );

      expect(bookmarks, hasLength(1));
      expect(bookmarks.single.bookmarkId, 'bookmark-1');
      expect(bookmarks.single.anchor.nodeId, 'node-1');
      expect(bookmarks.single.anchor.pageIndex, 2);

      await repository.removeReaderBookmark(bookmarkId: 'bookmark-1');
      expect(
        await repository.listReaderBookmarks(novelId: 'novel:49:200'),
        isEmpty,
      );

      await repository.addReaderBookmark(bookmark: bookmark);
      await repository.purgeWork(novelId: 'novel:49:200');
      bookmarks = await repository.listReaderBookmarks(novelId: 'novel:49:200');
      expect(bookmarks, isEmpty);
    });

    test(
      'toggleEpisodeBookmark exposes existing episode bookmark state',
      () async {
        await seedNovelRepository(
          await dbFuture,
          seed: const NovelSourceSeed(fid: '49', tid: '200'),
        );

        final episodes = await repository.getEpisodes(novelId: 'novel:49:200');

        await repository.toggleEpisodeBookmark(
          novelId: 'novel:49:200',
          episodeId: episodes.first.episodeId,
          isBookmarked: true,
        );

        var bookmarks = await repository.listReaderBookmarks(
          novelId: 'novel:49:200',
        );
        expect(
          bookmarks.map((bookmark) => bookmark.bookmarkId),
          contains('episode-bookmark:${episodes.first.episodeId}'),
        );

        await repository.toggleEpisodeBookmark(
          novelId: 'novel:49:200',
          episodeId: episodes.first.episodeId,
          isBookmarked: false,
        );
        bookmarks = await repository.listReaderBookmarks(
          novelId: 'novel:49:200',
        );
        expect(
          bookmarks.map((bookmark) => bookmark.bookmarkId),
          isNot(contains('episode-bookmark:${episodes.first.episodeId}')),
        );
      },
    );

    test(
      'purgeWork deletes only target novel data and reading progress',
      () async {
        await seedNovelRepository(
          await dbFuture,
          seed: const NovelSourceSeed(fid: '49', tid: '200'),
        );
        await seedNovelRepository(
          await dbFuture,
          seed: const NovelSourceSeed(fid: '55', tid: '300'),
        );
        final purgeEpisodes = await repository.getEpisodes(
          novelId: 'novel:49:200',
        );
        final keepEpisodes = await repository.getEpisodes(
          novelId: 'novel:55:300',
        );
        await repository.saveReadingProgress(
          novelId: 'novel:49:200',
          episodeId: purgeEpisodes.first.episodeId,
          scrollOffset: 88,
        );

        await repository.purgeWork(novelId: 'novel:49:200');

        final db = await dbFuture;
        expect(await repository.getDetail(novelId: 'novel:49:200'), isNull);
        expect(await repository.getEpisodes(novelId: 'novel:49:200'), isEmpty);
        expect(
          await repository.getChapterContent(
            episodeId: purgeEpisodes.first.episodeId,
          ),
          isNull,
        );
        expect(
          await repository.getReadingProgress(novelId: 'novel:49:200'),
          isNull,
        );
        expect(
          await db.query(
            ComicLocalDb.worksTable,
            where: 'work_id = ? AND content_type = ?',
            whereArgs: const <Object>['novel:49:200', 'novel'],
          ),
          isEmpty,
        );
        expect(
          await db.query(
            ComicLocalDb.workEpisodesTable,
            where: 'work_id = ? AND content_type = ?',
            whereArgs: const <Object>['novel:49:200', 'novel'],
          ),
          isEmpty,
        );
        expect(
          await db.query(
            ComicLocalDb.novelShelfItemsTable,
            where: 'novel_id = ?',
            whereArgs: const <Object>['novel:49:200'],
          ),
          isEmpty,
        );
        expect(
          await db.query(
            ComicLocalDb.novelReadingProgressTable,
            where: 'novel_id = ?',
            whereArgs: const <Object>['novel:49:200'],
          ),
          isEmpty,
        );
        expect(await repository.getDetail(novelId: 'novel:55:300'), isNotNull);
        expect(keepEpisodes, isNotEmpty);
        expect(
          await repository.getEpisodes(novelId: 'novel:55:300'),
          hasLength(keepEpisodes.length),
        );
      },
    );

    test(
      'queryShelfSnapshot ignores novel read state and aggregates bookmarks',
      () async {
        await seedNovelRepository(
          await dbFuture,
          seed: const NovelSourceSeed(fid: '49', tid: '200'),
        );

        final episodes = await repository.getEpisodes(novelId: 'novel:49:200');
        final stateRepository = LocalLibraryStateRepository(dbFuture);
        await stateRepository.upsertEpisodeState(
          moduleKey: LibraryModuleKey.novel,
          episodeId: episodes.first.episodeId,
          workId: 'novel:49:200',
          isRead: false,
          isDownloaded: true,
          isBookmarked: true,
        );
        await stateRepository.upsertEpisodeState(
          moduleKey: LibraryModuleKey.novel,
          episodeId: episodes.last.episodeId,
          workId: 'novel:49:200',
          isRead: true,
        );
        final tagId = await stateRepository.createTag(name: '连载');
        await stateRepository.bindTagToWork(
          moduleKey: LibraryModuleKey.novel,
          workId: 'novel:49:200',
          tagId: tagId,
        );

        final snapshot = await repository.queryShelfSnapshot(
          filters: LibraryFilterSet.defaults,
          sortOption: LibraryShelfSortOption.defaults,
          keyword: '测试小说',
        );
        final item = snapshot.itemsByCategory['default']!.single;

        expect(snapshot.visibleMatchCountByCategory['default'], 1);
        expect(item.title, '测试小说标题');
        expect(item.unreadCount, 0);
        expect(item.readChapterCount, 0);
        expect(item.totalChapterCount, episodes.length);
        expect(item.isDownloaded, isFalse);
        expect(item.hasTags, isTrue);
        expect(item.hasBookmarks, isTrue);

        final bookmarked = await repository.queryShelfSnapshot(
          filters: const LibraryFilterSet(
            bookmarked: TriStateFilterValue.include,
          ),
          sortOption: LibraryShelfSortOption.defaults,
          keyword: '',
        );
        final withoutBookmarks = await repository.queryShelfSnapshot(
          filters: const LibraryFilterSet(
            bookmarked: TriStateFilterValue.exclude,
          ),
          sortOption: LibraryShelfSortOption.defaults,
          keyword: '',
        );

        expect(bookmarked.itemsByCategory['default'], hasLength(1));
        expect(withoutBookmarks.itemsByCategory['default'], isEmpty);
      },
    );
  });
}
