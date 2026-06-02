import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/favorites/data/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/favorites/presentation/adapters/favorite_shelf_adapter.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  test('FavoriteShelfAdapter loads categories without triggering sync side effects', () async {
    final local = _FakeLocalFavoriteRepository();
    final sync = _FakeFavoriteSyncService();
    final adapter = FavoriteShelfAdapter(
      local,
      syncService: sync,
      stateRepository: _FakeLibraryStateRepository(),
    );

    final categories = await adapter.loadCategories();
    await adapter.loadCategories();

    expect(adapter.moduleKey, LibraryModuleKey.favorite);
    expect(adapter.defaultDisplayMode, LibraryDisplayMode.list);
    expect(sync.syncCount, 0);
    expect(sync.maintenanceCount, 0);
    expect(categories.single.categoryId, favoriteDefaultCategoryId);
  });

  test('FavoriteShelfAdapter querySnapshot stays pure read without maintenance', () async {
    final local = _FakeLocalFavoriteRepository()
      ..snapshot = FavoriteSyncSnapshot(
        syncKey: favoriteSyncKey,
        remoteCount: 1,
        localActiveCount: 1,
        lastSyncedAt: DateTime(2026, 1, 1),
      );
    final sync = _FakeFavoriteSyncService();
    final adapter = FavoriteShelfAdapter(
      local,
      syncService: sync,
      stateRepository: _FakeLibraryStateRepository(),
    );

    final snapshot = await adapter.querySnapshot(
      filters: LibraryFilterSet.defaults,
      sortOption: LibraryShelfSortOption.defaults,
      keyword: '',
    );

    expect(sync.syncCount, 0);
    expect(sync.maintenanceCount, 0);
    expect(snapshot.categories.single.categoryId, favoriteDefaultCategoryId);
  });

  test('FavoriteShelfAdapter returns metadata before warming comic cover, then writes local path back', () async {
    final local = _FakeLocalFavoriteRepository(
      items: <LibraryWorkItem>[
        LibraryWorkItem(
          workId: FavoriteShelfWorkId.fromTid('100'),
          categoryId: favoriteComicCategoryId,
          title: '收藏漫画',
          coverImageUrl: 'https://img.test/cover.jpg',
          unreadCount: 0,
          totalChapterCount: 1,
          readChapterCount: 0,
          addedAt: DateTime(2026, 1, 1),
        ),
      ],
      routeTargets: const <String, FavoriteRouteTarget>{
        'favorite:100': FavoriteRouteTarget(
          tid: '100',
          title: '收藏漫画',
          contentKind: ThreadContentKind.comic,
          workId: 'yamibo:100',
        ),
      },
    );
    final imageCache = _FakeImageCacheService(localPath: '/cache/comic-cover.jpg');
    final writer = _FakeComicCoverCacheWriter();
    final sync = _FakeFavoriteSyncService();
    sync.markSynced();
    final adapter = FavoriteShelfAdapter(
      local,
      syncService: sync,
      stateRepository: _FakeLibraryStateRepository(),
      imageCacheService: imageCache,
      comicCoverCacheWriter: writer,
    );

    final items = await adapter.loadCategoryItems(categoryId: favoriteComicCategoryId);

    expect(items.single.coverLocalPath, isNull);
    expect(imageCache.lastRequest, isNull);

    final requests = await adapter.buildCoverWarmupRequests(
      selectedCategoryId: favoriteComicCategoryId,
      itemsByCategory: <String, List<LibraryWorkItem>>{
        favoriteComicCategoryId: items,
      },
    );
    final result = await adapter.warmCover(requests.single);

    expect(result?.coverLocalPath, '/cache/comic-cover.jpg');
    expect(imageCache.lastRequest?.cacheKey, 'cover/comic/yamibo:100');
    expect(writer.lastComicId, 'yamibo:100');
    expect(writer.lastCoverLocalPath, '/cache/comic-cover.jpg');
  });

  test('FavoriteShelfAdapter warms custom comic cover separately', () async {
    final local = _FakeLocalFavoriteRepository(
      items: <LibraryWorkItem>[
        LibraryWorkItem(
          workId: FavoriteShelfWorkId.fromTid('101'),
          categoryId: favoriteComicCategoryId,
          title: '自定义封面漫画',
          coverImageUrl: 'https://img.test/custom-cover.jpg',
          customCoverImageUrl: 'https://img.test/custom-cover.jpg',
          unreadCount: 0,
          totalChapterCount: 1,
          readChapterCount: 0,
          addedAt: DateTime(2026, 1, 1),
        ),
      ],
      routeTargets: const <String, FavoriteRouteTarget>{
        'favorite:101': FavoriteRouteTarget(
          tid: '101',
          title: '自定义封面漫画',
          contentKind: ThreadContentKind.comic,
          workId: 'yamibo:101',
        ),
      },
    );
    final imageCache = _FakeImageCacheService(localPath: '/cache/custom-cover.jpg');
    final writer = _FakeComicCoverCacheWriter();
    final sync = _FakeFavoriteSyncService();
    sync.markSynced();
    final adapter = FavoriteShelfAdapter(
      local,
      syncService: sync,
      stateRepository: _FakeLibraryStateRepository(),
      imageCacheService: imageCache,
      comicCoverCacheWriter: writer,
    );

    final items = await adapter.loadCategoryItems(categoryId: favoriteComicCategoryId);

    expect(items.single.coverLocalPath, isNull);
    expect(items.single.customCoverLocalPath, isNull);
    expect(imageCache.lastRequest, isNull);

    final requests = await adapter.buildCoverWarmupRequests(
      selectedCategoryId: favoriteComicCategoryId,
      itemsByCategory: <String, List<LibraryWorkItem>>{
        favoriteComicCategoryId: items,
      },
    );
    final result = await adapter.warmCover(requests.single);

    expect(result?.coverLocalPath, isNull);
    expect(result?.customCoverLocalPath, '/cache/custom-cover.jpg');
    expect(imageCache.lastRequest?.cacheKey, 'cover/custom/comic/yamibo:101');
    expect(imageCache.lastRequest?.role, ImageCacheRole.customCover);
    expect(writer.lastCoverImageUrl, isNull);
    expect(writer.lastCoverLocalPath, isNull);
    expect(writer.lastCustomCoverLocalPath, '/cache/custom-cover.jpg');
  });

  test('FavoriteShelfAdapter exposes favorite progress from task progress hub', () {
    final sync = _FakeFavoriteSyncService();
    final hub = DefaultLibraryTaskProgressHub();
    final progress = ValueNotifier<LibraryShelfTaskProgress?>(
      const LibraryShelfTaskProgress(
        message: '正在解析: 收藏帖',
        current: 1,
        total: 3,
        source: LibraryMutationSource.favoriteSync,
      ),
    );
    final registration = hub.registerSource(
      modules: const <LibraryModuleKey>{LibraryModuleKey.favorite},
      progress: progress,
      priority: LibraryTaskProgressPriority.high,
    );
    addTearDown(progress.dispose);
    addTearDown(registration.dispose);
    addTearDown(hub.dispose);
    final adapter = FavoriteShelfAdapter(
      _FakeLocalFavoriteRepository(),
      syncService: sync,
      stateRepository: _FakeLibraryStateRepository(),
      taskProgressHub: hub,
    );

    expect(adapter.taskProgress?.value?.message, '正在解析: 收藏帖');
    expect(
      adapter.taskProgress?.value?.source,
      LibraryMutationSource.favoriteSync,
    );
  });
}

