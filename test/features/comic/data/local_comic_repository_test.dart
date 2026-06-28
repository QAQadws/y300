import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/local_comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/library_shared/data/repositories/local_library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('LocalComicRepository', () {
    late LocalComicRepository repository;
    late Future<Database> dbFuture;

    setUp(() async {
      await deleteDatabase(ComicLocalDb.dbName);
      dbFuture = ComicLocalDb.open();
      repository = LocalComicRepository(dbFuture);
    });

    test('adds comic to shelf and can query shelf state', () async {
      await repository.addToShelf(
        comicId: 'yamibo:100',
        tid: '100',
        fid: '30',
        sourceTypeId: '398',
        sourceTagName: '韩国漫画',
        title: '测试漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/cover.jpg'],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '1', episodeTitle: '1'),
          ],
          plainTextSummary: '摘要',
          inferredAuthor: '作者A',
        ),
      );

      final inShelf = await repository.isInShelf(comicId: 'yamibo:100');
      final items = await repository.getShelfItems();

      expect(inShelf, isTrue);
      expect(items.length, 1);
      expect(items.first.title, '测试漫画');
      expect(items.first.sourceTypeId, '398');
      expect(items.first.sourceTagName, '韩国漫画');
      expect(items.first.author, '作者A');
      expect(items.first.coverImageUrl, 'https://img.test/cover.jpg');
    });

    test('addToShelf is idempotent for same comic', () async {
      const parsed = ParsedComicPost(
        imageUrls: <String>['https://img.test/cover.jpg'],
        episodeLinks: <ComicEpisodeLink>[],
        plainTextSummary: '摘要',
      );

      await repository.addToShelf(
        comicId: 'yamibo:100',
        tid: '100',
        fid: '30',
        title: '测试漫画',
        parsedPost: parsed,
      );

      await repository.addToShelf(
        comicId: 'yamibo:100',
        tid: '100',
        fid: '30',
        title: '测试漫画',
        parsedPost: parsed,
      );

      final items = await repository.getShelfItems();
      expect(items.length, 1);
    });

    test(
      'addToShelf 单帖漫画用 subject metadata 的 episodeLabel 作为话名',
      () async {
        await repository.addToShelf(
          comicId: 'yamibo:single-thread',
          tid: '300',
          fid: '30',
          title: '【某汉化组】一帖完结漫画 第3话',
          parsedPost: const ParsedComicPost(
            imageUrls: <String>[
              'https://img.test/single-thread-page-1.jpg',
              'https://img.test/single-thread-page-2.jpg',
            ],
            episodeLinks: <ComicEpisodeLink>[],
            plainTextSummary: '摘要',
            subjectMetadata: ComicSubjectMetadata(
              normalizedTitle: '一帖完结漫画',
              translationGroup: '某汉化组',
              episodeLabel: '第3话',
            ),
          ),
        );

        final episodes = await repository.getComicEpisodes(
          comicId: 'yamibo:single-thread',
          descending: false,
        );

        // 单帖漫画：唯一一话 + 命名取自标题分析器的 episodeLabel。
        expect(episodes, hasLength(1));
        expect(episodes.first.episodeTitle, '第3话');
        expect(episodes.first.sourceTid, '300');
      },
    );

    test(
      'addToShelf 单帖漫画无 episodeLabel 时回落到规范化书名',
      () async {
        await repository.addToShelf(
          comicId: 'yamibo:single-no-label',
          tid: '301',
          fid: '30',
          title: '【组A】整本就一话漫画',
          parsedPost: const ParsedComicPost(
            imageUrls: <String>['https://img.test/no-label.jpg'],
            episodeLinks: <ComicEpisodeLink>[],
            plainTextSummary: '摘要',
            subjectMetadata: ComicSubjectMetadata(
              normalizedTitle: '整本就一话漫画',
              translationGroup: '组A',
            ),
          ),
        );

        final episodes = await repository.getComicEpisodes(
          comicId: 'yamibo:single-no-label',
          descending: false,
        );

        expect(episodes, hasLength(1));
        expect(episodes.first.episodeTitle, '整本就一话漫画');
      },
    );

    test(
      'addToShelf 解析到 catalog 章节链接时不再种入"首楼"影子记录',
      () async {
        await repository.addToShelf(
          comicId: 'yamibo:catalog-only',
          tid: '400',
          fid: '30',
          title: '【某汉化组】目录贴漫画',
          parsedPost: const ParsedComicPost(
            // 即使 OP 里有横幅图，只要 catalog 链接非空就不该种入 source tid
            // 上的孤儿话——避免后续显示 sourceUrl 空、永远拉不到内容的章节。
            imageUrls: <String>['https://img.test/catalog-banner.jpg'],
            episodeLinks: <ComicEpisodeLink>[
              ComicEpisodeLink(
                url: 'thread-401-1-1.html',
                rawText: '第1话',
                episodeTitle: '第1话',
              ),
              ComicEpisodeLink(
                url: 'thread-402-1-1.html',
                rawText: '第2话',
                episodeTitle: '第2话',
              ),
            ],
            plainTextSummary: '摘要',
          ),
        );

        final episodes = await repository.getComicEpisodes(
          comicId: 'yamibo:catalog-only',
          descending: false,
        );

        expect(episodes, hasLength(2));
        expect(
          episodes.map((episode) => episode.episodeTitle).toList(),
          <String?>['第1话', '第2话'],
        );
        expect(episodes.any((episode) => episode.sourceTid == '400'), isFalse);
      },
    );

    test('removeFromShelf only removes shelf entry and keeps comic data', () async {
      await repository.addToShelf(
        comicId: 'yamibo:remove-only',
        tid: '150',
        fid: '30',
        title: '保留数据漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/remove-only-cover.jpg'],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(
              url: 'thread-151-1-1.html',
              rawText: '第1话',
              episodeTitle: '第1话',
            ),
          ],
          plainTextSummary: '摘要',
        ),
      );
      const episodeId = 'yamibo:remove-only:151';
      await repository.saveEpisodeImages(
        episodeId: episodeId,
        imageUrls: const <String>['https://img.test/remove-only-page-1.jpg'],
      );
      await repository.updateLastReadProgress(
        comicId: 'yamibo:remove-only',
        episodeId: episodeId,
        imageIndex: 0,
        scrollOffset: 18,
      );

      await repository.removeFromShelf(comicId: 'yamibo:remove-only');

      final inShelf = await repository.isInShelf(comicId: 'yamibo:remove-only');
      final shelfItems = await repository.getShelfItems();
      final detail = await repository.getComicDetail(comicId: 'yamibo:remove-only');
      final episodes = await repository.getComicEpisodes(
        comicId: 'yamibo:remove-only',
        descending: false,
      );
      final images = await repository.getEpisodeImages(episodeId: episodeId);
      final progress = await repository.getLastReadProgress(
        comicId: 'yamibo:remove-only',
      );

      expect(inShelf, isFalse);
      expect(shelfItems, isEmpty);
      expect(detail, isNotNull);
      // catalog 章节链接已抓到时不再种入 "首楼" 影子记录，
      // 详见 ComicSingleThreadEpisodeNamer 的语义说明。
      expect(episodes, hasLength(1));
      expect(
        episodes.map((episode) => episode.episodeTitle).toList(),
        <String?>['第1话'],
      );
      expect(images, hasLength(1));
      expect(progress, isNotNull);
      expect(progress?.episodeId, episodeId);
    });

    test('purgeWork deletes comic rows and cascaded episode data only for target comic', () async {
      await repository.addToShelf(
        comicId: 'yamibo:purge-a',
        tid: '160',
        fid: '30',
        title: '待清理漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/purge-a-cover.jpg'],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(
              url: 'thread-161-1-1.html',
              rawText: '第1话',
              episodeTitle: '第1话',
            ),
          ],
          plainTextSummary: '摘要',
        ),
      );
      await repository.addToShelf(
        comicId: 'yamibo:purge-b',
        tid: '260',
        fid: '30',
        title: '保留漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/purge-b-cover.jpg'],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(
              url: 'thread-261-1-1.html',
              rawText: '第1话',
              episodeTitle: '第1话',
            ),
          ],
          plainTextSummary: '摘要',
        ),
      );
      const purgeEpisodeId = 'yamibo:purge-a:161';
      await repository.saveEpisodeImages(
        episodeId: purgeEpisodeId,
        imageUrls: const <String>['https://img.test/purge-a-page-1.jpg'],
      );
      await repository.updateLastReadProgress(
        comicId: 'yamibo:purge-a',
        episodeId: purgeEpisodeId,
        imageIndex: 1,
        scrollOffset: 64,
      );

      await repository.purgeWork(comicId: 'yamibo:purge-a');

      final db = await dbFuture;
      final remainingDetail = await repository.getComicDetail(comicId: 'yamibo:purge-b');
      final remainingEpisodes = await repository.getComicEpisodes(
        comicId: 'yamibo:purge-b',
        descending: false,
      );
      final purgedProgress = await repository.getLastReadProgress(
        comicId: 'yamibo:purge-a',
      );

      expect(
        await db.query(
          ComicLocalDb.comicsTable,
          where: 'comic_id = ?',
          whereArgs: const <Object>['yamibo:purge-a'],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          ComicLocalDb.episodesTable,
          where: 'comic_id = ?',
          whereArgs: const <Object>['yamibo:purge-a'],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          ComicLocalDb.episodeImagesTable,
          where: 'episode_id = ?',
          whereArgs: const <Object>[purgeEpisodeId],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          ComicLocalDb.shelfItemsTable,
          where: 'comic_id = ?',
          whereArgs: const <Object>['yamibo:purge-a'],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          ComicLocalDb.readingProgressTable,
          where: 'comic_id = ?',
          whereArgs: const <Object>['yamibo:purge-a'],
        ),
        isEmpty,
      );
      expect(purgedProgress, isNull);
      expect(remainingDetail, isNotNull);
      expect(remainingEpisodes, hasLength(1));
      expect(
        remainingEpisodes.map((episode) => episode.episodeTitle).toList(),
        <String?>['第1话'],
      );
      expect(
        await db.query(
          ComicLocalDb.comicsTable,
          where: 'comic_id = ?',
          whereArgs: const <Object>['yamibo:purge-b'],
        ),
        isNotEmpty,
      );
    });

    test('addToShelf prefers normalized title and subject-derived author metadata', () async {
      await repository.addToShelf(
        comicId: 'yamibo:200',
        tid: '200',
        fid: '30',
        title: '【某汉化组】[作者X]作品名 12',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/cover-2.jpg'],
          episodeLinks: <ComicEpisodeLink>[],
          plainTextSummary: '摘要',
          inferredAuthor: '内容作者Y',
          subjectMetadata: ComicSubjectMetadata(
            normalizedTitle: '作品名',
            translationGroup: '某汉化组',
            inferredAuthor: '作者X',
            episodeLabel: '12',
          ),
        ),
      );

      final detail = await repository.getComicDetail(comicId: 'yamibo:200');
      expect(detail, isNotNull);
      expect(detail!.title, '作品名');
      expect(detail.author, '作者X');
      expect(detail.translationGroup, '某汉化组');
    });

    test('can create category and move comic across categories', () async {
      await repository.addToShelf(
        comicId: 'yamibo:100',
        tid: '100',
        fid: '30',
        title: '测试漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/cover.jpg'],
          episodeLinks: <ComicEpisodeLink>[],
          plainTextSummary: '摘要',
        ),
      );

      final categoryId = await repository.createCategory(name: '追更');
      await repository.moveComicToCategory(
        comicId: 'yamibo:100',
        fromCategoryId: 'default',
        toCategoryId: categoryId,
      );

      final defaultItems = await repository.getShelfItems(categoryId: 'default');
      final customItems = await repository.getShelfItems(categoryId: categoryId);

      expect(defaultItems, isEmpty);
      expect(customItems.length, 1);
      expect(customItems.first.comicId, 'yamibo:100');
    });

    test('deleting category moves comics back to default', () async {
      await repository.addToShelf(
        comicId: 'yamibo:100',
        tid: '100',
        fid: '30',
        title: '测试漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/cover.jpg'],
          episodeLinks: <ComicEpisodeLink>[],
          plainTextSummary: '摘要',
        ),
      );

      final categoryId = await repository.createCategory(name: '归档');
      await repository.moveComicToCategory(
        comicId: 'yamibo:100',
        fromCategoryId: 'default',
        toCategoryId: categoryId,
      );
      await repository.deleteCategory(categoryId: categoryId);

      final defaultItems = await repository.getShelfItems(categoryId: 'default');
      expect(defaultItems.length, 1);
      expect(defaultItems.first.comicId, 'yamibo:100');
    });

    test('can update custom cover and display settings', () async {
      await repository.addToShelf(
        comicId: 'yamibo:100',
        tid: '100',
        fid: '30',
        title: '测试漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/original.jpg'],
          episodeLinks: <ComicEpisodeLink>[],
          plainTextSummary: '摘要',
        ),
      );

      await repository.updateCustomCover(
        comicId: 'yamibo:100',
        customCoverImageUrl: 'https://img.test/custom.jpg',
      );

      await repository.updateGridColumnCount(columnCount: 4);

      final items = await repository.getShelfItems();
      final settings = await repository.getDisplaySettings();

      expect(items.first.coverImageUrl, 'https://img.test/custom.jpg');
      expect(items.first.customCoverImageUrl, 'https://img.test/custom.jpg');
      expect(settings.gridColumnCount, 4);
    });

    test('updating custom cover clears stale custom local path', () async {
      await repository.addToShelf(
        comicId: 'yamibo:101',
        tid: '101',
        fid: '30',
        title: '测试漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/original.jpg'],
          episodeLinks: <ComicEpisodeLink>[],
          plainTextSummary: '摘要',
        ),
      );

      await repository.updateCustomCover(
        comicId: 'yamibo:101',
        customCoverImageUrl: 'https://img.test/custom-a.jpg',
      );
      await repository.updateCoverCache(
        comicId: 'yamibo:101',
        customCoverLocalPath: '/cache/custom-a.jpg',
      );
      await repository.updateCustomCover(
        comicId: 'yamibo:101',
        customCoverImageUrl: 'https://img.test/custom-b.jpg',
      );

      final detail = await repository.getComicDetail(comicId: 'yamibo:101');
      expect(detail?.coverImageUrl, 'https://img.test/custom-b.jpg');
      expect(detail?.customCoverImageUrl, 'https://img.test/custom-b.jpg');
      expect(detail?.customCoverLocalPath, isNull);
    });

    test('custom metadata overrides display and can be cleared to source values', () async {
      await repository.addToShelf(
        comicId: 'yamibo:102',
        tid: '102',
        fid: '30',
        title: '【源组】[源作者]来源标题 第1话',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/original.jpg'],
          episodeLinks: <ComicEpisodeLink>[],
          plainTextSummary: '摘要',
          subjectMetadata: ComicSubjectMetadata(
            normalizedTitle: '来源标题',
            translationGroup: '源组',
            inferredAuthor: '源作者',
          ),
        ),
      );

      await repository.updateCustomMetadata(
        comicId: 'yamibo:102',
        customTitle: '自定义标题',
        customAuthor: '自定义作者',
        customTranslationGroup: '自定义组',
        customSearchTitle: '搜索关键词',
      );

      var detail = await repository.getComicDetail(comicId: 'yamibo:102');
      var items = await repository.getShelfItems();
      expect(detail?.title, '自定义标题');
      expect(detail?.sourceTitle, '来源标题');
      expect(detail?.customTitle, '自定义标题');
      expect(detail?.author, '自定义作者');
      expect(detail?.translationGroup, '自定义组');
      expect(detail?.customSearchTitle, '搜索关键词');
      expect(items.single.title, '自定义标题');
      expect(items.single.translationGroup, '自定义组');

      await repository.clearCustomMetadata(
        comicId: 'yamibo:102',
        title: true,
        author: true,
        translationGroup: true,
        searchTitle: true,
      );

      detail = await repository.getComicDetail(comicId: 'yamibo:102');
      items = await repository.getShelfItems();
      expect(detail?.title, '来源标题');
      expect(detail?.customTitle, isNull);
      expect(detail?.author, '源作者');
      expect(detail?.translationGroup, '源组');
      expect(detail?.customSearchTitle, isNull);
      expect(items.single.title, '来源标题');
    });

    test('refreshing source metadata keeps custom metadata and display values', () async {
      const firstPost = ParsedComicPost(
        imageUrls: <String>['https://img.test/original.jpg'],
        episodeLinks: <ComicEpisodeLink>[],
        plainTextSummary: '摘要',
        subjectMetadata: ComicSubjectMetadata(
          normalizedTitle: '旧来源',
          translationGroup: '旧组',
          inferredAuthor: '旧作者',
        ),
      );
      await repository.addToShelf(
        comicId: 'yamibo:103',
        tid: '103',
        fid: '30',
        title: '旧来源',
        parsedPost: firstPost,
      );
      await repository.updateCustomMetadata(
        comicId: 'yamibo:103',
        customTitle: '自定义标题',
        customAuthor: '自定义作者',
        customTranslationGroup: '自定义组',
        customSearchTitle: '自定义搜索',
      );

      await repository.addToShelf(
        comicId: 'yamibo:103',
        tid: '103',
        fid: '30',
        title: '新来源',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/new.jpg'],
          episodeLinks: <ComicEpisodeLink>[],
          plainTextSummary: '摘要',
          subjectMetadata: ComicSubjectMetadata(
            normalizedTitle: '新来源',
            translationGroup: '新组',
            inferredAuthor: '新作者',
          ),
        ),
      );

      final detail = await repository.getComicDetail(comicId: 'yamibo:103');
      expect(detail?.sourceTitle, '新来源');
      expect(detail?.title, '自定义标题');
      expect(detail?.sourceAuthor, '新作者');
      expect(detail?.author, '自定义作者');
      expect(detail?.sourceTranslationGroup, '新组');
      expect(detail?.translationGroup, '自定义组');
      expect(detail?.customSearchTitle, '自定义搜索');
    });

    test('can query comic detail and episodes descending', () async {
      await repository.addToShelf(
        comicId: 'yamibo:100',
        tid: '100',
        fid: '30',
        title: '【测试汉化组】[作者A]测试漫画 第1话',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/cover.jpg'],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '1', episodeTitle: '第1话'),
            ComicEpisodeLink(url: 'thread-102-1-1.html', rawText: '2', episodeTitle: '第2话'),
          ],
          plainTextSummary: '摘要',
          inferredAuthor: '作者A',
          subjectMetadata: ComicSubjectMetadata(
            normalizedTitle: '测试漫画',
            translationGroup: '测试汉化组',
            inferredAuthor: '作者A',
            episodeLabel: '第1话',
          ),
        ),
      );

      final detail = await repository.getComicDetail(comicId: 'yamibo:100');
      final episodes = await repository.getComicEpisodes(comicId: 'yamibo:100', descending: true);

      expect(detail, isNotNull);
      expect(detail!.title, '测试漫画');
      expect(detail.translationGroup, '测试汉化组');
      expect(detail.author, '作者A');
      expect(detail.episodeCount, greaterThanOrEqualTo(2));
      expect(episodes.first.episodeTitle, contains('2'));
    });

    test('mergeEpisodesFromLinks can insert and update episodes', () async {
      await repository.addToShelf(
        comicId: 'yamibo:100',
        tid: '100',
        fid: '30',
        title: '测试漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/cover.jpg'],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '1', episodeTitle: '1'),
          ],
          plainTextSummary: '摘要',
        ),
      );

      final result = await repository.mergeEpisodesFromLinks(
        comicId: 'yamibo:100',
        fallbackSourceTid: '100',
        episodeLinks: const <ComicEpisodeLink>[
          ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '1', episodeTitle: '第1话-修订'),
          ComicEpisodeLink(url: 'thread-102-1-1.html', rawText: '2', episodeTitle: '第2话'),
        ],
      );

      final episodes = await repository.getComicEpisodes(comicId: 'yamibo:100', descending: false);
      expect(result.insertedCount, 1);
      expect(result.updatedCount, 1);
      expect(result.totalCount, episodes.length);
      expect(episodes.any((e) => e.episodeTitle == '第1话-修订'), isTrue);
    });

    test('mergeEpisodesFromLinks updates same tid title without losing read state', () async {
      await repository.addToShelf(
        comicId: 'yamibo:110',
        tid: '110',
        fid: '30',
        title: '测试漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>[],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-111-1-1.html', rawText: '1', episodeTitle: '第1话'),
          ],
          plainTextSummary: '摘要',
        ),
      );
      final stateRepository = LocalLibraryStateRepository(dbFuture);
      await stateRepository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: 'yamibo:110:111',
        workId: 'yamibo:110',
        isRead: true,
      );

      final result = await repository.mergeEpisodesFromLinks(
        comicId: 'yamibo:110',
        fallbackSourceTid: '110',
        episodeLinks: const <ComicEpisodeLink>[
          ComicEpisodeLink(
            url: 'thread-111-1-1.html',
            rawText: '第1话 完整标题',
            episodeTitle: '第1话 完整标题',
          ),
        ],
      );

      final episodes = await repository.getComicEpisodes(
        comicId: 'yamibo:110',
        descending: false,
      );
      final snapshot = await repository.queryShelfSnapshot(
        filters: LibraryFilterSet.defaults,
        sortOption: LibraryShelfSortOption.defaults,
        keyword: '',
      );
      final item = snapshot.itemsByCategory['default']!.single;

      expect(result.insertedCount, 0);
      expect(result.updatedCount, 1);
      expect(episodes, hasLength(1));
      expect(episodes.single.episodeTitle, '第1话 完整标题');
      expect(item.readChapterCount, 1);
      expect(item.unreadCount, 0);
    });

    test('queryShelfSnapshot aggregates episode state and tags', () async {
      await repository.addToShelf(
        comicId: 'yamibo:900',
        tid: '900',
        fid: '30',
        title: '聚合漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>[],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-901-1-1.html', rawText: '1', episodeTitle: '第1话'),
            ComicEpisodeLink(url: 'thread-902-1-1.html', rawText: '2', episodeTitle: '第2话'),
          ],
          plainTextSummary: '摘要',
          inferredAuthor: '作者S',
        ),
      );
      final stateRepository = LocalLibraryStateRepository(dbFuture);
      await stateRepository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: 'yamibo:900:901',
        workId: 'yamibo:900',
        isRead: false,
        isDownloaded: true,
      );
      await stateRepository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: 'yamibo:900:902',
        workId: 'yamibo:900',
        isRead: true,
      );
      final tagId = await stateRepository.createTag(name: '追更');
      await stateRepository.bindTagToWork(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:900',
        tagId: tagId,
      );

      final snapshot = await repository.queryShelfSnapshot(
        filters: LibraryFilterSet.defaults,
        sortOption: LibraryShelfSortOption.defaults,
        keyword: '',
      );
      final item = snapshot.itemsByCategory['default']!.single;

      expect(snapshot.categories.single.categoryId, 'default');
      expect(snapshot.visibleMatchCountByCategory['default'], 1);
      expect(item.title, '聚合漫画');
      expect(item.unreadCount, 1);
      expect(item.readChapterCount, 1);
      expect(item.totalChapterCount, greaterThanOrEqualTo(2));
      expect(item.isDownloaded, isTrue);
      expect(item.hasTags, isTrue);
    });

    test('queryShelfSnapshot treats episodes without state rows as unread', () async {
      await repository.addToShelf(
        comicId: 'yamibo:910',
        tid: '910',
        fid: '30',
        title: '无状态漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>[],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-911-1-1.html', rawText: '1', episodeTitle: '第1话'),
            ComicEpisodeLink(url: 'thread-912-1-1.html', rawText: '2', episodeTitle: '第2话'),
            ComicEpisodeLink(url: 'thread-913-1-1.html', rawText: '3', episodeTitle: '第3话'),
          ],
          plainTextSummary: '摘要',
        ),
      );

      final stateRepository = LocalLibraryStateRepository(dbFuture);
      await stateRepository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: 'yamibo:910:911',
        workId: 'yamibo:910',
        isRead: true,
      );

      final snapshot = await repository.queryShelfSnapshot(
        filters: LibraryFilterSet.defaults,
        sortOption: LibraryShelfSortOption.defaults,
        keyword: '',
      );
      final item = snapshot.itemsByCategory['default']!.single;

      expect(item.totalChapterCount, 3);
      expect(item.readChapterCount, 1);
      expect(item.unreadCount, 2);
    });

    test('queryShelfSnapshot unread filter includes works with missing episode state', () async {
      await repository.addToShelf(
        comicId: 'yamibo:920',
        tid: '920',
        fid: '30',
        title: '未初始化未读',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>[],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-921-1-1.html', rawText: '1', episodeTitle: '第1话'),
          ],
          plainTextSummary: '摘要',
        ),
      );

      final snapshot = await repository.queryShelfSnapshot(
        filters: const LibraryFilterSet(unread: TriStateFilterValue.include),
        sortOption: LibraryShelfSortOption.defaults,
        keyword: '',
      );

      expect(snapshot.itemsByCategory['default']!.single.workId, 'yamibo:920');
      expect(snapshot.itemsByCategory['default']!.single.unreadCount, 1);
    });

    test('can persist reading progress and image cache status', () async {
      await repository.addToShelf(
        comicId: 'yamibo:100',
        tid: '100',
        fid: '30',
        title: '测试漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/1.jpg'],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '1', episodeTitle: '第1话'),
          ],
          plainTextSummary: '摘要',
        ),
      );

      const episodeId = 'yamibo:100:101';
      await repository.saveEpisodeImages(
        episodeId: episodeId,
        imageUrls: const <String>[
          'https://img.test/101-1.jpg',
          'https://img.test/101-2.jpg',
        ],
      );
      await repository.updateEpisodeImageCacheStatus(
        episodeId: episodeId,
        imageUrl: 'https://img.test/101-1.jpg',
        cacheStatus: 'done',
        cacheLocalPath: '/tmp/101-1.jpg',
      );
      await repository.updateLastReadProgress(
        comicId: 'yamibo:100',
        episodeId: episodeId,
        imageIndex: 1,
        scrollOffset: 222.5,
      );

      final images = await repository.getEpisodeImages(episodeId: episodeId);
      final progress = await repository.getLastReadProgress(comicId: 'yamibo:100');

      expect(images.length, 2);
      expect(images.first.cacheStatus, 'done');
      expect(images.first.cacheLocalPath, '/tmp/101-1.jpg');
      expect(progress, isNotNull);
      expect(progress!.episodeId, episodeId);
      expect(progress.imageIndex, 1);
      expect(progress.scrollOffset, 222.5);
    });

    test('saveEpisodeImages promotes smallest tid first image as initial cover', () async {
      await repository.addToShelf(
        comicId: 'yamibo:700',
        tid: '700',
        fid: '30',
        title: '测试漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>[],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-701-1-1.html', rawText: '后话', episodeTitle: '后话'),
            ComicEpisodeLink(url: 'thread-699-1-1.html', rawText: '首话', episodeTitle: '首话'),
          ],
          plainTextSummary: '摘要',
        ),
      );

      await repository.saveEpisodeImages(
        episodeId: 'yamibo:700:701',
        imageUrls: const <String>['https://img.test/701-1.jpg'],
      );
      var detail = await repository.getComicDetail(comicId: 'yamibo:700');
      expect(detail?.coverImageUrl, isNull);

      await repository.saveEpisodeImages(
        episodeId: 'yamibo:700:699',
        imageUrls: const <String>['https://img.test/699-1.jpg'],
      );
      detail = await repository.getComicDetail(comicId: 'yamibo:700');

      expect(detail?.coverImageUrl, 'https://img.test/699-1.jpg');
    });

    test('saveEpisodeImages corrects parsed first-floor cover to smallest tid image', () async {
      await repository.addToShelf(
        comicId: 'yamibo:701',
        tid: '701',
        fid: '30',
        title: '测试漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/first-floor.jpg'],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-702-1-1.html', rawText: '后话', episodeTitle: '后话'),
            ComicEpisodeLink(url: 'thread-700-1-1.html', rawText: '首话', episodeTitle: '首话'),
          ],
          plainTextSummary: '摘要',
        ),
      );

      await repository.saveEpisodeImages(
        episodeId: 'yamibo:701:700',
        imageUrls: const <String>['https://img.test/700-1.jpg'],
      );

      final detail = await repository.getComicDetail(comicId: 'yamibo:701');
      expect(detail?.coverImageUrl, 'https://img.test/700-1.jpg');
    });

    test('mergeEpisodesFromLinks extracts tid from viewthread links and keeps unique episodes', () async {
      await repository.addToShelf(
        comicId: 'yamibo:300',
        tid: '300',
        fid: '30',
        title: '测试漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>[],
          episodeLinks: <ComicEpisodeLink>[],
          plainTextSummary: '摘要',
        ),
      );

      await repository.mergeEpisodesFromLinks(
        comicId: 'yamibo:300',
        fallbackSourceTid: '300',
        episodeLinks: const <ComicEpisodeLink>[
          ComicEpisodeLink(
            url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=530646&highlight=a',
            rawText: '01',
            episodeTitle: '01',
          ),
          ComicEpisodeLink(
            url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=533029&highlight=a',
            rawText: '02',
            episodeTitle: '02',
          ),
          ComicEpisodeLink(
            url: 'https://bbs.yamibo.com/forum.php?mod=viewthread&tid=533956&highlight=a',
            rawText: '03',
            episodeTitle: '03',
          ),
        ],
      );

      final episodes = await repository.getComicEpisodes(
        comicId: 'yamibo:300',
        descending: false,
      );

      expect(episodes.length, 3);
      expect(episodes.map((e) => e.sourceTid).toList(), <String>['530646', '533029', '533956']);
    });

    test('detail order uses reverse of message order when reading with descending=true', () async {
      await repository.addToShelf(
        comicId: 'yamibo:400',
        tid: '400',
        fid: '30',
        title: '测试漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>[],
          episodeLinks: <ComicEpisodeLink>[],
          plainTextSummary: '摘要',
        ),
      );

      await repository.mergeEpisodesFromLinks(
        comicId: 'yamibo:400',
        fallbackSourceTid: '400',
        episodeLinks: const <ComicEpisodeLink>[
          ComicEpisodeLink(url: 'thread-4001-1-1.html', rawText: '01', episodeTitle: '01'),
          ComicEpisodeLink(url: 'thread-4002-1-1.html', rawText: '02', episodeTitle: '02'),
          ComicEpisodeLink(url: 'thread-4003-1-1.html', rawText: '特典', episodeTitle: '特典'),
          ComicEpisodeLink(url: 'thread-4004-1-1.html', rawText: '03', episodeTitle: '03'),
        ],
      );

      final episodes = await repository.getComicEpisodes(
        comicId: 'yamibo:400',
        descending: true,
      );

      expect(
        episodes.map((e) => e.episodeTitle).toList(),
        <String?>['03', '特典', '02', '01'],
      );
    });

    test('detail descending order keeps specials interleaved by message order', () async {
      await repository.addToShelf(
        comicId: 'yamibo:500',
        tid: '500',
        fid: '30',
        title: '测试漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>[],
          episodeLinks: <ComicEpisodeLink>[],
          plainTextSummary: '摘要',
        ),
      );

      await repository.mergeEpisodesFromLinks(
        comicId: 'yamibo:500',
        fallbackSourceTid: '500',
        episodeLinks: const <ComicEpisodeLink>[
          ComicEpisodeLink(url: 'thread-5001-1-1.html', rawText: '09', episodeTitle: '09'),
          ComicEpisodeLink(url: 'thread-5002-1-1.html', rawText: '第一卷特典', episodeTitle: '第一卷特典'),
          ComicEpisodeLink(url: 'thread-5003-1-1.html', rawText: '10', episodeTitle: '10'),
          ComicEpisodeLink(url: 'thread-5004-1-1.html', rawText: '11', episodeTitle: '11'),
          ComicEpisodeLink(url: 'thread-5005-1-1.html', rawText: '第二卷特典', episodeTitle: '第二卷特典'),
          ComicEpisodeLink(url: 'thread-5006-1-1.html', rawText: '12', episodeTitle: '12'),
        ],
      );

      final episodes = await repository.getComicEpisodes(
        comicId: 'yamibo:500',
        descending: true,
      );

      expect(
        episodes.map((e) => e.episodeTitle).toList(),
        <String?>['12', '第二卷特典', '11', '10', '第一卷特典', '09'],
      );
    });

    test('mergeEpisodesFromLinks normalizes long subject to parsed episode label', () async {
      await repository.addToShelf(
        comicId: 'yamibo:600',
        tid: '600',
        fid: '30',
        title: '测试漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>[],
          episodeLinks: <ComicEpisodeLink>[],
          plainTextSummary: '摘要',
        ),
      );

      await repository.mergeEpisodesFromLinks(
        comicId: 'yamibo:600',
        fallbackSourceTid: '600',
        episodeLinks: const <ComicEpisodeLink>[
          ComicEpisodeLink(
            url: 'thread-558227-1-1.html',
            rawText: '【萌木汉化组】[ななつ藤][貴女へささげるサディスティック]献予你的支配之礼 第1.1话',
            episodeTitle: '【萌木汉化组】[ななつ藤][貴女へささげるサディスティック]献予你的支配之礼 第1.1话',
          ),
        ],
      );

      final episodes = await repository.getComicEpisodes(
        comicId: 'yamibo:600',
        descending: false,
      );
      expect(episodes.length, 1);
      expect(episodes.first.episodeTitle, '第1.1话');
    });

    test('clearEpisodeImageCache resets unprotected cache metadata', () async {
      await repository.addToShelf(
        comicId: 'yamibo:clear-cache',
        tid: '800',
        fid: '30',
        title: '清理缓存漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/clear-cover.jpg'],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(
              url: 'thread-801-1-1.html',
              rawText: '第1话',
              episodeTitle: '第1话',
            ),
          ],
          plainTextSummary: '摘要',
        ),
      );
      final episodes = await repository.getComicEpisodes(
        comicId: 'yamibo:clear-cache',
        descending: false,
      );
      final episodeId = episodes.first.episodeId;
      await repository.saveEpisodeImages(
        episodeId: episodeId,
        imageUrls: const <String>['https://img.test/page-1.jpg'],
      );
      await repository.updateEpisodeImageCacheStatus(
        episodeId: episodeId,
        imageUrl: 'https://img.test/page-1.jpg',
        cacheStatus: 'done',
        cacheLocalPath: '/cache/page-1.jpg',
      );

      await repository.clearEpisodeImageCache(episodeId: episodeId);

      final images = await repository.getEpisodeImages(episodeId: episodeId);
      expect(images.single.cacheStatus, 'none');
      expect(images.single.effectiveLocalPath, isNull);
    });

    test('updateEpisodeImageCacheMetadata persists decoded image dimensions', () async {
      await repository.addToShelf(
        comicId: 'yamibo:image-size',
        tid: '810',
        fid: '30',
        title: '图片尺寸漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/size-cover.jpg'],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(
              url: 'thread-811-1-1.html',
              rawText: '第1话',
              episodeTitle: '第1话',
            ),
          ],
          plainTextSummary: '摘要',
        ),
      );
      final episodes = await repository.getComicEpisodes(
        comicId: 'yamibo:image-size',
        descending: false,
      );
      final episodeId = episodes.first.episodeId;
      await repository.saveEpisodeImages(
        episodeId: episodeId,
        imageUrls: const <String>['https://img.test/size-page-1.jpg'],
      );

      await repository.updateEpisodeImageCacheMetadata(
        episodeId: episodeId,
        imageUrl: 'https://img.test/size-page-1.jpg',
        width: 900,
        height: 1800,
      );

      final images = await repository.getEpisodeImages(episodeId: episodeId);
      expect(images.single.width, 900);
      expect(images.single.height, 1800);
    });

    test('failed image cache status clears persisted local path', () async {
      await repository.addToShelf(
        comicId: 'yamibo:failed-local-path',
        tid: '820',
        fid: '30',
        title: '失败缓存漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/failed-cover.jpg'],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(
              url: 'thread-821-1-1.html',
              rawText: '第1话',
              episodeTitle: '第1话',
            ),
          ],
          plainTextSummary: '摘要',
        ),
      );
      final episodes = await repository.getComicEpisodes(
        comicId: 'yamibo:failed-local-path',
        descending: false,
      );
      final episodeId = episodes.first.episodeId;
      await repository.saveEpisodeImages(
        episodeId: episodeId,
        imageUrls: const <String>['https://img.test/failed-page-1.jpg'],
      );
      await repository.updateEpisodeImageCacheMetadata(
        episodeId: episodeId,
        imageUrl: 'https://img.test/failed-page-1.jpg',
        localPath: '/cache/failed-page-1.jpg',
      );

      await repository.updateEpisodeImageCacheStatus(
        episodeId: episodeId,
        imageUrl: 'https://img.test/failed-page-1.jpg',
        cacheStatus: 'failed',
      );

      final images = await repository.getEpisodeImages(episodeId: episodeId);
      expect(images.single.cacheStatus, 'failed');
      expect(images.single.effectiveLocalPath, isNull);
    });

    test('mergeDuplicateGroup keeps shortest title and merges unique episodes', () async {
      await repository.addToShelf(
        comicId: 'yamibo:1000',
        tid: '1000',
        fid: '30',
        title: '很长的重复漫画标题',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>[],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-1001-1-1.html', rawText: '1', episodeTitle: '第1话'),
            ComicEpisodeLink(url: 'thread-1002-1-1.html', rawText: '2', episodeTitle: '第2话'),
          ],
          plainTextSummary: '摘要',
        ),
      );
      await repository.addToShelf(
        comicId: 'yamibo:2000',
        tid: '2000',
        fid: '30',
        title: '短标题',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>[],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-1002-1-1.html', rawText: '2', episodeTitle: '第二话完整标题'),
            ComicEpisodeLink(url: 'thread-1003-1-1.html', rawText: '3', episodeTitle: '第3话'),
          ],
          plainTextSummary: '摘要',
        ),
      );

      final groups = await repository.findDuplicateGroups();
      final result = await repository.mergeDuplicateGroup(
        comicIds: groups.single.comicIds,
      );

      final detail = await repository.getComicDetail(comicId: result.targetComicId);
      final removedDetail = await repository.getComicDetail(
        comicId: result.mergedComicIds.single,
      );
      final episodes = await repository.getComicEpisodes(
        comicId: result.targetComicId,
        descending: false,
      );
      final shelfItems = await repository.getShelfItems();

      expect(result.changed, isTrue);
      expect(result.targetComicId, 'yamibo:2000');
      expect(result.targetTitle, '短标题');
      expect(detail?.title, '短标题');
      expect(removedDetail, isNull);
      expect(episodes.map((episode) => episode.sourceTid).toList(), <String>[
        '1001',
        '1002',
        '1003',
      ]);
      expect(shelfItems.map((item) => item.comicId).toSet(), <String>{'yamibo:2000'});
    });

    test('mergeDuplicateGroup moves reading state tags and favorite work id safely', () async {
      await repository.addToShelf(
        comicId: 'yamibo:source',
        tid: '3000',
        fid: '30',
        title: '来源重复漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>[],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-3001-1-1.html', rawText: '1', episodeTitle: '第1话'),
          ],
          plainTextSummary: '摘要',
        ),
      );
      await repository.addToShelf(
        comicId: 'yamibo:target',
        tid: '4000',
        fid: '30',
        title: '短',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>[],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-3001-1-1.html', rawText: '1', episodeTitle: '第1话'),
          ],
          plainTextSummary: '摘要',
        ),
      );
      final stateRepository = LocalLibraryStateRepository(dbFuture);
      await stateRepository.upsertEpisodeState(
        moduleKey: LibraryModuleKey.comic,
        episodeId: 'yamibo:source:3001',
        workId: 'yamibo:source',
        isRead: true,
        isDownloaded: true,
      );
      final tagId = await stateRepository.createTag(name: '重复');
      await stateRepository.bindTagToWork(
        moduleKey: LibraryModuleKey.comic,
        workId: 'yamibo:source',
        tagId: tagId,
      );
      await repository.updateLastReadProgress(
        comicId: 'yamibo:source',
        episodeId: 'yamibo:source:3001',
        imageIndex: 2,
        scrollOffset: 42,
      );
      final db = await dbFuture;
      await db.insert(
        ComicLocalDb.favoriteThreadsTable,
        <String, Object?>{
          'tid': '3000',
          'title': '来源重复漫画',
          'content_kind': 'comic',
          'work_id': 'yamibo:source',
          'first_seen_at': 1,
          'last_seen_at': 1,
        },
      );

      final result = await repository.mergeDuplicateGroup(
        comicIds: const <String>{'yamibo:source', 'yamibo:target'},
      );

      final snapshot = await repository.queryShelfSnapshot(
        filters: LibraryFilterSet.defaults,
        sortOption: LibraryShelfSortOption.defaults,
        keyword: '',
      );
      final item = snapshot.itemsByCategory['default']!.single;
      final progress = await repository.getLastReadProgress(comicId: result.targetComicId);
      final favoriteRows = await db.query(
        ComicLocalDb.favoriteThreadsTable,
        columns: const <String>['work_id'],
        where: 'tid = ?',
        whereArgs: <Object>['3000'],
      );

      expect(result.targetComicId, 'yamibo:target');
      expect(item.readChapterCount, 1);
      expect(item.unreadCount, 0);
      expect(item.hasTags, isTrue);
      expect(progress?.episodeId, 'yamibo:target:3001');
      expect(progress?.imageIndex, 2);
      expect(favoriteRows.single['work_id'], 'yamibo:target');
    });
  });
}
