import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/data/comic_search_refresh_queue_providers.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/favorites/data/favorite_providers.dart';
import 'package:y300/features/favorites/data/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/startup/presentation/main_shell_page.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  testWidgets('MainShellPage can switch between forum/comic/novel/more tabs', (tester) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
          localFavoriteRepositoryProvider.overrideWith((ref) => _FakeLocalFavoriteRepository()),
          favoriteSyncServiceProvider.overrideWith((ref) => _FakeFavoriteSyncService()),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(queueSnapshot),
          mainShellBackgroundTaskStarterProvider.overrideWithValue(() async {}),
        ],
        child: const MaterialApp(home: MainShellPage()),
      ),
    );

    expect(find.text('论坛首页'), findsOneWidget);

    await tester.tap(find.text('收藏').last);
    await tester.pumpAndSettle();
    expect(find.text('收藏'), findsWidgets);
    expect(find.byKey(const Key('unified-shelf-list-view')), findsOneWidget);

    await tester.tap(find.text('漫画').last);
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);

    await tester.tap(find.text('小说').last);
    await tester.pumpAndSettle();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byKey(const Key('unified-shelf-category-indicator')), findsOneWidget);

    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    expect(find.text('更多'), findsWidgets);
    expect(find.byKey(const Key('more-login-entry')), findsOneWidget);
  });

  testWidgets('Novel tab icon changes after tap', (tester) async {
    final queueSnapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
      ComicSearchRefreshQueueSnapshot.empty,
    );
    addTearDown(queueSnapshot.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          comicRepositoryProvider.overrideWithValue(_FakeComicRepository()),
          novelRepositoryProvider.overrideWithValue(_FakeNovelRepository()),
          libraryStateRepositoryProvider.overrideWithValue(_FakeLibraryStateRepository()),
          localFavoriteRepositoryProvider.overrideWith((ref) => _FakeLocalFavoriteRepository()),
          favoriteSyncServiceProvider.overrideWith((ref) => _FakeFavoriteSyncService()),
          comicSearchRefreshQueueSnapshotProvider.overrideWithValue(queueSnapshot),
          mainShellBackgroundTaskStarterProvider.overrideWithValue(() async {}),
        ],
        child: const MaterialApp(home: MainShellPage()),
      ),
    );

    expect(find.byIcon(Icons.local_library_outlined), findsOneWidget);
    expect(find.byIcon(Icons.local_library), findsNothing);

    await tester.tap(find.text('小说'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.local_library_outlined), findsNothing);
    expect(find.byIcon(Icons.local_library), findsOneWidget);
  });
}

class _FakeComicRepository implements ComicRepository {
  @override
  Future<void> addToShelf({
    required String comicId,
    required String tid,
    required String fid,
    String? sourceTypeId,
    String? sourceTagName,
    required String title,
    required ParsedComicPost parsedPost,
  }) async {}

  @override
  Future<void> removeFromShelf({required String comicId}) async {}

  @override
  Future<String> createCategory({required String name}) async => 'mock-category';

  @override
  Future<void> clearEpisodeImageCache({required String episodeId}) async {}

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
  Future<void> updateCustomCoverFromLocalFile({required String comicId, required String localCoverPath, String? sourceEpisodeId, int? sourceImageIndex, String? sourceImageUrl}) async {}

  @override
  Future<void> updateCustomMetadata({required String comicId, String? customTitle, String? customAuthor, String? customTranslationGroup, String? customSearchTitle}) async {}

  @override
  Future<void> clearCustomMetadata({required String comicId, bool title = false, bool author = false, bool translationGroup = false, bool searchTitle = false}) async {}

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

class _FakeNovelRepository implements NovelRepository {
  @override
  Future<String> createCategory({required String name}) async => 'default';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<NovelShelfCategory>> getCategories() async {
    return <NovelShelfCategory>[
      NovelShelfCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<NovelItem?> getDetail({required String novelId}) async => null;

  @override
  Future<NovelChapterContent?> getChapterContent({required String episodeId}) async => null;

  @override
  Future<List<NovelEpisodeItem>> getEpisodes({required String novelId, bool descending = false}) async {
    return const <NovelEpisodeItem>[];
  }

  @override
  Future<NovelReaderPreferences> getReaderPreferences() async {
    return NovelReaderPreferences.defaults();
  }

  @override
  Future<List<NovelItem>> getShelfItems({String categoryId = 'default'}) async {
    return const <NovelItem>[];
  }

  @override
  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<NovelReadingProgress?> getReadingProgress({required String novelId}) async => null;

  @override
  Future<NovelEpisodeRefreshResult> refreshEpisodes({required String novelId}) async {
    return const NovelEpisodeRefreshResult(insertedCount: 0, updatedCount: 0, totalCount: 0);
  }

  @override
  Future<void> removeFromShelf({required String novelId}) async {}

  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}

  @override
  Future<void> saveReadingProgress({
    required String novelId,
    required String episodeId,
    required double scrollOffset,
  }) async {}

  @override
  Future<void> upsertNovelBySeed({required NovelRefreshSeed seed}) async {}

  @override
  Future<void> upsertReaderPreferences(NovelReaderPreferences preferences) async {}
}

class _FakeFavoriteSyncService implements FavoriteSyncService {
  final _progress = ValueNotifier<FavoriteSyncProgress>(FavoriteSyncProgress.idle);

