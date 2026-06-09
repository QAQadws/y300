import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/data/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/novel/data/local_novel_repository.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/services/novel_episode_discovery_service.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

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
      repository = LocalNovelRepository(
        dbFuture,
        threadGateway: _FakeGateway(),
        discoveryService: const NovelEpisodeDiscoveryService(),
      );
    });

    tearDown(() async {
      await deleteDatabase(testDbName);
    });

    test('upsertNovelBySeed + refreshEpisodes builds readable shelf and episodes', () async {
      await repository.upsertNovelBySeed(
        seed: const NovelRefreshSeed(
          fid: '49',
          tid: '200',
          typeid: '293',
          tagName: '原创',
        ),
      );
      final result = await repository.refreshEpisodes(novelId: 'novel:49:200');

      final shelf = await repository.getShelfItems();
      final episodes = await repository.getEpisodes(novelId: 'novel:49:200');
      final content = await repository.getChapterContent(episodeId: episodes.first.episodeId);

      expect(result.totalCount, greaterThan(0));
      expect(shelf.length, 1);
      expect(shelf.first.sourceFid, '49');
      expect(shelf.first.sourceTypeId, '293');
      expect(shelf.first.sourceTagName, '原创');
      expect(shelf.first.coverImageUrl, 'https://img.test/novel-cover.jpg');
      expect(shelf.first.categoryId, 'default');
      expect(episodes.length, greaterThan(0));
      expect(episodes.first.sourceTid, '200');
      expect(episodes.first.sourcePid, '5001');
      expect(content, isNotNull);
      expect(content!.paragraphs, isNotEmpty);
    });

    test('reader preferences and reading progress can persist', () async {
      await repository.upsertNovelBySeed(seed: const NovelRefreshSeed(fid: '55', tid: '300'));
      await repository.refreshEpisodes(novelId: 'novel:55:300');
      final episodes = await repository.getEpisodes(novelId: 'novel:55:300');

      await repository.upsertReaderPreferences(
        NovelReaderPreferences(
          fontSize: 20,
          lineHeight: 2.0,
          paragraphSpacing: 12,
          pagePadding: 18,
          themeMode: 'sepia',
          fontFamily: 'system',
          flowMode: NovelReaderFlowMode.pagedLtr,
          contentMaxWidth: 640,
          firstLineIndent: 28,
          fontWeight: 500,
          textAlign: NovelReaderTextAlignMode.justify,
          showProgressIndicator: false,
          showChapterTitle: false,
        ),
      );
      await repository.saveReadingProgress(
        novelId: 'novel:55:300',
        episodeId: episodes.first.episodeId,
        scrollOffset: 222.5,
        flowMode: NovelReaderFlowMode.pagedLtr,
        pageIndex: 3,
        anchorNodeId: 'node-3',
        progressPercent: 0.42,
      );

      final preferences = await repository.getReaderPreferences();
      final progress = await repository.getReadingProgress(novelId: 'novel:55:300');

      expect(preferences.themeMode, 'sepia');
      expect(preferences.themePreset, NovelReaderThemePreset.sepia);
      expect(preferences.fontSize, 20);
      expect(preferences.flowMode, NovelReaderFlowMode.pagedLtr);
      expect(preferences.contentMaxWidth, 640);
      expect(preferences.firstLineIndent, 28);
      expect(preferences.fontWeight, 500);
      expect(preferences.textAlign, NovelReaderTextAlignMode.justify);
      expect(preferences.showProgressIndicator, isFalse);
      expect(preferences.showChapterTitle, isFalse);
      expect(progress, isNotNull);
      expect(progress!.episodeId, episodes.first.episodeId);
      expect(progress.scrollOffset, 222.5);
      expect(progress.flowMode, NovelReaderFlowMode.pagedLtr);
      expect(progress.pageIndex, 3);
      expect(progress.anchorNodeId, 'node-3');
      expect(progress.progressPercent, 0.42);
    });

    test('reading progress reads old rows with defaults', () async {
      final db = await dbFuture;
      await db.insert(
        ComicLocalDb.novelReadingProgressTable,
        <String, Object?>{
          'novel_id': 'novel:old:progress',
          'episode_id': 'episode-old',
          'scroll_offset': 128.0,
          'updated_at': DateTime(2026, 6, 1).millisecondsSinceEpoch,
        },
      );

      final progress = await repository.getReadingProgress(
        novelId: 'novel:old:progress',
      );

      expect(progress, isNotNull);
      expect(progress!.episodeId, 'episode-old');
      expect(progress.scrollOffset, 128);
      expect(progress.flowMode, NovelReaderFlowMode.vertical);
      expect(progress.pageIndex, 0);
      expect(progress.anchorNodeId, isNull);
      expect(progress.progressPercent, 0);
    });

    test('reader bookmarks can persist and are purged with work', () async {
      await repository.upsertNovelBySeed(seed: const NovelRefreshSeed(fid: '49', tid: '200'));
      await repository.refreshEpisodes(novelId: 'novel:49:200');
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
      var bookmarks = await repository.listReaderBookmarks(novelId: 'novel:49:200');

      expect(bookmarks, hasLength(1));
      expect(bookmarks.single.bookmarkId, 'bookmark-1');
      expect(bookmarks.single.anchor.nodeId, 'node-1');
      expect(bookmarks.single.anchor.pageIndex, 2);

      await repository.removeReaderBookmark(bookmarkId: 'bookmark-1');
      expect(await repository.listReaderBookmarks(novelId: 'novel:49:200'), isEmpty);

      await repository.addReaderBookmark(bookmark: bookmark);
      await repository.purgeWork(novelId: 'novel:49:200');
      bookmarks = await repository.listReaderBookmarks(novelId: 'novel:49:200');
      expect(bookmarks, isEmpty);
    });

    test('toggleEpisodeBookmark exposes existing episode bookmark state', () async {
      await repository.upsertNovelBySeed(seed: const NovelRefreshSeed(fid: '49', tid: '200'));
      await repository.refreshEpisodes(novelId: 'novel:49:200');
      final episodes = await repository.getEpisodes(novelId: 'novel:49:200');

      await repository.toggleEpisodeBookmark(
        novelId: 'novel:49:200',
        episodeId: episodes.first.episodeId,
        isBookmarked: true,
      );

      var bookmarks = await repository.listReaderBookmarks(novelId: 'novel:49:200');
      expect(
        bookmarks.map((bookmark) => bookmark.bookmarkId),
        contains('episode-bookmark:${episodes.first.episodeId}'),
      );

      await repository.toggleEpisodeBookmark(
        novelId: 'novel:49:200',
        episodeId: episodes.first.episodeId,
        isBookmarked: false,
      );
      bookmarks = await repository.listReaderBookmarks(novelId: 'novel:49:200');
      expect(
        bookmarks.map((bookmark) => bookmark.bookmarkId),
        isNot(contains('episode-bookmark:${episodes.first.episodeId}')),
      );
    });

    test('reader preferences read old rows with defaults', () async {
      final db = await dbFuture;
      await db.insert(
        ComicLocalDb.readerPreferencesTable,
        const <String, Object?>{
          'content_type': 'novel',
          'font_size': 19.0,
          'line_height': 1.9,
          'paragraph_spacing': 8.0,
          'page_padding': 20.0,
          'theme_mode': 'dark',
          'font_family': 'system',
        },
      );

      final preferences = await repository.getReaderPreferences();

      expect(preferences.fontSize, 19);
      expect(preferences.themePreset, NovelReaderThemePreset.dark);
      expect(preferences.themeMode, 'dark');
      expect(preferences.flowMode, NovelReaderFlowMode.vertical);
      expect(preferences.contentMaxWidth, 720);
      expect(preferences.firstLineIndent, 0);
      expect(preferences.fontWeight, 400);
      expect(preferences.textAlign, NovelReaderTextAlignMode.start);
      expect(preferences.showProgressIndicator, isTrue);
      expect(preferences.showChapterTitle, isTrue);
    });

    test('purgeWork deletes only target novel data and reading progress', () async {
      await repository.upsertNovelBySeed(seed: const NovelRefreshSeed(fid: '49', tid: '200'));
      await repository.upsertNovelBySeed(seed: const NovelRefreshSeed(fid: '55', tid: '300'));
      await repository.refreshEpisodes(novelId: 'novel:49:200');
      await repository.refreshEpisodes(novelId: 'novel:55:300');

      final purgeEpisodes = await repository.getEpisodes(novelId: 'novel:49:200');
      final keepEpisodes = await repository.getEpisodes(novelId: 'novel:55:300');
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
        await repository.getChapterContent(episodeId: purgeEpisodes.first.episodeId),
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
      expect(await repository.getEpisodes(novelId: 'novel:55:300'), hasLength(keepEpisodes.length));
    });

    test('queryShelfSnapshot aggregates episode state and tags', () async {
      await repository.upsertNovelBySeed(seed: const NovelRefreshSeed(fid: '49', tid: '200'));
      await repository.refreshEpisodes(novelId: 'novel:49:200');
      final episodes = await repository.getEpisodes(novelId: 'novel:49:200');
      final stateRepository = LocalLibraryStateRepository(dbFuture);
      await stateRepository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.novel,
        episodeId: episodes.first.episodeId,
        workId: 'novel:49:200',
        isRead: false,
        isDownloaded: true,
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
      expect(item.unreadCount, 1);
      expect(item.readChapterCount, 1);
      expect(item.totalChapterCount, greaterThanOrEqualTo(episodes.length));
      expect(item.isDownloaded, isTrue);
      expect(item.hasTags, isTrue);
    });

    test('refreshEpisodes removes stale parsed episode rows', () async {
      await repository.upsertNovelBySeed(seed: const NovelRefreshSeed(fid: '49', tid: '200'));
      final db = await dbFuture;
      await db.insert(
        ComicLocalDb.workEpisodesTable,
        <String, Object?>{
          'episode_id': 'novel:49:200:stale-tid',
          'work_id': 'novel:49:200',
          'content_type': 'novel',
          'source_tid': '200',
          'source_pid': '200',
          'source_page': 1,
          'episode_title': '错误旧章节',
          'order_index': 99,
          'dateline_text': '',
        },
      );
      await db.insert(
        ComicLocalDb.novelEpisodeContentTable,
        <String, Object?>{
          'episode_id': 'novel:49:200:stale-tid',
          'raw_html': '',
          'plain_text': '',
          'paragraph_json': '[]',
          'updated_at': 0,
        },
      );

      await repository.refreshEpisodes(novelId: 'novel:49:200');

      final episodes = await repository.getEpisodes(novelId: 'novel:49:200');
      final staleContent = await repository.getChapterContent(episodeId: 'novel:49:200:stale-tid');
      expect(episodes.map((episode) => episode.episodeId), isNot(contains('novel:49:200:stale-tid')));
      expect(staleContent, isNull);
    });
  });
}