class _FakeFavoriteSyncService implements FavoriteSyncService {
  final _progress = ValueNotifier<FavoriteSyncProgress>(FavoriteSyncProgress.idle);
  int syncCount = 0;
  int maintenanceCount = 0;

  @override
  ValueListenable<FavoriteSyncProgress> get progress => _progress;

  @override
  Future<void> runBackgroundMaintenance() async {
    maintenanceCount++;
  }

  @override
  Future<FavoriteSyncResult> sync() async {
    syncCount++;
    return const FavoriteSyncResult(
      mode: FavoriteSyncMode.fullDiff,
      remoteCount: 1,
      fetchedPages: 1,
      upsertedCount: 1,
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

  void markSynced() {
    syncCount = 1;
  }
}

class _FakeLocalFavoriteRepository implements LocalFavoriteRepository {
  _FakeLocalFavoriteRepository({
    this.items = const <LibraryWorkItem>[],
    this.routeTargets = const <String, FavoriteRouteTarget>{},
  });

  FavoriteSyncSnapshot? snapshot;
  final List<LibraryWorkItem> items;
  final Map<String, FavoriteRouteTarget> routeTargets;

  @override
  Future<int> countActiveThreads() async => 1;

  @override
  Future<int> countMissingDetailRecords() async => 0;

  @override
  Future<String> createCategory({required String name}) async => 'custom';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<void> finishSync({required FavoriteSyncMode mode, required int remoteCount, String? status, String? message}) async {
    snapshot = FavoriteSyncSnapshot(
      syncKey: favoriteSyncKey,
      remoteCount: remoteCount,
      localActiveCount: 1,
      lastSyncedAt: DateTime(2026, 1, 1),
    );
  }

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
  Future<List<FavoriteThreadCacheRecord>> getActiveThreadsByWorkId(String workId) async =>
      const <FavoriteThreadCacheRecord>[];

  @override
  Future<bool> hasActiveThreadForWorkId(String workId) async => false;

  @override
  Future<List<FavoriteThreadCacheRecord>> getMissingDetailRecords({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<List<FavoriteThreadCacheRecord>> getComicAutoRefreshBackfillCandidates({
    int limit = 20,
    Set<String> excludedTids = const <String>{},
  }) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(String workId) async => routeTargets[workId];

  @override
  Future<FavoriteSyncSnapshot?> getSyncSnapshot() async => snapshot;

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId) async {
    return items.where((item) => item.categoryId == categoryId).toList(growable: false);
  }

  @override
  Future<List<LibraryCategory>> loadVisibleCategories() async {
    return <LibraryCategory>[
      LibraryCategory(
        categoryId: favoriteDefaultCategoryId,
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<void> markSyncFailure(String message) async {}

  @override
  Future<List<FavoriteThreadCacheRecord>> markRemovedTids(Set<String> activeRemoteTids) async => const <FavoriteThreadCacheRecord>[];

  @override
  Future<void> moveThreadToCategory({required String tid, required String toCategoryId}) async {}

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) async => null;

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async => <String, List<LibraryWorkItem>>{
        for (final category in categories)
          category.categoryId: items
              .where((item) => item.categoryId == category.categoryId)
              .toList(growable: false),
      };

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
  Future<int> upsertRemotePage({required FavoriteThreadsPage page, required int pageStartOrder}) async => page.items.length;
}

class _FakeImageCacheService implements ImageCacheService {
  _FakeImageCacheService({required this.localPath});

  final String localPath;
  ImageCacheRequest? lastRequest;

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> clearUnprotected() async {}

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: localPath,
    );
  }

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    lastRequest = request;
    return CachedImageResult(
      success: true,
      cacheKey: request.cacheKey,
      localPath: localPath,
    );
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {}
}

class _FakeComicCoverCacheWriter implements ComicCoverCacheWriter {
  String? lastComicId;
  String? lastCoverImageUrl;
  String? lastCoverLocalPath;
  String? lastCustomCoverLocalPath;

  @override
  Future<void> updateCoverCache({
    required String comicId,
    String? coverImageUrl,
    String? coverLocalPath,
    String? customCoverLocalPath,
  }) async {
    lastComicId = comicId;
    lastCoverImageUrl = coverImageUrl;
    lastCoverLocalPath = coverLocalPath;
    lastCustomCoverLocalPath = customCoverLocalPath;
  }
}

class _FakeLibraryStateRepository implements LibraryStateRepository {
  @override
  Future<void> bindTagToWork({required LibraryModuleKey moduleKey, required String workId, required String tagId}) async {}
  @override
  Future<int> countDownloadedEpisodes({required LibraryModuleKey moduleKey, required String workId}) async => 0;
  @override
  Future<int> countReadEpisodes({required LibraryModuleKey moduleKey, required String workId}) async => 0;
  @override
  Future<int> countUnreadEpisodes({required LibraryModuleKey moduleKey, required String workId}) async => 0;
  @override
  Future<String> createTag({required String name}) async => 'tag-1';
  @override
  Future<void> deleteTag({required String tagId}) async {}
  @override
  Future<LibraryModuleDisplaySettings> getDisplaySettings({required LibraryModuleKey moduleKey, required LibraryDisplayMode defaultDisplayMode}) async {
    return LibraryModuleDisplaySettings(
      moduleKey: moduleKey,
      displayMode: defaultDisplayMode,
      gridColumns: 3,
      updatedAt: DateTime(2026, 1, 1),
    );
  }
  @override
  Future<LibraryEpisodeState?> getEpisodeState({required LibraryModuleKey moduleKey, required String episodeId}) async => null;
  @override
  Future<List<LibraryTag>> getTags() async => const <LibraryTag>[];
  @override
  Future<LibraryWorkState?> getWorkState({required LibraryModuleKey moduleKey, required String workId}) async => null;
  @override
  Future<List<LibraryTag>> getWorkTags({required LibraryModuleKey moduleKey, required String workId}) async => const <LibraryTag>[];
  @override
  Future<bool> hasAnyTag({required LibraryModuleKey moduleKey, required String workId}) async => false;
  @override
  Future<void> renameTag({required String tagId, required String newName}) async {}
  @override
  Future<void> unbindTagFromWork({required LibraryModuleKey moduleKey, required String workId, required String tagId}) async {}
  @override
  Future<void> upsertDisplaySettings({required LibraryModuleKey moduleKey, required LibraryDisplayMode displayMode, required int gridColumns}) async {}
  @override
  Future<void> upsertEpisodeState({required LibraryModuleKey moduleKey, required String episodeId, required String workId, bool? isRead, bool? isDownloaded, bool? isBookmarked, DateTime? readAt, DateTime? downloadedAt}) async {}
  @override
  Future<void> upsertWorkState({required LibraryModuleKey moduleKey, required String workId, String? lastReadEpisodeId, DateTime? lastReadAt, DateTime? checkUpdatedAt, DateTime? fetchedUpdatedAt, String? introText}) async {}
}
