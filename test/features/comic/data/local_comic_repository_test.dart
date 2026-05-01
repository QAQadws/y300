import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local_comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('LocalComicRepository', () {
    late LocalComicRepository repository;

    setUp(() async {
      await deleteDatabase(ComicLocalDb.dbName);
      repository = LocalComicRepository(ComicLocalDb.open());
    });

    test('adds comic to shelf and can query shelf state', () async {
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
          inferredAuthor: '作者A',
        ),
      );

      final inShelf = await repository.isInShelf(comicId: 'yamibo:100');
      final items = await repository.getShelfItems();

      expect(inShelf, isTrue);
      expect(items.length, 1);
      expect(items.first.title, '测试漫画');
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
      expect(settings.gridColumnCount, 4);
    });

    test('can query comic detail and episodes descending', () async {
      await repository.addToShelf(
        comicId: 'yamibo:100',
        tid: '100',
        fid: '30',
        title: '测试漫画',
        parsedPost: const ParsedComicPost(
          imageUrls: <String>['https://img.test/cover.jpg'],
          episodeLinks: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '1', episodeTitle: '第1话'),
            ComicEpisodeLink(url: 'thread-102-1-1.html', rawText: '2', episodeTitle: '第2话'),
          ],
          plainTextSummary: '摘要',
          inferredAuthor: '作者A',
        ),
      );

      final detail = await repository.getComicDetail(comicId: 'yamibo:100');
      final episodes = await repository.getComicEpisodes(comicId: 'yamibo:100', descending: true);

      expect(detail, isNotNull);
      expect(detail!.title, '测试漫画');
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
  });
}
