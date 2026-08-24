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
import 'package:y300/features/novel/domain/models/novel_thread_models.dart';
import 'package:y300/features/novel/domain/services/novel_episode_discovery_service.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

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

    test(
      'upsertNovelBySeed + refreshEpisodes builds readable shelf and episodes',
      () async {
        await repository.upsertNovelBySeed(
          seed: const NovelRefreshSeed(
            fid: '49',
            tid: '200',
            typeid: '293',
            tagName: '原创',
          ),
        );
        final result = await repository.refreshEpisodes(
          novelId: 'novel:49:200',
        );

        final shelf = await repository.getShelfItems();
        final episodes = await repository.getEpisodes(novelId: 'novel:49:200');
        final content = await repository.getChapterContent(
          episodeId: episodes.first.episodeId,
        );

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
      },
    );

    test('custom title and cover survive source refresh', () async {
      const novelId = 'novel:49:200';
      await repository.upsertNovelBySeed(
        seed: const NovelRefreshSeed(fid: '49', tid: '200'),
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

      await repository.refreshEpisodes(novelId: novelId);

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

      await repository.refreshEpisodes(novelId: novelId);
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
      await repository.upsertNovelBySeed(
        seed: const NovelRefreshSeed(fid: '55', tid: '300'),
      );
      await repository.refreshEpisodes(novelId: 'novel:55:300');
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
      await repository.upsertNovelBySeed(
        seed: const NovelRefreshSeed(fid: '49', tid: '200'),
      );
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
        await repository.upsertNovelBySeed(
          seed: const NovelRefreshSeed(fid: '49', tid: '200'),
        );
        await repository.refreshEpisodes(novelId: 'novel:49:200');
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
        await repository.upsertNovelBySeed(
          seed: const NovelRefreshSeed(fid: '49', tid: '200'),
        );
        await repository.upsertNovelBySeed(
          seed: const NovelRefreshSeed(fid: '55', tid: '300'),
        );
        await repository.refreshEpisodes(novelId: 'novel:49:200');
        await repository.refreshEpisodes(novelId: 'novel:55:300');

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
        await repository.upsertNovelBySeed(
          seed: const NovelRefreshSeed(fid: '49', tid: '200'),
        );
        await repository.refreshEpisodes(novelId: 'novel:49:200');
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

    test('refreshEpisodes removes stale parsed episode rows', () async {
      await repository.upsertNovelBySeed(
        seed: const NovelRefreshSeed(fid: '49', tid: '200'),
      );
      final db = await dbFuture;
      await db.insert(ComicLocalDb.workEpisodesTable, <String, Object?>{
        'episode_id': 'novel:49:200:stale-tid',
        'work_id': 'novel:49:200',
        'content_type': 'novel',
        'source_tid': '200',
        'source_pid': '200',
        'source_page': 1,
        'episode_title': '错误旧章节',
        'order_index': 99,
        'dateline_text': '',
      });
      await db.insert(ComicLocalDb.novelEpisodeContentTable, <String, Object?>{
        'episode_id': 'novel:49:200:stale-tid',
        'raw_html': '',
        'plain_text': '',
        'paragraph_json': '[]',
        'updated_at': 0,
      });

      await repository.refreshEpisodes(novelId: 'novel:49:200');

      final episodes = await repository.getEpisodes(novelId: 'novel:49:200');
      final staleContent = await repository.getChapterContent(
        episodeId: 'novel:49:200:stale-tid',
      );
      expect(
        episodes.map((episode) => episode.episodeId),
        isNot(contains('novel:49:200:stale-tid')),
      );
      expect(staleContent, isNull);
    });

    test(
      'upsertNovelBySeed strips leading brackets and decodes &amp; in title',
      () async {
        final dirtyRepo = LocalNovelRepository(
          dbFuture,
          threadGateway: _DirtyTitleGateway(),
          discoveryService: const NovelEpisodeDiscoveryService(),
        );

        await dirtyRepo.upsertNovelBySeed(
          seed: const NovelRefreshSeed(fid: '49', tid: '700'),
        );

        final detail = await dirtyRepo.getDetail(novelId: 'novel:49:700');
        expect(detail, isNotNull);
        expect(detail!.title, '一周一次买下同班同学的那些事 A & B');
      },
    );

    test(
      'refreshEpisodes auto-fills parsed intro when work state is empty',
      () async {
        final introRepo = LocalNovelRepository(
          dbFuture,
          threadGateway: _IntroGateway(),
          discoveryService: const NovelEpisodeDiscoveryService(),
        );
        await introRepo.upsertNovelBySeed(
          seed: const NovelRefreshSeed(fid: '49', tid: '800'),
        );
        await introRepo.refreshEpisodes(novelId: 'novel:49:800');

        final stateRepository = LocalLibraryStateRepository(dbFuture);
        final state = await stateRepository.getWorkState(
          moduleKey: LibraryModuleKey.novel,
          workId: 'novel:49:800',
        );
        expect(state, isNotNull);
        expect(state!.introText, isNotNull);
        expect(state.introText, contains('简介：本文讲述'));
        expect(state.introText, contains('感人的故事'));
        expect(state.introText, isNot(contains('目录')));
      },
    );

    test('refreshEpisodes does not overwrite user-edited intro', () async {
      final introRepo = LocalNovelRepository(
        dbFuture,
        threadGateway: _IntroGateway(),
        discoveryService: const NovelEpisodeDiscoveryService(),
      );
      await introRepo.upsertNovelBySeed(
        seed: const NovelRefreshSeed(fid: '49', tid: '800'),
      );

      final stateRepository = LocalLibraryStateRepository(dbFuture);
      await stateRepository.upsertWorkState(
        moduleKey: LibraryModuleKey.novel,
        workId: 'novel:49:800',
        introText: '我手动写的简介',
      );

      await introRepo.refreshEpisodes(novelId: 'novel:49:800');

      final state = await stateRepository.getWorkState(
        moduleKey: LibraryModuleKey.novel,
        workId: 'novel:49:800',
      );
      expect(state!.introText, '我手动写的简介');
    });

    test(
      'refreshEpisodes incremental refetches from last known page and merges new episodes',
      () async {
        final gateway = _IncrementalGateway();
        final incrementalRepo = LocalNovelRepository(
          dbFuture,
          threadGateway: gateway,
          discoveryService: const NovelEpisodeDiscoveryService(),
        );
        await incrementalRepo.upsertNovelBySeed(
          seed: const NovelRefreshSeed(fid: '49', tid: '900'),
        );
        // 第一轮 full：首版只有 page1+page2 各 1 章，page2 只有 1 楼以触发分页终止。
        await incrementalRepo.refreshEpisodes(novelId: 'novel:49:900');
        gateway.requestedPages.clear();
        gateway.advanceToWithExtraChapter();

        final result = await incrementalRepo.refreshEpisodes(
          novelId: 'novel:49:900',
          mode: NovelEpisodeRefreshMode.incremental,
        );

        // 起点 == 已知最大 source_page == 2；不会再请求 page=1。
        expect(gateway.requestedPages, isNot(contains(1)));
        expect(gateway.requestedPages, contains(2));
        expect(gateway.requestedPages, contains(3));
        expect(result.insertedCount, 1);
        final episodes = await incrementalRepo.getEpisodes(
          novelId: 'novel:49:900',
        );
        // page=1 的旧章节仍在；新章节追加在末尾。
        expect(episodes.length, 3);
        expect(
          episodes.map((episode) => episode.sourcePid),
          containsAllInOrder(<String>['9101', '9201', '9301']),
        );
        // 新章节 orderIndex 从 maxOrder + 1 开始。
        final newEpisode = episodes.firstWhere(
          (episode) => episode.sourcePid == '9301',
        );
        expect(newEpisode.orderIndex, 2);
      },
    );

    test('refreshEpisodes incremental updates title via sanitizer', () async {
      final gateway = _IncrementalGateway();
      final incrementalRepo = LocalNovelRepository(
        dbFuture,
        threadGateway: gateway,
        discoveryService: const NovelEpisodeDiscoveryService(),
      );
      await incrementalRepo.upsertNovelBySeed(
        seed: const NovelRefreshSeed(fid: '49', tid: '900'),
      );
      await incrementalRepo.refreshEpisodes(novelId: 'novel:49:900');
      final initial = await incrementalRepo.getDetail(novelId: 'novel:49:900');
      expect(initial!.title, '小说标题 6.20更新番外5');

      gateway.advanceTitleAndAddChapter();
      await incrementalRepo.refreshEpisodes(
        novelId: 'novel:49:900',
        mode: NovelEpisodeRefreshMode.incremental,
      );
      final after = await incrementalRepo.getDetail(novelId: 'novel:49:900');
      // sanitizer 把前导 `[搬运]` 剥掉、保留更新时间标记。
      expect(after!.title, '小说标题 7.1更新番外6');
    });

    test(
      'refreshEpisodes incremental falls back to full when no episodes exist',
      () async {
        final gateway = _IncrementalGateway();
        final incrementalRepo = LocalNovelRepository(
          dbFuture,
          threadGateway: gateway,
          discoveryService: const NovelEpisodeDiscoveryService(),
        );
        await incrementalRepo.upsertNovelBySeed(
          seed: const NovelRefreshSeed(fid: '49', tid: '900'),
        );
        gateway.requestedPages.clear();

        await incrementalRepo.refreshEpisodes(
          novelId: 'novel:49:900',
          mode: NovelEpisodeRefreshMode.incremental,
        );

        // 零章节 -> 内部降级到 full；必然请求 page=1。
        expect(gateway.requestedPages, contains(1));
      },
    );

    test(
      'refreshEpisodes incremental preserves catalog-derived titles when re-discovering episodes via rule chain',
      () async {
        // catalog 模式启发式 (page=1 上 ≥ 2 章节) 已经移除 —— 它在 ppp=200 的真实多页
        // 小说上几乎总命中，把所有正常增量都打回了 full。改用「锁定既有 episode_title」
        // 这个在写入路径上的硬约束兜底标题漂移：哪怕 rule 链给出了不一样的候选，DB 里
        // 的 catalog 标题也不会被覆盖。
        final gateway = _CatalogModeGateway();
        final catalogRepo = LocalNovelRepository(
          dbFuture,
          threadGateway: gateway,
          discoveryService: const NovelEpisodeDiscoveryService(),
        );
        await catalogRepo.upsertNovelBySeed(
          seed: const NovelRefreshSeed(fid: '49', tid: '901'),
        );
        await catalogRepo.refreshEpisodes(novelId: 'novel:49:901');
        // catalog 路径下，pid 9601 应该拿到目录链接文本「第3章 远方」作为标题。
        final beforeEpisodes = await catalogRepo.getEpisodes(
          novelId: 'novel:49:901',
        );
        final beforeChapter3 = beforeEpisodes.firstWhere(
          (e) => e.sourcePid == '9601',
        );
        expect(beforeChapter3.episodeTitle, '第3章 远方');

        gateway.requestedPages.clear();
        await catalogRepo.refreshEpisodes(
          novelId: 'novel:49:901',
          mode: NovelEpisodeRefreshMode.incremental,
        );

        // 不再降级：增量从 page=2 起拉，page=1 不会被请求。
        expect(gateway.requestedPages, isNot(contains(1)));
        expect(gateway.requestedPages, contains(2));
        // 关键不变量：rule 链对 9601 帖文规则化抽出的标题是「第3章」（去掉了「远方」），
        // 但既有章节的 episode_title 在写入时被锁定，DB 里的标题保持原样。
        final afterEpisodes = await catalogRepo.getEpisodes(
          novelId: 'novel:49:901',
        );
        final afterChapter3 = afterEpisodes.firstWhere(
          (e) => e.sourcePid == '9601',
        );
        expect(afterChapter3.episodeTitle, '第3章 远方');
      },
    );

    test(
      'refreshEpisodes incremental does not overwrite user-edited intro',
      () async {
        final gateway = _IncrementalGateway();
        final incrementalRepo = LocalNovelRepository(
          dbFuture,
          threadGateway: gateway,
          discoveryService: const NovelEpisodeDiscoveryService(),
        );
        await incrementalRepo.upsertNovelBySeed(
          seed: const NovelRefreshSeed(fid: '49', tid: '900'),
        );
        await incrementalRepo.refreshEpisodes(novelId: 'novel:49:900');

        final stateRepository = LocalLibraryStateRepository(dbFuture);
        await stateRepository.upsertWorkState(
          moduleKey: LibraryModuleKey.novel,
          workId: 'novel:49:900',
          introText: '我写的简介',
        );

        gateway.advanceToWithExtraChapter();
        await incrementalRepo.refreshEpisodes(
          novelId: 'novel:49:900',
          mode: NovelEpisodeRefreshMode.incremental,
        );

        final state = await stateRepository.getWorkState(
          moduleKey: LibraryModuleKey.novel,
          workId: 'novel:49:900',
        );
        // 增量分支根本不调 _maybeWriteParsedIntro —— 用户简介无需保护。
        expect(state!.introText, '我写的简介');
      },
    );
  });
}

