import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/presentation/comic_detail_page.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';

void main() {
  testWidgets('ComicDetailPage renders unified detail header and chapter list', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
        ],
        child: const MaterialApp(home: ComicDetailPage(comicId: 'comic:1')),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Test Comic'), findsAtLeastNWidgets(1));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('unified-detail-chapter-comic:1:e1')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-comic:1:e1')), findsOneWidget);
    expect(find.byIcon(Icons.file_download), findsOneWidget);
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
  Future<String> createCategory({required String name}) async => 'created';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<ComicShelfCategory>> getCategories() async => const [];

  @override
  Future<ComicDetail?> getComicDetail({required String comicId}) async {
    return ComicDetail(
      comicId: comicId,
      sourceTid: '100',
      sourceFid: '30',
      title: 'Test Comic',
      author: 'Author A',
      translationGroup: 'Group A',
      coverImageUrl: null,
      updatedAt: DateTime(2026, 1, 1),
      episodeCount: 1,
    );
  }

  @override
  Future<List<ComicEpisodeItem>> getComicEpisodes({required String comicId, bool descending = true}) async {
    return const [
      ComicEpisodeItem(
        episodeId: 'comic:1:e1',
        comicId: 'comic:1',
        sourceTid: '100',
        sourceUrl: 'thread-100-1-1.html',
        orderIndex: 0,
        episodeTitle: 'Episode 1',
        publishTimeText: '2026-01-01',
      ),
    ];
  }

  @override
  Future<ComicShelfDisplaySettings> getDisplaySettings() async =>
      const ComicShelfDisplaySettings(gridColumnCount: 3);

  @override
  Future<List<ComicEpisodeImageItem>> getEpisodeImages({required String episodeId}) async => const [];

  @override
  Future<ComicReadingProgress?> getLastReadProgress({required String comicId}) async => null;

  @override
  Future<List<ComicShelfItem>> getShelfItems({String categoryId = 'default'}) async => const [];

  @override
  Future<bool> isInShelf({required String comicId}) async => true;

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    return const ComicEpisodeRefreshResult(insertedCount: 0, updatedCount: 0, totalCount: 1);
  }

  @override
  Future<void> moveComicToCategory({
    required String comicId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

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

class _FakeLibraryStateRepository implements LibraryStateRepository {
  @override
  Future<void> bindTagToWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<int> countDownloadedEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<int> countReadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<int> countUnreadEpisodes({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return 0;
  }

  @override
  Future<String> createTag({required String name}) async => 'tag-1';

  @override
  Future<void> deleteTag({required String tagId}) async {}

  @override
  Future<LibraryModuleDisplaySettings> getDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode defaultDisplayMode,
  }) async {
    return LibraryModuleDisplaySettings(
      moduleKey: moduleKey,
      displayMode: defaultDisplayMode,
      gridColumns: 3,
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<LibraryEpisodeState?> getEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
  }) async {
    return null;
  }

  @override
  Future<List<LibraryTag>> getTags() async => const [];

  @override
  Future<LibraryWorkState?> getWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return null;
  }

  @override
  Future<List<LibraryTag>> getWorkTags({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return const [];
  }

  @override
  Future<bool> hasAnyTag({
    required LibraryModuleKey moduleKey,
    required String workId,
  }) async {
    return false;
  }

  @override
  Future<void> renameTag({
    required String tagId,
    required String newName,
  }) async {}

  @override
  Future<void> unbindTagFromWork({
    required LibraryModuleKey moduleKey,
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<void> upsertDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode displayMode,
    required int gridColumns,
  }) async {}

  @override
  Future<void> upsertEpisodeState({
    required LibraryModuleKey moduleKey,
    required String episodeId,
    required String workId,
    bool? isRead,
    bool? isDownloaded,
    bool? isBookmarked,
    DateTime? readAt,
    DateTime? downloadedAt,
  }) async {}

  @override
  Future<void> upsertWorkState({
    required LibraryModuleKey moduleKey,
    required String workId,
    String? lastReadEpisodeId,
    DateTime? lastReadAt,
    DateTime? checkUpdatedAt,
    DateTime? fetchedUpdatedAt,
    String? introText,
  }) async {}
}
