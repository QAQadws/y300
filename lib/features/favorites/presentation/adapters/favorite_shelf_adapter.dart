import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:y300/features/cache/domain/image_cache_keys.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/favorites/data/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/unfavorite_use_cases.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_cache_service.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';
import 'package:y300/features/library_shared/domain/services/shelf_category_assign_use_case.dart';
import 'package:y300/features/library_shared/domain/services/shelf_cover_warmup_service.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

typedef _FavoriteCoverWriteBack = Future<void> Function(
  String sourceUrl,
  String localPath,
);
typedef ComicCoverCacheWriterResolver = ComicCoverCacheWriter? Function();
typedef NovelCoverCacheWriterResolver = NovelCoverCacheWriter? Function();
typedef ShelfCategoryAssignUseCaseResolver =
    ShelfCategoryAssignUseCase? Function();
typedef UnfavoriteThreadUseCaseResolver = UnfavoriteThreadUseCase? Function();

class FavoriteShelfAdapter
    implements
        ShelfModuleAdapter,
        ShelfSnapshotAdapter,
        ShelfCoverWarmupAdapter,
        ShelfSelectionActionAdapter {
  FavoriteShelfAdapter(
    this._repository, {
    required FavoriteSyncService syncService,
    required LibraryStateRepository stateRepository,
    ImageCacheService? imageCacheService,
    ImageCacheServiceResolver? imageCacheServiceResolver,
    ComicCoverCacheWriter? comicCoverCacheWriter,
    ComicCoverCacheWriterResolver? comicCoverCacheWriterResolver,
    NovelCoverCacheWriter? novelCoverCacheWriter,
    NovelCoverCacheWriterResolver? novelCoverCacheWriterResolver,
    LibraryTaskProgressHub? taskProgressHub,
    LibraryShelfRefreshBus? shelfRefreshBus,
    ShelfCategoryAssignUseCase? categoryAssignUseCase,
    ShelfCategoryAssignUseCaseResolver? categoryAssignUseCaseResolver,
    UnfavoriteThreadUseCase? unfavoriteThreadUseCase,
    UnfavoriteThreadUseCaseResolver? unfavoriteThreadUseCaseResolver,
  })  : _syncService = syncService,
        _stateRepository = stateRepository,
        _shelfRefreshBus = shelfRefreshBus,
        _coverCacheService = imageCacheServiceResolver == null
            ? LibraryCoverCacheService(imageCacheService)
            : LibraryCoverCacheService.lazy(imageCacheServiceResolver),
        _comicCoverCacheWriterResolver =
            comicCoverCacheWriterResolver ?? (() => comicCoverCacheWriter),
        _novelCoverCacheWriterResolver =
            novelCoverCacheWriterResolver ?? (() => novelCoverCacheWriter),
        _categoryAssignUseCaseResolver =
            categoryAssignUseCaseResolver ?? (() => categoryAssignUseCase),
        _unfavoriteThreadUseCaseResolver =
            unfavoriteThreadUseCaseResolver ?? (() => unfavoriteThreadUseCase),
        _taskProgress = taskProgressHub?.progressFor(LibraryModuleKey.favorite);

  final LocalFavoriteRepository _repository;
  final FavoriteSyncService _syncService;
  final LibraryStateRepository _stateRepository;
  final LibraryShelfRefreshBus? _shelfRefreshBus;
  final LibraryCoverCacheService _coverCacheService;
  final ComicCoverCacheWriterResolver _comicCoverCacheWriterResolver;
  final NovelCoverCacheWriterResolver _novelCoverCacheWriterResolver;
  final ShelfCategoryAssignUseCaseResolver _categoryAssignUseCaseResolver;
  final UnfavoriteThreadUseCaseResolver _unfavoriteThreadUseCaseResolver;
  final ValueListenable<LibraryShelfTaskProgress?>? _taskProgress;

  static const String _moduleTitle = '\u6536\u85cf';
  static const String _assignLabel = '\u8bbe\u7f6e\u5206\u7c7b';
  static const String _unfavoriteLabel = '\u53d6\u6d88\u6536\u85cf';

  @override
  ValueListenable<LibraryShelfTaskProgress?>? get taskProgress => _taskProgress;

  @override
  List<SelectionAction> get selectionActions {
    final actions = <SelectionAction>[];
    if (_categoryAssignUseCaseResolver() != null) {
      actions.add(
        const SelectionAction(
          id: SelectionActionIds.assignCategory,
          icon: Icons.label_outline,
          label: _assignLabel,
        ),
      );
    }
    if (_unfavoriteThreadUseCaseResolver() != null) {
      actions.add(
        const SelectionAction(
          id: SelectionActionIds.unfavorite,
          icon: Icons.favorite_border,
          label: _unfavoriteLabel,
          destructive: true,
          needsConfirm: true,
        ),
      );
    }
    return actions;
  }

  @override
  ValueListenable<LibraryShelfRefreshSignal?>? get shelfRefreshSignals {
    return _shelfRefreshBus?.signal;
  }

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.favorite;

  @override
  String get moduleTitle => _moduleTitle;

  @override
  LibraryDisplayMode get defaultDisplayMode => LibraryDisplayMode.list;

  @override
  Future<List<LibraryCategory>> loadCategories() async {
    return _repository.loadVisibleCategories();
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems({
    required String categoryId,
  }) async {
    final items = await _repository.loadCategoryItems(categoryId);
    return items
        .map(_withoutOrdinaryCoverWhenCustomIsPending)
        .toList(growable: false);
  }

  @override
  Future<Map<String, List<LibraryWorkItem>>> searchItemsByKeyword({
    required String keyword,
  }) async {
    final categories = await _repository.loadVisibleCategories();
    final queried = await _repository.queryItems(
      categories: categories,
      filters: LibraryFilterSet.defaults,
      sortOption: LibraryShelfSortOption.defaults,
      keyword: keyword,
    );
    return _withoutOrdinaryCoversWhenCustomIsPending(queried);
  }

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    final queried = await _repository.queryItems(
      categories: categories,
      filters: filters,
      sortOption: sortOption,
      keyword: keyword,
    );
    return _withoutOrdinaryCoversWhenCustomIsPending(queried);
  }

  @override
  Future<LibraryShelfSnapshot> querySnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    final snapshotRepository = _repository is FavoriteShelfSnapshotRepository
        ? _repository as FavoriteShelfSnapshotRepository
        : null;
    if (snapshotRepository != null) {
      final snapshot = await snapshotRepository.queryShelfSnapshot(
        filters: filters,
        sortOption: sortOption,
        keyword: keyword,
      );
      return LibraryShelfSnapshot(
        categories: snapshot.categories,
        itemsByCategory: _withoutOrdinaryCoversWhenCustomIsPending(
          snapshot.itemsByCategory,
        ),
        visibleMatchCountByCategory: snapshot.visibleMatchCountByCategory,
      );
    }

    final categories = await loadCategories();
    final queried = await queryItems(
      categories: categories,
      filters: filters,
      sortOption: sortOption,
      keyword: keyword,
    );
    return LibraryShelfSnapshot(
      categories: categories,
      itemsByCategory: queried,
      visibleMatchCountByCategory: <String, int>{
        for (final category in categories)
          category.categoryId:
              (queried[category.categoryId] ?? const <LibraryWorkItem>[]).length,
      },
    );
  }

  @override
  Future<void> refreshShelf() async {
    await _syncService.sync();
  }

  Map<String, List<LibraryWorkItem>> _withoutOrdinaryCoversWhenCustomIsPending(
    Map<String, List<LibraryWorkItem>> source,
  ) {
    return <String, List<LibraryWorkItem>>{
      for (final entry in source.entries)
        entry.key: entry.value
            .map(_withoutOrdinaryCoverWhenCustomIsPending)
            .toList(growable: false),
    };
  }

  LibraryWorkItem _withoutOrdinaryCoverWhenCustomIsPending(
    LibraryWorkItem item,
  ) {
    final customSource = item.customCoverImageUrl?.trim();
    final customLocal = item.customCoverLocalPath?.trim();
    if (customSource == null ||
        customSource.isEmpty ||
        (customLocal != null && customLocal.isNotEmpty)) {
      return item;
    }
    return item.copyWith(clearCoverLocalPath: true);
  }

  @override
  Future<Object> buildDetailRouteArgument({required String workId}) async {
    final target = await _repository.getRouteTargetByShelfWorkId(workId);
    if (target == null) {
      throw StateError('Favorite route target is missing');
    }
    return target;
  }

  @override
  Future<String> createCategory({required String name}) {
    return _repository.createCategory(name: name);
  }

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) {
    return _repository.renameCategory(
      categoryId: categoryId,
      newName: newName,
    );
  }

  @override
  Future<void> deleteCategory({required String categoryId}) {
    return _repository.deleteCategory(categoryId: categoryId);
  }

  @override
  Future<void> moveWorkToCategory({
    required String workId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {
    final tid = FavoriteShelfWorkId.parseTid(workId);
    if (tid == null) {
      return;
    }
    await _repository.moveThreadToCategory(
      tid: tid,
      toCategoryId: toCategoryId,
    );
  }

  @override
  Future<void> updateDisplayPreference({
    required LibraryDisplayMode displayMode,
    required int gridColumnCount,
  }) {
    return _stateRepository.upsertDisplaySettings(
      moduleKey: LibraryModuleKey.favorite,
      displayMode: displayMode,
      gridColumns: gridColumnCount,
    );
  }

  @override
  Future<LibraryDisplayPreference> loadDisplayPreference() async {
    final settings = await _stateRepository.getDisplaySettings(
      moduleKey: LibraryModuleKey.favorite,
      defaultDisplayMode: LibraryDisplayMode.list,
    );
    return LibraryDisplayPreference(
      displayMode: settings.displayMode,
      gridColumnCount: settings.gridColumns,
    );
  }

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) {
    return _repository.pickRandomWorkId(categoryId: categoryId);
  }

  @override
  Future<SelectionActionResult> runSelectionAction(
    SelectionActionExecutionRequest request,
  ) async {
    switch (request.actionId) {
      case SelectionActionIds.assignCategory:
        return _runAssignCategory(request);
      case SelectionActionIds.unfavorite:
        return _runUnfavorite(request);
      case SelectionActionIds.markAllRead:
      case SelectionActionIds.markAllUnread:
      case SelectionActionIds.download:
        return const SelectionActionResult(
          message: 'Favorite shelf does not support this batch action',
        );
    }
    return const SelectionActionResult(message: 'Unsupported favorite action');
  }

  Future<SelectionActionResult> _runAssignCategory(
    SelectionActionExecutionRequest request,
  ) async {
    final useCase = _categoryAssignUseCaseResolver();
    final targetCategoryId = request.targetCategoryId?.trim();
    if (useCase == null) {
      return const SelectionActionResult(
        message: 'Favorite shelf does not support batch category assignment',
      );
    }
    if (targetCategoryId == null || targetCategoryId.isEmpty) {
      return const SelectionActionResult(message: 'Missing target category');
    }
    final result = await useCase.assign(
      workIds: request.workIds,
      sourceCategoryId: request.activeCategoryId,
      targetCategoryId: targetCategoryId,
    );
    return SelectionActionResult(
      message: _buildAssignMessage(
        assignedCount: result.assignedWorkIds.length,
        failedCount: result.failedWorkIds.length,
      ),
      changed: result.assignedWorkIds.isNotEmpty,
      failedCount: result.failedWorkIds.length,
    );
  }

  Future<SelectionActionResult> _runUnfavorite(
    SelectionActionExecutionRequest request,
  ) async {
    final useCase = _unfavoriteThreadUseCaseResolver();
    if (useCase == null) {
      return const SelectionActionResult(
        message: 'Favorite shelf does not support batch unfavorite',
      );
    }
    final tids = <String>{};
    var invalidCount = 0;
    for (final rawWorkId in request.workIds) {
      final tid = FavoriteShelfWorkId.parseTid(rawWorkId.trim());
      if (tid == null) {
        invalidCount += 1;
        continue;
      }
      tids.add(tid);
    }
    if (tids.isEmpty) {
      return SelectionActionResult(
        message: 'No valid favorite threads to unfavorite',
        failedCount: invalidCount,
      );
    }
    final result = await useCase.callMany(tids);
    final failedCount = result.failedTids.length + invalidCount;
    return SelectionActionResult(
      message: _buildUnfavoriteMessage(
        succeededCount: result.succeededTids.length,
        failedCount: failedCount,
      ),
      changed: result.succeededTids.isNotEmpty,
      failedCount: failedCount,
    );
  }

  @override
  Future<List<ShelfCoverWarmupRequest>> buildCoverWarmupRequests({
    required Map<String, List<LibraryWorkItem>> itemsByCategory,
    String? selectedCategoryId,
  }) async {
    final requests = <ShelfCoverWarmupRequest>[];
    final items = orderedShelfItemsForCoverWarmup(
      itemsByCategory: itemsByCategory,
      selectedCategoryId: selectedCategoryId,
    );
    for (final item in items) {
      final customSourceUrl = item.customCoverImageUrl?.trim();
      final useCustomCover =
          customSourceUrl != null && customSourceUrl.isNotEmpty;
      final sourceUrl =
          useCustomCover ? customSourceUrl : item.coverImageUrl?.trim();
      if (sourceUrl == null || sourceUrl.isEmpty) {
        continue;
      }
      if (useCustomCover) {
        final customLocal = item.customCoverLocalPath?.trim();
        if (customLocal != null && customLocal.isNotEmpty) {
          continue;
        }
      } else if (_hasPreferredLocalCover(item)) {
        continue;
      }
      final target = await _repository.getRouteTargetByShelfWorkId(item.workId);
      final moduleWorkId = target?.workId?.trim();
      if (target == null || moduleWorkId == null || moduleWorkId.isEmpty) {
        continue;
      }
      final cacheTarget = _resolveCacheTarget(
        target.contentKind,
        moduleWorkId,
        useCustomCover: useCustomCover,
      );
      if (cacheTarget == null) {
        continue;
      }
      requests.add(
        ShelfCoverWarmupRequest(
          moduleKey: LibraryModuleKey.favorite,
          workId: item.workId,
          cacheKey: cacheTarget.cacheKey,
          sourceUrl: sourceUrl,
          ownerType: cacheTarget.ownerType,
          ownerId: moduleWorkId,
          role: cacheTarget.role,
          useCustomCover: useCustomCover,
        ),
      );
    }
    return requests;
  }

  bool _hasPreferredLocalCover(LibraryWorkItem item) {
    final custom = item.customCoverLocalPath?.trim();
    if (custom != null && custom.isNotEmpty) {
      return true;
    }
    final cover = item.coverLocalPath?.trim();
    return cover != null && cover.isNotEmpty;
  }

  @override
  Future<ShelfCoverWarmupResult?> warmCover(
    ShelfCoverWarmupRequest request,
  ) async {
    final cached = await _coverCacheService.ensureProtectedCover(
      cacheKey: request.cacheKey,
      sourceUrl: request.sourceUrl,
      ownerType: request.ownerType,
      ownerId: request.ownerId,
      role: request.role,
    );
    final localPath = cached?.localPath?.trim();
    if (localPath == null || localPath.isEmpty) {
      return null;
    }
    final cacheTarget = _resolveCacheTarget(
      _kindFromOwnerType(request.ownerType),
      request.ownerId,
      useCustomCover: request.useCustomCover,
    );
    if (cacheTarget == null) {
      return null;
    }
    await cacheTarget.writeBack(request.sourceUrl, localPath);
    return ShelfCoverWarmupResult(
      workId: request.workId,
      coverLocalPath: request.useCustomCover ? null : localPath,
      customCoverLocalPath: request.useCustomCover ? localPath : null,
    );
  }

  ThreadContentKind _kindFromOwnerType(ImageCacheOwnerType ownerType) {
    return switch (ownerType) {
      ImageCacheOwnerType.comic => ThreadContentKind.comic,
      ImageCacheOwnerType.novel => ThreadContentKind.novel,
      ImageCacheOwnerType.thread => ThreadContentKind.forum,
    };
  }

  _FavoriteCoverCacheTarget? _resolveCacheTarget(
    ThreadContentKind kind,
    String workId, {
    required bool useCustomCover,
  }) {
    switch (kind) {
      case ThreadContentKind.comic:
        final writer = _comicCoverCacheWriterResolver();
        if (writer == null) {
          return null;
        }
        return _FavoriteCoverCacheTarget(
          cacheKey: useCustomCover
              ? ImageCacheKeys.customCover(
                  ownerType: ImageCacheOwnerType.comic.dbValue,
                  ownerId: workId,
                )
              : ImageCacheKeys.comicCover(workId),
          ownerType: ImageCacheOwnerType.comic,
          role: useCustomCover ? ImageCacheRole.customCover : ImageCacheRole.cover,
          writeBack: (sourceUrl, localPath) => writer.updateCoverCache(
            comicId: workId,
            coverImageUrl: useCustomCover ? null : sourceUrl,
            coverLocalPath: useCustomCover ? null : localPath,
            customCoverLocalPath: useCustomCover ? localPath : null,
          ),
        );
      case ThreadContentKind.novel:
        final writer = _novelCoverCacheWriterResolver();
        if (writer == null) {
          return null;
        }
        return _FavoriteCoverCacheTarget(
          cacheKey: useCustomCover
              ? ImageCacheKeys.customCover(
                  ownerType: ImageCacheOwnerType.novel.dbValue,
                  ownerId: workId,
                )
              : ImageCacheKeys.novelCover(workId),
          ownerType: ImageCacheOwnerType.novel,
          role: useCustomCover ? ImageCacheRole.customCover : ImageCacheRole.cover,
          writeBack: (sourceUrl, localPath) => writer.updateCoverCache(
            novelId: workId,
            coverImageUrl: useCustomCover ? null : sourceUrl,
            coverLocalPath: useCustomCover ? null : localPath,
            customCoverLocalPath: useCustomCover ? localPath : null,
          ),
        );
      case ThreadContentKind.unknown:
      case ThreadContentKind.forum:
        return null;
    }
  }

  String _buildAssignMessage({
    required int assignedCount,
    required int failedCount,
  }) {
    if (assignedCount == 0 && failedCount == 0) {
      return 'No favorites were moved';
    }
    if (failedCount == 0) {
      return 'Moved $assignedCount favorites';
    }
    if (assignedCount == 0) {
      return 'Failed to move favorites';
    }
    return 'Moved $assignedCount favorites, failed $failedCount';
  }

  String _buildUnfavoriteMessage({
    required int succeededCount,
    required int failedCount,
  }) {
    if (succeededCount == 0 && failedCount == 0) {
      return 'No valid favorite threads to unfavorite';
    }
    if (failedCount == 0) {
      return 'Unfavorited $succeededCount items';
    }
    if (succeededCount == 0) {
      return 'Failed to unfavorite';
    }
    return 'Unfavorited $succeededCount items, failed $failedCount';
  }
}

class _FavoriteCoverCacheTarget {
  const _FavoriteCoverCacheTarget({
    required this.cacheKey,
    required this.ownerType,
    required this.role,
    required this.writeBack,
  });

  final String cacheKey;
  final ImageCacheOwnerType ownerType;
  final ImageCacheRole role;
  final _FavoriteCoverWriteBack writeBack;
}