class _DirtyTitleGateway implements LegacyNovelThreadGateway {
  @override
  Future<ThreadDetailData> getThreadDetail({
    required String tid,
    required int page,
  }) async {
    if (page > 1) {
      return ThreadDetailData(
        tid: tid,
        fid: '49',
        subject: '[个人翻译][长篇][羽田宇佐]一周一次买下同班同学的那些事 A &amp; B',
        author: '楼主A',
        replies: 0,
        views: 0,
        currentPage: page,
        perPage: 20,
        posts: const <ThreadPost>[],
      );
    }
    return ThreadDetailData(
      tid: tid,
      fid: '49',
      // 既验证前导括号剥离，也验证 &amp; 实体解码。
      subject: '[个人翻译][长篇][羽田宇佐]一周一次买下同班同学的那些事 A &amp; B',
      author: '楼主A',
      replies: 0,
      views: 0,
      currentPage: 1,
      perPage: 20,
      posts: <ThreadPost>[
        ThreadPost(
          pid: '7001',
          author: '楼主A',
          authorId: '1',
          message: '<p>第1章 开始</p><p>正文</p>',
          number: 1,
          isFirst: true,
          dateline: '2026-06-15',
        ),
      ],
    );
  }
}

class _IntroGateway implements LegacyNovelThreadGateway {
  @override
  Future<ThreadDetailData> getThreadDetail({
    required String tid,
    required int page,
  }) async {
    if (page > 1) {
      return ThreadDetailData(
        tid: tid,
        fid: '49',
        subject: '带简介的小说',
        author: '楼主A',
        replies: 0,
        views: 0,
        currentPage: page,
        perPage: 20,
        posts: const <ThreadPost>[],
      );
    }
    return ThreadDetailData(
      tid: tid,
      fid: '49',
      subject: '带简介的小说',
      author: '楼主A',
      replies: 0,
      views: 0,
      currentPage: 1,
      perPage: 20,
      posts: <ThreadPost>[
        ThreadPost(
          pid: '8001',
          author: '楼主A',
          authorId: '1',
          message:
              '<p>简介：本文讲述</p>'
              '<p>一段感人的故事。</p>'
              '<p>目录</p>'
              '<p>第1章 开始</p>',
          number: 1,
          isFirst: true,
          dateline: '2026-06-15',
        ),
        ThreadPost(
          pid: '8002',
          author: '楼主A',
          authorId: '1',
          message: '<p>第2章 继续</p><p>正文 B</p>',
          number: 2,
          isFirst: false,
          dateline: '2026-06-15',
        ),
      ],
    );
  }
}

