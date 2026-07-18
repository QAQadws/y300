import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/use_cases/unfavorite_use_cases.dart';
import 'package:y300/features/favorites/presentation/adapters/favorite_shelf_adapter.dart';
import 'package:y300/features/library_shared/data/repositories/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/models/library_state_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';
import 'package:y300/features/library_shared/domain/services/shelf_category_assign_use_case.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

void main() {
  test(
    'FavoriteShelfAdapter loads categories without triggering sync side effects',
    () async {
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
      final capabilities = resolveShelfModuleCapabilities(adapter);
      expect(
        capabilities.defaultSortOption.field,
        LibraryShelfSortField.favoriteAddedAt,
      );
      expect(
        capabilities.defaultSortOption.direction,
        LibrarySortDirection.desc,
      );
      expect(sync.syncCount, 0);
      expect(sync.maintenanceCount, 0);
      expect(categories.single.categoryId, favoriteDefaultCategoryId);
    },
  );

  test(
    'FavoriteShelfAdapter querySnapshot stays pure read without maintenance',
    () async {
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
    },
  );

  test(
    'FavoriteShelfAdapter returns metadata before warming comic cover, then writes local path back',
    () async {
      final local = _FakeLocalFavoriteRepository(
        items: <LibraryWorkItem>[
          LibraryWorkItem(
            workId: FavoriteShelfWorkId.fromTid('100'),
            categoryId: favoriteComicCategoryId,
            title: 'Favorite Comic',
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
            title: 'Favorite Comic',
            contentKind: ThreadContentKind.comic,
            workId: 'yamibo:100',
          ),
        },
      );
      final imageCache = _FakeImageCacheService(
        localPath: '/cache/comic-cover.jpg',
      );
      final writer = _FakeComicCoverCacheWriter();
      final sync = _FakeFavoriteSyncService()..markSynced();
      final adapter = FavoriteShelfAdapter(
        local,
        syncService: sync,
        stateRepository: _FakeLibraryStateRepository(),
        imageCacheService: imageCache,
        comicCoverCacheWriter: writer,
      );

      final items = await adapter.loadCategoryItems(
        categoryId: favoriteComicCategoryId,
      );

      expect(items.single.coverLocalPath, isNull);
      expect(imageCache.lastRequest, isNull);

      final requests = await adapter.buildCoverWarmupRequests(
        selectedCategoryId: favoriteComicCategoryId,
        itemsByCategory: <String, List<LibraryWorkItem>>{
          favoriteComicCategoryId: items,
        },
      );
      expect(requests.single.imageSpec.kind, ForumImageKind.favoriteCover);
      expect(requests.single.imageSpec.ownerType, ImageCacheOwnerType.comic);
      expect(requests.single.imageSpec.ownerId, 'yamibo:100');
      expect(requests.single.imageSpec.cacheKey, 'cover/comic/yamibo:100');
      final result = await adapter.warmCover(requests.single);

      expect(result?.coverLocalPath, '/cache/comic-cover.jpg');
      expect(imageCache.lastRequest?.cacheKey, 'cover/comic/yamibo:100');
      expect(writer.lastComicId, 'yamibo:100');
      expect(writer.lastCoverLocalPath, '/cache/comic-cover.jpg');
    },
  );

  test('FavoriteShelfAdapter warms custom comic cover separately', () async {
    final local = _FakeLocalFavoriteRepository(
      items: <LibraryWorkItem>[
        LibraryWorkItem(
          workId: FavoriteShelfWorkId.fromTid('101'),
          categoryId: favoriteComicCategoryId,
          title: 'Custom Cover Comic',
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
          title: 'Custom Cover Comic',
          contentKind: ThreadContentKind.comic,
          workId: 'yamibo:101',
        ),
      },
    );
    final imageCache = _FakeImageCacheService(
      localPath: '/cache/custom-cover.jpg',
    );
    final writer = _FakeComicCoverCacheWriter();
    final sync = _FakeFavoriteSyncService()..markSynced();
    final adapter = FavoriteShelfAdapter(
      local,
      syncService: sync,
      stateRepository: _FakeLibraryStateRepository(),
      imageCacheService: imageCache,
      comicCoverCacheWriter: writer,
    );

    final items = await adapter.loadCategoryItems(
      categoryId: favoriteComicCategoryId,
    );

    expect(items.single.coverLocalPath, isNull);
    expect(items.single.customCoverLocalPath, isNull);
    expect(imageCache.lastRequest, isNull);

    final requests = await adapter.buildCoverWarmupRequests(
      selectedCategoryId: favoriteComicCategoryId,
      itemsByCategory: <String, List<LibraryWorkItem>>{
        favoriteComicCategoryId: items,
      },
    );
    expect(requests.single.imageSpec.kind, ForumImageKind.customCover);
    expect(requests.single.imageSpec.protected, isTrue);
    expect(requests.single.imageSpec.ownerId, 'yamibo:101');
    final result = await adapter.warmCover(requests.single);

    expect(result?.coverLocalPath, isNull);
    expect(result?.customCoverLocalPath, '/cache/custom-cover.jpg');
    expect(imageCache.lastRequest?.cacheKey, 'cover/custom/comic/yamibo:101');
    expect(imageCache.lastRequest?.role, ImageCacheRole.customCover);
    expect(writer.lastCoverImageUrl, isNull);
    expect(writer.lastCoverLocalPath, isNull);
    expect(writer.lastCustomCoverLocalPath, '/cache/custom-cover.jpg');
  });

  test(
    'FavoriteShelfAdapter skips cover warmup when route target is missing',
    () async {
      final local = _FakeLocalFavoriteRepository(
        items: <LibraryWorkItem>[
          LibraryWorkItem(
            workId: FavoriteShelfWorkId.fromTid('102'),
            categoryId: favoriteComicCategoryId,
            title: 'Missing Target',
            coverImageUrl: 'https://img.test/missing.jpg',
            unreadCount: 0,
            totalChapterCount: 1,
            readChapterCount: 0,
            addedAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final sync = _FakeFavoriteSyncService()..markSynced();
      final adapter = FavoriteShelfAdapter(
        local,
        syncService: sync,
        stateRepository: _FakeLibraryStateRepository(),
        imageCacheService: _FakeImageCacheService(
          localPath: '/cache/missing.jpg',
        ),
        comicCoverCacheWriter: _FakeComicCoverCacheWriter(),
      );

      final items = await adapter.loadCategoryItems(
        categoryId: favoriteComicCategoryId,
      );
      final requests = await adapter.buildCoverWarmupRequests(
        selectedCategoryId: favoriteComicCategoryId,
        itemsByCategory: <String, List<LibraryWorkItem>>{
          favoriteComicCategoryId: items,
        },
      );

      expect(requests, isEmpty);
    },
  );

  test(
    'FavoriteShelfAdapter exposes favorite progress from task progress hub',
    () {
      final hub = DefaultLibraryTaskProgressHub();
      final progress = ValueNotifier<LibraryShelfTaskProgress?>(
        const LibraryShelfTaskProgress(
          message: 'Parsing favorite thread',
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
        syncService: _FakeFavoriteSyncService(),
        stateRepository: _FakeLibraryStateRepository(),
        taskProgressHub: hub,
      );

      expect(adapter.taskProgress?.value?.message, 'Parsing favorite thread');
      expect(
        adapter.taskProgress?.value?.source,
        LibraryMutationSource.favoriteSync,
      );
    },
  );

  test('FavoriteShelfAdapter exposes selection actions in fixed order', () {
    final adapter = FavoriteShelfAdapter(
      _FakeLocalFavoriteRepository(),
      syncService: _FakeFavoriteSyncService(),
      stateRepository: _FakeLibraryStateRepository(),
      categoryAssignUseCase: _FakeShelfCategoryAssignUseCase(),
      unfavoriteThreadUseCase: _FakeUnfavoriteThreadUseCase(),
    );

    expect(
      adapter.selectionActions.map((action) => action.id).toList(),
      <String>[
        SelectionActionIds.assignCategory,
        SelectionActionIds.unfavorite,
      ],
    );
  });

  test('FavoriteShelfAdapter parses favorite tid before unfavorite', () async {
    final useCase = _FakeUnfavoriteThreadUseCase();
    final adapter = FavoriteShelfAdapter(
      _FakeLocalFavoriteRepository(),
      syncService: _FakeFavoriteSyncService(),
      stateRepository: _FakeLibraryStateRepository(),
      unfavoriteThreadUseCase: useCase,
    );

    final result = await adapter.runSelectionAction(
      const SelectionActionExecutionRequest(
        actionId: SelectionActionIds.unfavorite,
        workIds: <String>{'favorite:100', 'favorite:101'},
        activeCategoryId: favoriteDefaultCategoryId,
      ),
    );

    expect(useCase.lastTids, <String>{'100', '101'});
    expect(result.changed, isTrue);
    expect(result.failedCount, 0);
  });

  test('FavoriteShelfAdapter counts invalid work ids as failures', () async {
    final useCase = _FakeUnfavoriteThreadUseCase();
    final adapter = FavoriteShelfAdapter(
      _FakeLocalFavoriteRepository(),
      syncService: _FakeFavoriteSyncService(),
      stateRepository: _FakeLibraryStateRepository(),
      unfavoriteThreadUseCase: useCase,
    );

    final result = await adapter.runSelectionAction(
      const SelectionActionExecutionRequest(
        actionId: SelectionActionIds.unfavorite,
        workIds: <String>{'favorite:100', 'broken-id'},
        activeCategoryId: favoriteDefaultCategoryId,
      ),
    );

    expect(useCase.lastTids, <String>{'100'});
    expect(result.changed, isTrue);
    expect(result.failedCount, 1);
  });
}

class _FakeFavoriteSyncService implements FavoriteSyncService {
  final _progress = ValueNotifier<FavoriteSyncProgress>(
    FavoriteSyncProgress.idle,
  );
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
  Future<FavoriteSyncResult> syncRecentlyAddedThread({required String tid}) {
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
  Future<FavoriteSyncSnapshot?> getSyncSnapshot() async => snapshot;

  @override
  Future<List<LibraryCategory>> loadVisibleCategories() async {
    return <LibraryCategory>[
      LibraryCategory(
        categoryId: favoriteDefaultCategoryId,
        name: 'Default',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems(String categoryId) async {
    return items
        .where((item) => item.categoryId == categoryId)
        .toList(growable: false);
  }

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    return <String, List<LibraryWorkItem>>{
      for (final category in categories)
        category.categoryId: items
            .where((item) => item.categoryId == category.categoryId)
            .toList(growable: false),
    };
  }

  @override
  Future<FavoriteRouteTarget?> getRouteTargetByShelfWorkId(
    String workId,
  ) async {
    return routeTargets[workId];
  }

  @override
  Future<void> moveThreadToCategory({
    required String tid,
    required String toCategoryId,
  }) async {}

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) async {
    return items.isEmpty ? null : items.first.workId;
  }

  @override
  Future<int> markRemovedByWorkId(String workId) async => 0;

  @override
  Future<int> markRemovedByTids(Set<String> tids) async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeImageCacheService implements ImageCacheService {
  _FakeImageCacheService({required this.localPath});

  final String localPath;
  ImageCacheRequest? lastRequest;

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  Future<void> upsertDisplaySettings({
    required LibraryModuleKey moduleKey,
    required LibraryDisplayMode displayMode,
    required int gridColumns,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeShelfCategoryAssignUseCase implements ShelfCategoryAssignUseCase {
  Set<String>? lastWorkIds;
  String? lastSourceCategoryId;
  String? lastTargetCategoryId;

  @override
  Future<ShelfCategoryAssignResult> assign({
    required Set<String> workIds,
    required String sourceCategoryId,
    required String targetCategoryId,
  }) async {
    lastWorkIds = workIds;
    lastSourceCategoryId = sourceCategoryId;
    lastTargetCategoryId = targetCategoryId;
    return ShelfCategoryAssignResult(
      assignedWorkIds: workIds.toList(growable: false),
      failedWorkIds: const <String>[],
      targetCategoryId: targetCategoryId,
    );
  }
}

class _FakeUnfavoriteThreadUseCase implements UnfavoriteThreadUseCase {
  Set<String>? lastTids;

  @override
  Future<UnfavoriteResult> call(String tid) async {
    lastTids = <String>{tid};
    return UnfavoriteResult(
      requestedTids: <String>[tid],
      succeededTids: <String>[tid],
      failedTids: const <String>[],
      purgedWorkIds: const <String>[],
    );
  }

  @override
  Future<UnfavoriteResult> callMany(Set<String> tids) async {
    lastTids = tids;
    return UnfavoriteResult(
      requestedTids: tids.toList(growable: false),
      succeededTids: tids.toList(growable: false),
      failedTids: const <String>[],
      purgedWorkIds: const <String>[],
    );
  }
}