  @override
  ValueListenable<FavoriteSyncProgress> get progress => _progress;

  @override
  Future<void> runBackgroundMaintenance() async {}

  @override
  Future<FavoriteSyncResult> sync() async {
    return const FavoriteSyncResult(
      mode: FavoriteSyncMode.incremental,
      remoteCount: 1,
      fetchedPages: 1,
      upsertedCount: 0,
      removedRecords: <FavoriteThreadCacheRecord>[],
      detailLoadedCount: 0,
      failedDetailTids: <String>[],
    );
  }

  @override
  Future<FavoriteSyncResult> syncRecentlyAddedThread({
    required String tid,
  }) {
    return sync();
  }
}

class _FakeLocalFavoriteRepository implements LocalFavoriteRepository {
  final _category = LibraryCategory(
    categoryId: favoriteDefaultCategoryId,
    name: '默认',
    sortOrder: 0,
    createdAt: DateTime(2026, 1, 1),
  );

  final _item = LibraryWorkItem(
    workId: FavoriteShelfWorkId.fromTid('100'),
    categoryId: favoriteDefaultCategoryId,
    title: '收藏帖',
    secondaryName: '作者A',
    unreadCount: 0,
    totalChapterCount: 1,
    readChapterCount: 0,
    addedAt: DateTime(2026, 1, 1),
  );

  @override
  Future<int> countActiveThreads() async => 1;

  @override
  Future<int> countMissingDetailRecords() async => 0;

  @override
  Future<String> createCategory({required String name}) async => 'fav-custom';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<void> finishSync({
    required FavoriteSyncMode mode,
    required int remoteCount,
    String? status,
    String? message,
  }) async {}

  @override
  Future<Set<String>> getActiveTids() async => const <String>{'100'};

  @override
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsForSnapshot() async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<bool> hasCompletedComicAutoRefreshBackfill() async => true;

  @override
  Future<void> markComicAutoRefreshBackfillCompleted({
    required int checkedCount,
    String? message,
  }) async {}

  @override
  Future<FavoriteThreadCacheRecord?> getActiveThreadByTid(String tid) async => null;

  @override
  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async {
    return const <FavoriteThreadCacheRecord>[];
  }

  @override
  Future<List<FavoriteThreadCacheRecord>> getComicAutoRefreshBackfillCandidates({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async {
    return const <FavoriteThreadCacheRecord>[];
  }

  @override
  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(String workId) async {
    return const FavoriteRouteTarget(
      tid: '100',
      title: '收藏帖',
      contentKind: ThreadContentKind.forum,
      workId: 'thread:100',
    );
  }

  @override
  Future<FavoriteSyncSnapshot?> getSyncSnapshot() async {
    return FavoriteSyncSnapshot(
      syncKey: favoriteSyncKey,
      remoteCount: 1,
      localActiveCount: 1,
      lastSyncedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId) async {
    return <LibraryWorkItem>[_item];
  }

  @override
  Future<List<LibraryCategory>> loadVisibleCategories() async {
    return <LibraryCategory>[_category];
  }

  @override
  Future<void> markSyncFailure(String message) async {}

  @override
  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(Set<String> activeRemoteTids) async {
    return const <FavoriteThreadCacheRecord>[];
  }

  @override
  Future<void> moveThreadToCategory({required String tid, required String toCategoryId}) async {}

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) async => _item.workId;

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    return <String, List<LibraryWorkItem>>{
      for (final category in categories) category.categoryId: <LibraryWorkItem>[_item],
    };
  }

  @override
  Future<void> renameCategory({required String categoryId, required String newName}) async {}

  @override
  Future<void> updateThreadDetailMeta({
    required String tid,
    required String fid,
    required String typeid,
    required String? tagName,
    required ThreadContentKind contentKind,
    required String? workId,
  }) async {}

  @override
  Future<int> upsertRemotePage({
    required FavoriteThreadsPage page,
    required int pageStartOrder,
  }) async => 0;
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
