import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:y300/features/cache/domain/image_cache_keys.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/favorites/data/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_cache_service.dart';
import 'package:y300/features/library_shared/domain/services/shelf_cover_warmup_service.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

typedef _FavoriteCoverWriteBack = Future<void> Function(
  String sourceUrl,
  String localPath,
);
typedef ComicCoverCacheWriterResolver = ComicCoverCacheWriter? Function();
typedef NovelCoverCacheWriterResolver = NovelCoverCacheWriter? Function();

class FavoriteShelfAdapter
    implements ShelfModuleAdapter, ShelfSnapshotAdapter, ShelfCoverWarmupAdapter {
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
  })  : _syncService = syncService,
        _stateRepository = stateRepository,
        _coverCacheService = imageCacheServiceResolver == null
            ? LibraryCoverCacheService(imageCacheService)
            : LibraryCoverCacheService.lazy(imageCacheServiceResolver),
        _comicCoverCacheWriterResolver = comicCoverCacheWriterResolver ??
            (() => comicCoverCacheWriter),
        _novelCoverCacheWriterResolver = novelCoverCacheWriterResolver ??
            (() => novelCoverCacheWriter),
        _taskProgress = _FavoriteShelfTaskProgressListenable(syncService.progress);

  final LocalFavoriteRepository _repository;
  final FavoriteSyncService _syncService;
  final LibraryStateRepository _stateRepository;
  final LibraryCoverCacheService _coverCacheService;
  final ComicCoverCacheWriterResolver _comicCoverCacheWriterResolver;
  final NovelCoverCacheWriterResolver _novelCoverCacheWriterResolver;
  final ValueListenable<LibraryShelfTaskProgress?> _taskProgress;
  var _initialSyncAttempted = false;

  @override
  ValueListenable<LibraryShelfTaskProgress?> get taskProgress => _taskProgress;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.favorite;

  @override
  String get moduleTitle => '收藏';

  @override
  LibraryDisplayMode get defaultDisplayMode => LibraryDisplayMode.list;

  @override
  Future<List<LibraryCategory>> loadCategories() async {
    _startInitialSyncIfNeeded();
    return _repository.loadVisibleCategories();
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems({
    required String categoryId,
  }) async {
    final items = await _repository.loadCategoryItems(categoryId);
    return items.map(_withoutOrdinaryCoverWhenCustomIsPending).toList(growable: false);
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
    _startInitialSyncIfNeeded();
    final snapshotRepository = _repository is FavoriteShelfSnapshotRepository
        ? _repository as FavoriteShelfSnapshotRepository
        : null;
    if (snapshotRepository != null) {
      final snapshot = await snapshotRepository.queryShelfSnapshot(
        filters: filters,
        sortOption: sortOption,
        keyword: keyword,
      );
      final itemsByCategory = _withoutOrdinaryCoversWhenCustomIsPending(snapshot.itemsByCategory);
      return LibraryShelfSnapshot(
        categories: snapshot.categories,
        itemsByCategory: itemsByCategory,
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
          category.categoryId: (queried[category.categoryId] ?? const <LibraryWorkItem>[]).length,
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
        entry.key: entry.value.map(_withoutOrdinaryCoverWhenCustomIsPending).toList(growable: false),
    };
  }

  LibraryWorkItem _withoutOrdinaryCoverWhenCustomIsPending(LibraryWorkItem item) {
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
      throw StateError('收藏记录不存在');
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
    return _repository.renameCategory(categoryId: categoryId, newName: newName);
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

  void _startInitialSyncIfNeeded() {
    if (_initialSyncAttempted) {
      return;
    }
    _initialSyncAttempted = true;
    // The first favorite sync may load remote list/detail data. Fire it in the
    // background so the shelf chrome and progress banner can render immediately.
    unawaited(_syncIfNoSnapshot());
  }

  Future<void> _syncIfNoSnapshot() async {
    try {
      final snapshot = await _repository.getSyncSnapshot();
      if (snapshot != null) {
        return;
      }
      await _syncService.sync();
    } catch (_) {
      // The sync service owns progress/error reporting. Keep the initial shelf
      // metadata path non-blocking even if the first remote sync fails.
    }
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
      final useCustomCover = customSourceUrl != null && customSourceUrl.isNotEmpty;
      final sourceUrl = useCustomCover ? customSourceUrl : item.coverImageUrl?.trim();
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
  Future<ShelfCoverWarmupResult?> warmCover(ShelfCoverWarmupRequest request) async {
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

class _FavoriteShelfTaskProgressListenable implements ValueListenable<LibraryShelfTaskProgress?> {
  const _FavoriteShelfTaskProgressListenable(this._source);

  final ValueListenable<FavoriteSyncProgress> _source;

  @override
  LibraryShelfTaskProgress? get value {
    // 把收藏同步内部阶段翻译成 shared 层通用进度，避免 UnifiedShelfPage 依赖 favorites 包。
    final progress = _source.value;
    if (!progress.isActive) {
      return null;
    }
    return LibraryShelfTaskProgress(
      message: progress.message,
      current: progress.current,
      total: progress.total,
    );
  }

  @override
  void addListener(VoidCallback listener) {
    _source.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _source.removeListener(listener);
  }
}