class _FakeGateway implements NovelThreadGateway {
  @override
  Future<ThreadDetailData> getThreadDetail({required String tid, required int page}) async {
    if (page > 1) {
      return ThreadDetailData(
        tid: tid,
        fid: '49',
        subject: '测试小说标题',
        author: '楼主A',
        replies: 1,
        views: 10,
        currentPage: page,
        perPage: 20,
        posts: const <ThreadPost>[],
      );
    }

    return ThreadDetailData(
      tid: tid,
      fid: '49',
      subject: '测试小说标题',
      author: '楼主A',
      replies: 2,
      views: 10,
      currentPage: 1,
      perPage: 20,
      posts: <ThreadPost>[
        ThreadPost(
          pid: '5001',
          author: '楼主A',
          authorId: '1',
          message: '<p>第1章 开始</p><p>这是第一段。</p><img data-src="https://img.test/novel-cover.jpg" />',
          number: 1,
          isFirst: true,
          dateline: '2026-05-03',
        ),
        ThreadPost(
          pid: '5002',
          author: '路人',
          authorId: '2',
          message: '<p>围观</p>',
          number: 2,
          isFirst: false,
          dateline: '2026-05-03',
        ),
        ThreadPost(
          pid: '5003',
          author: '楼主A',
          authorId: '1',
          message: '<p>第2章 继续</p><p>这是第二章。</p>',
          number: 3,
          isFirst: false,
          dateline: '2026-05-04',
        ),
      ],
    );
  }
}

