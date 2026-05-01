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
  });
}

