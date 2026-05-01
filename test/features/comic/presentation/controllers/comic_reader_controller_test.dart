import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('controller helper APIs return episode ids by sequence', () async {
    final repository = _ReaderRepoForControllerTest();
    final episodes = await repository.getComicEpisodes(
      comicId: 'yamibo:100',
      descending: false,
    );

    expect(episodes.first.episodeId, 'yamibo:100:101');
    expect(episodes.last.episodeId, 'yamibo:100:103');
  });
}

/// Lightweight fake to document expected episode ordering in controller tests.
///
/// Full AsyncNotifier wiring is covered by widget tests; this fake focuses on
/// phase-0 API assumptions for readable review.
class _ReaderRepoForControllerTest implements ComicRepository {
  @override
  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    required String title,
    required ParsedComicPost parsedPost,
  }) async {}

  @override
  Future<String> createCategory({required String name}) async => 'mock';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async => null;

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({required String comicId, bool descending = true}) async {
    final list = <ComicEpisodeItem>[
      const ComicEpisodeItem(
        episodeId: 'yamibo:100:101',
        comicId: 'yamibo:100',
        episodeTitle: '第1话',
        sourceTid: '101',
        sourceUrl: 'thread-101-1-1.html',
        orderIndex: 0,
        publishTimeText: null,
      ),
      const ComicEpisodeItem(
        episodeId: 'yamibo:100:102',
        comicId: 'yamibo:100',
        episodeTitle: '第2话',
        sourceTid: '102',
        sourceUrl: 'thread-102-1-1.html',
        orderIndex: 1,
        publishTimeText: null,
      ),
      const ComicEpisodeItem(
        episodeId: 'yamibo:100:103',
        comicId: 'yamibo:100',
        episodeTitle: '第3话',
        sourceTid: '103',
        sourceUrl: 'thread-103-1-1.html',
        orderIndex: 2,
        publishTimeText: null,
      ),
    ];
    list.sort((a, b) => descending ? b.orderIndex.compareTo(a.orderIndex) : a.orderIndex.compareTo(b.orderIndex));
    return list;
  }

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({required String episodeId}) async {
    return const <ComicEpisodeImageItem>[];
  }

  @override
  Future<List<ComicShelfCategory>> getCategories() async => const <ComicShelfCategory>[];

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async {
    return const ComicShelfDisplaySettings(gridColumnCount: 3);
  }

  @override
  Future<ComicReadingProgress?> getLastReadProgress({required String comicId}) async => null;

  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async => const <ComicShelfItem>[];

  @override
  Future<bool> isInShelf({required String comicId}) async => false;

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
  Future<void> saveEpisodeImages({required String episodeId, required List<String> imageUrls}) async {}

  @override
  Future<void> updateCustomCover({required String comicId, required String? customCoverImageUrl}) async {}

  @override
  Future<void> updateEpisodeImageCacheStatus({
    required String episodeId,
    required String imageUrl,
    required String cacheStatus,
    String? cacheLocalPath,
  }) async {}

  @override
  Future<void> updateGridColumnCount({required int columnCount}) async {}

  @override
  Future<void> updateLastReadProgress({
    required String comicId,
    required String episodeId,
    required int imageIndex,
    required double scrollOffset,
  }) async {}
}