class _FakeGateway implements LegacyNovelThreadGateway {
  @override
  Future<ThreadDetailData> getThreadDetail({
    required String tid,
    required int page,
  }) async {
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
          message:
              '<p>第1章 开始</p><p>这是第一段。</p><img data-src="https://img.test/novel-cover.jpg" />',
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

/// 多状态可推进的非 catalog 网关 —— 用来模拟「再发一次帖子，又出新章节」。
///
/// 第一次刷新（_baseline）：page1 (2 楼：1 楼 OP 章节 + 1 楼路人) + page2 (1 楼 OP 章节)；
/// `advanceToWithExtraChapter` 后：page2 仍有 1 楼，page3 新增 1 楼章节；
/// `advanceTitleAndAddChapter` 同时把 subject 换成新版本以验证 sanitizer 复跑。
class _IncrementalGateway implements LegacyNovelThreadGateway {
  final List<int> requestedPages = <int>[];
  String _subject = '[搬运] 小说标题 6.20更新番外5';
  bool _hasExtraChapter = false;

  void advanceToWithExtraChapter() {
    _hasExtraChapter = true;
  }

  void advanceTitleAndAddChapter() {
    _subject = '[搬运] 小说标题 7.1更新番外6';
    _hasExtraChapter = true;
  }

  @override
  Future<ThreadDetailData> getThreadDetail({
    required String tid,
    required int page,
  }) async {
    requestedPages.add(page);
    final perPage = 2;
    if (page == 1) {
      return ThreadDetailData(
        tid: tid,
        fid: '49',
        subject: _subject,
        author: '楼主A',
        replies: 4,
        views: 0,
        currentPage: 1,
        perPage: perPage,
        posts: <ThreadPost>[
          ThreadPost(
            pid: '9101',
            author: '楼主A',
            authorId: '1',
            message: '<p>第1章 序章</p><p>正文</p>',
            number: 1,
            isFirst: true,
            dateline: '2026-06-01',
          ),
          ThreadPost(
            pid: '9102',
            author: '路人',
            authorId: '2',
            message: '<p>沙发</p>',
            number: 2,
            isFirst: false,
            dateline: '2026-06-01',
          ),
        ],
      );
    }
    if (page == 2) {
      return ThreadDetailData(
        tid: tid,
        fid: '49',
        subject: _subject,
        author: '楼主A',
        replies: 4,
        views: 0,
        currentPage: 2,
        perPage: perPage,
        posts: <ThreadPost>[
          ThreadPost(
            pid: '9201',
            author: '楼主A',
            authorId: '1',
            message: '<p>第2章 继续</p><p>正文 B</p>',
            number: 3,
            isFirst: false,
            dateline: '2026-06-08',
          ),
          // 填充非楼主帖以避免 _fetchPages 的 posts.length < perPage 提前终止
          // —— 否则增量场景下 page=3 永远不会被拉取，看不到新增章节。
          ThreadPost(
            pid: '9202',
            author: '路人B',
            authorId: '3',
            message: '<p>催更</p>',
            number: 4,
            isFirst: false,
            dateline: '2026-06-08',
          ),
        ],
      );
    }
    if (page == 3 && _hasExtraChapter) {
      return ThreadDetailData(
        tid: tid,
        fid: '49',
        subject: _subject,
        author: '楼主A',
        replies: 4,
        views: 0,
        currentPage: 3,
        perPage: perPage,
        posts: <ThreadPost>[
          ThreadPost(
            pid: '9301',
            author: '楼主A',
            authorId: '1',
            message: '<p>第3章 新章节</p><p>新增正文</p>',
            number: 4,
            isFirst: false,
            dateline: '2026-06-15',
          ),
        ],
      );
    }
    // 越过末页：返回空 posts，触发 _fetchPages 终止。
    return ThreadDetailData(
      tid: tid,
      fid: '49',
      subject: _subject,
      author: '楼主A',
      replies: 4,
      views: 0,
      currentPage: page,
      perPage: perPage,
      posts: const <ThreadPost>[],
    );
  }
}

/// 模拟 catalog 模式：page=1 楼主帖子里有 ≥ 2 个跳到不同 pid 的目录链接，
/// 对应章节散落在多页。增量从 page=2 开始的话会丢失目录上下文，
/// 仓库要正确降级到 full。
class _CatalogModeGateway implements LegacyNovelThreadGateway {
  final List<int> requestedPages = <int>[];

  @override
  Future<ThreadDetailData> getThreadDetail({
    required String tid,
    required int page,
  }) async {
    requestedPages.add(page);
    if (page == 1) {
      return ThreadDetailData(
        tid: tid,
        fid: '49',
        subject: '[搬运] 目录小说',
        author: '楼主A',
        replies: 4,
        views: 0,
        currentPage: 1,
        perPage: 2,
        posts: <ThreadPost>[
          ThreadPost(
            pid: '9501',
            author: '楼主A',
            authorId: '1',
            message:
                '<p>目录</p>'
                '<p><a href="forum.php?mod=redirect&goto=findpost&ptid=$tid&pid=9501">'
                '第1章 序章</a></p>'
                '<p><a href="forum.php?mod=redirect&goto=findpost&ptid=$tid&pid=9502">'
                '第2章 继续</a></p>'
                '<p><a href="forum.php?mod=redirect&goto=findpost&ptid=$tid&pid=9601">'
                '第3章 远方</a></p>',
            number: 1,
            isFirst: true,
            dateline: '2026-06-01',
          ),
          ThreadPost(
            pid: '9502',
            author: '楼主A',
            authorId: '1',
            message: '<p>第2章 继续</p><p>正文 B</p>',
            number: 2,
            isFirst: false,
            dateline: '2026-06-01',
          ),
        ],
      );
    }
    if (page == 2) {
      return ThreadDetailData(
        tid: tid,
        fid: '49',
        subject: '[搬运] 目录小说',
        author: '楼主A',
        replies: 4,
        views: 0,
        currentPage: 2,
        perPage: 2,
        posts: <ThreadPost>[
          ThreadPost(
            pid: '9601',
            author: '楼主A',
            authorId: '1',
            message: '<p>第3章 远方</p><p>正文 C</p>',
            number: 3,
            isFirst: false,
            dateline: '2026-06-08',
          ),
        ],
      );
    }
    return ThreadDetailData(
      tid: tid,
      fid: '49',
      subject: '[搬运] 目录小说',
      author: '楼主A',
      replies: 4,
      views: 0,
      currentPage: page,
      perPage: 2,
      posts: const <ThreadPost>[],
    );
  }
}
