import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/startup/presentation/main_shell_page.dart';

void main() {
  testWidgets('MainShellPage can switch between forum and comic tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
        ],
        child: const MaterialApp(home: MainShellPage()),
      ),
    );

    expect(find.text('论坛首页'), findsOneWidget);

    await tester.tap(find.text('漫画'));
    await tester.pumpAndSettle();

    expect(find.text('书架'), findsOneWidget);
  });
}

class _FakeComicRepository implements ComicRepository {
  @override
  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    required String title,
    required ParsedComicPost parsedPost,
  }) async {}

  @override
  Future<String> createCategory({required String name}) async => 'mock-category';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async => null;

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({required String comicId, bool descending = true}) async {
    return const <ComicEpisodeItem>[];
  }

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({required String episodeId}) async {
    return const <ComicEpisodeImageItem>[];
  }

  @override
  Future<List<ComicShelfCategory>> getCategories() async {
    return <ComicShelfCategory>[
      ComicShelfCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async {
    return const ComicShelfDisplaySettings(gridColumnCount: 3);
  }

  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async {
    return const <ComicShelfItem>[];
  }

  @override
  Future<bool> isInShelf({required String comicId}) async {
    return false;
  }

  @override
  Future<ComicReadingProgress?> getLastReadProgress({required String comicId}) async => null;

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    return const ComicEpisodeRefreshResult(insertedCount: 0, updatedCount: 0, totalCount: 0);
  }

  @override
  Future<void> moveComicToCategory({
    required String comicId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}

  @override
  Future<void> updateCustomCover({required String comicId, required String? customCoverImageUrl}) async {}

  @override
  Future<void> updateGridColumnCount({required int columnCount}) async {}

  @override
  Future<void> saveEpisodeImages({required String episodeId, required List<String> imageUrls}) async {}

  @override
  Future<void> updateEpisodeImageCacheStatus({
    required String episodeId,
    required String imageUrl,
    required String cacheStatus,
    String? cacheLocalPath,
  }) async {}

  @override
  Future<void> updateLastReadProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) async {}
}
