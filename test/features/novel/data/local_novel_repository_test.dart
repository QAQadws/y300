import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/novel/data/repositories/local_novel_repository.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_reader_anchor_format.dart';
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
      dbFuture = AppDatabase.open(databaseName: testDbName);
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
        anchorFormatVersion: NovelReaderAnchorFormat.semanticCodePoints,
        anchorTextIdentity: NovelReaderAnchorFormat.textIdentity('语义正文'),
        isProgressPercentValid: true,
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
      expect(
        progress.anchorFormatVersion,
        NovelReaderAnchorFormat.semanticCodePoints,
      );
      expect(
        progress.anchorTextIdentity,
        NovelReaderAnchorFormat.textIdentity('语义正文'),
      );
      expect(progress.isProgressPercentValid, isTrue);
    });

    test('reading progress reads old rows with defaults', () async {
      final db = await dbFuture;
      await db.insert(AppDatabase.novelReadingProgressTable, <String, Object?>{
        'novel_id': 'novel:old:progress',
        'episode_id': 'episode-old',
        'scroll_offset': 128.0,
        'updated_at': DateTime(2026, 6, 1).millisecondsSinceEpoch,
      });
      final beforeRead = (await db.query(
        AppDatabase.novelReadingProgressTable,
      )).single;

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
      expect(
        progress.anchorFormatVersion,
        NovelReaderAnchorFormat.legacyUnknown,
      );
      expect(progress.anchorTextIdentity, isNull);
      expect(progress.isProgressPercentValid, isNull);
      expect(
        (await db.query(AppDatabase.novelReadingProgressTable)).single,
        beforeRead,
      );
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
        AppDatabase.novelReadingProgressTable,
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
          formatVersion: NovelReaderAnchorFormat.semanticCodePoints,
          textIdentity: NovelReaderAnchorFormat.textIdentity('这是书签片段'),
          isProgressPercentValid: true,
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
      expect(
        bookmarks.single.anchor.formatVersion,
        NovelReaderAnchorFormat.semanticCodePoints,
      );
      expect(
        bookmarks.single.anchor.textIdentity,
        bookmark.anchor.textIdentity,
      );
      expect(bookmarks.single.anchor.isProgressPercentValid, isTrue);

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
      'legacy bookmark metadata updates preserve its opaque position',
      () async {
        final db = await dbFuture;
        await seedNovelRepository(
          db,
          seed: const NovelSourceSeed(fid: '49', tid: '200'),
        );
        final episode = (await repository.getEpisodes(
          novelId: 'novel:49:200',
        )).first;
        await db.insert(AppDatabase.readerBookmarksTable, <String, Object?>{
          'bookmark_id': 'legacy-bookmark',
          'novel_id': episode.novelId,
          'episode_id': episode.episodeId,
          'node_id': 'legacy-node',
          'text_offset': -7,
          'page_index': 3,
          'scroll_offset': 120.0,
          'progress_percent': 0.6,
          'title': '旧书签',
          'snippet': '旧坐标片段',
          'created_at': 1,
          'updated_at': 2,
        });
        final beforeRead = (await db.query(
          AppDatabase.readerBookmarksTable,
        )).single;

        final bookmark = (await repository.listReaderBookmarks(
          novelId: episode.novelId,
        )).single;

        expect(
          bookmark.anchor.formatVersion,
          NovelReaderAnchorFormat.legacyUnknown,
        );
        expect(bookmark.anchor.textIdentity, isNull);
        expect(bookmark.anchor.isProgressPercentValid, isNull);
        expect(bookmark.anchor.textOffset, -7);
        expect(bookmark.anchor.progressPercent, 0.6);
        expect(
          (await db.query(AppDatabase.readerBookmarksTable)).single,
          beforeRead,
        );

        await repository.addReaderBookmark(
          bookmark: NovelReaderBookmark(
            bookmarkId: bookmark.bookmarkId,
            novelId: bookmark.novelId,
            episodeId: bookmark.episodeId,
            anchor: bookmark.anchor,
            title: 'updated legacy title',
            snippet: bookmark.snippet,
            note: 'updated legacy note',
            createdAt: bookmark.createdAt,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(3),
          ),
        );
        expect(
          (await db.query(AppDatabase.readerBookmarksTable)).single,
          <String, Object?>{
            ...beforeRead,
            'title': 'updated legacy title',
            'note': 'updated legacy note',
            'updated_at': 3,
          },
        );
      },
    );

    test(
      'position updates preserve unsupported versions and future columns',
      () async {
        final db = await dbFuture;
        await seedNovelRepository(
          db,
          seed: const NovelSourceSeed(fid: '49', tid: '200'),
        );
        final episode = (await repository.getEpisodes(
          novelId: 'novel:49:200',
        )).first;
        for (final table in <String>[
          AppDatabase.novelReadingProgressTable,
          AppDatabase.readerBookmarksTable,
        ]) {
          await db.execute(
            'ALTER TABLE $table ADD COLUMN future_extension TEXT',
          );
        }
        const futureIdentity = ' future-v77|opaque ';
        const futureOffset = (1 << 35) + 13;
        await db
            .insert(AppDatabase.novelReadingProgressTable, <String, Object?>{
              'novel_id': episode.novelId,
              'episode_id': episode.episodeId,
              'scroll_offset': 40.0,
              'anchor_node_id': 'future-node',
              'anchor_text_offset': futureOffset,
              'anchor_format_version': 77,
              'anchor_text_identity': futureIdentity,
              'progress_percent': 0.4,
              'progress_percent_valid': 0,
              'future_extension': 'progress extension',
              'updated_at': 1,
            });
        await db.insert(AppDatabase.readerBookmarksTable, <String, Object?>{
          'bookmark_id': 'future-bookmark',
          'novel_id': episode.novelId,
          'episode_id': episode.episodeId,
          'node_id': 'future-node',
          'text_offset': futureOffset,
          'anchor_format_version': 77,
          'anchor_text_identity': futureIdentity,
          'progress_percent': 0.4,
          'progress_percent_valid': 0,
          'future_extension': 'bookmark extension',
          'title': 'future bookmark',
          'snippet': 'future snippet',
          'created_at': 1,
          'updated_at': 2,
        });

        final progress = (await repository.getReadingProgress(
          novelId: episode.novelId,
        ))!;
        final bookmark = (await repository.listReaderBookmarks(
          novelId: episode.novelId,
        )).single;
        expect(progress.anchorFormatVersion, 77);
        expect(progress.anchorTextIdentity, futureIdentity);
        expect(progress.anchorTextOffset, futureOffset);
        expect(progress.isProgressPercentValid, isFalse);
        expect(bookmark.anchor.formatVersion, 77);
        expect(bookmark.anchor.textIdentity, futureIdentity);
        expect(bookmark.anchor.textOffset, futureOffset);
        expect(bookmark.anchor.isProgressPercentValid, isFalse);

        await repository.saveReadingProgress(
          novelId: progress.novelId,
          episodeId: progress.episodeId,
          scrollOffset: 50,
          anchorNodeId: progress.anchorNodeId,
          anchorTextOffset: progress.anchorTextOffset,
          progressPercent: progress.progressPercent,
          anchorFormatVersion: progress.anchorFormatVersion,
          anchorTextIdentity: progress.anchorTextIdentity,
          isProgressPercentValid: progress.isProgressPercentValid,
        );
        await repository.addReaderBookmark(
          bookmark: NovelReaderBookmark(
            bookmarkId: bookmark.bookmarkId,
            novelId: bookmark.novelId,
            episodeId: bookmark.episodeId,
            anchor: bookmark.anchor,
            title: bookmark.title,
            snippet: bookmark.snippet,
            note: 'updated note',
            createdAt: bookmark.createdAt,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(3),
          ),
        );

        final progressRow = (await db.query(
          AppDatabase.novelReadingProgressTable,
        )).single;
        final bookmarkRow = (await db.query(
          AppDatabase.readerBookmarksTable,
        )).single;
        for (final row in <Map<String, Object?>>[progressRow, bookmarkRow]) {
          expect(row['anchor_format_version'], 77);
          expect(row['anchor_text_identity'], futureIdentity);
          expect(row['progress_percent_valid'], 0);
        }
        expect(progressRow['future_extension'], 'progress extension');
        expect(progressRow['anchor_text_offset'], futureOffset);
        expect(progressRow['scroll_offset'], 50.0);
        expect(bookmarkRow['future_extension'], 'bookmark extension');
        expect(bookmarkRow['text_offset'], futureOffset);
        expect(bookmarkRow['note'], 'updated note');
        expect(bookmarkRow['created_at'], 1);
        expect(bookmarkRow['updated_at'], 3);
      },
    );

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
            AppDatabase.worksTable,
            where: 'work_id = ? AND content_type = ?',
            whereArgs: const <Object>['novel:49:200', 'novel'],
          ),
          isEmpty,
        );
        expect(
          await db.query(
            AppDatabase.workEpisodesTable,
            where: 'work_id = ? AND content_type = ?',
            whereArgs: const <Object>['novel:49:200', 'novel'],
          ),
          isEmpty,
        );
        expect(
          await db.query(
            AppDatabase.novelShelfItemsTable,
            where: 'novel_id = ?',
            whereArgs: const <Object>['novel:49:200'],
          ),
          isEmpty,
        );
        expect(
          await db.query(
            AppDatabase.novelReadingProgressTable,
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
