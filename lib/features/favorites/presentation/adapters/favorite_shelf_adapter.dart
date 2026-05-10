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
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

typedef _FavoriteCoverWriteBack = Future<void> Function(
  String sourceUrl,
  String localPath,
);
typedef ComicCoverCacheWriterResolver = ComicCoverCacheWriter? Function();
typedef NovelCoverCacheWriterResolver = NovelCoverCacheWriter? Function();

class FavoriteShelfAdapter implements ShelfModuleAdapter {
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
    await _ensureInitialSync();
    return _repository.loadVisibleCategories();
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems({
    required String categoryId,
  }) async {
    final items = await _repository.loadCategoryItems(categoryId);
    return Future.wait(items.map(_ensureFavoriteCoverCached));
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
    return _ensureCoversForQueryResult(queried);
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
    return _ensureCoversForQueryResult(queried);
  }

  @override
  Future<void> refreshShelf() async {
    await _syncService.sync();
  }

  Future<Map<String, List<LibraryWorkItem>>> _ensureCoversForQueryResult(
    Map<String, List<LibraryWorkItem>> source,
  ) async {
    final output = <String, List<LibraryWorkItem>>{};
    for (final entry in source.entries) {
      output[entry.key] = await Future.wait(entry.value.map(_ensureFavoriteCoverCached));
    }
    return output;
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

  Future<void> _ensureInitialSync() async {
    if (_initialSyncAttempted) {
      return;
    }
    _initialSyncAttempted = true;
    final snapshot = await _repository.getSyncSnapshot();
    if (snapshot != null) {
      return;
    }
    // 首次进入收藏页时建立本地缓存；失败交给统一书架错误区展示。
    await _syncService.sync();
  }

  Future<LibraryWorkItem> _ensureFavoriteCoverCached(LibraryWorkItem item) async {
    final customSourceUrl = item.customCoverImageUrl?.trim();
    if (customSourceUrl != null && customSourceUrl.isNotEmpty) {
      return _ensureFavoriteCoverCachedWithTarget(
        item: item,
        sourceUrl: customSourceUrl,
        useCustomCover: true,
      );
    }

    final sourceUrl = item.coverImageUrl?.trim();
    if (sourceUrl == null || sourceUrl.isEmpty || _hasPreferredLocalCover(item)) {
      return item;
    }
    return _ensureFavoriteCoverCachedWithTarget(
      item: item,
      sourceUrl: sourceUrl,
      useCustomCover: false,
    );
  }

  Future<LibraryWorkItem> _ensureFavoriteCoverCachedWithTarget({
    required LibraryWorkItem item,
    required String sourceUrl,
    required bool useCustomCover,
  }) async {
    if (useCustomCover) {
      final customLocal = item.customCoverLocalPath?.trim();
      if (customLocal != null && customLocal.isNotEmpty) {
        return item;
      }
    } else if (_hasPreferredLocalCover(item)) {
      return item;
    }

    final target = await _repository.getRouteTargetByShelfWorkId(item.workId);
    if (target == null) {
      return item;
    }
    final workId = target.workId?.trim();
    if (workId == null || workId.isEmpty) {
      return item;
    }

    final cacheTarget = _resolveCacheTarget(
      target.contentKind,
      workId,
      useCustomCover: useCustomCover,
    );
    if (cacheTarget == null) {
      return useCustomCover ? _copyForCustomRemoteFallback(item) : item;
    }
    final cached = await _coverCacheService.ensureProtectedCover(
      cacheKey: cacheTarget.cacheKey,
      sourceUrl: sourceUrl,
      ownerType: cacheTarget.ownerType,
      ownerId: workId,
      role: cacheTarget.role,
    );
    final localPath = cached?.localPath?.trim();
    if (localPath == null || localPath.isEmpty) {
      return useCustomCover ? _copyForCustomRemoteFallback(item) : item;
    }
    await cacheTarget.writeBack(sourceUrl, localPath);
    return _copyWithCoverLocalPath(
      item,
      localPath,
      useCustomCover: useCustomCover,
    );
  }

  bool _hasPreferredLocalCover(LibraryWorkItem item) {
    final custom = item.customCoverLocalPath?.trim();
    if (custom != null && custom.isNotEmpty) {
      return true;
    }
    final cover = item.coverLocalPath?.trim();
    return cover != null && cover.isNotEmpty;
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

  LibraryWorkItem _copyWithCoverLocalPath(
    LibraryWorkItem item,
    String localPath, {
    required bool useCustomCover,
  }) {
    return LibraryWorkItem(
      workId: item.workId,
      categoryId: item.categoryId,
      title: item.title,
      secondaryName: item.secondaryName,
      coverImageUrl: item.coverImageUrl,
      customCoverImageUrl: item.customCoverImageUrl,
      coverLocalPath: useCustomCover ? item.coverLocalPath : localPath,
      customCoverLocalPath: useCustomCover ? localPath : item.customCoverLocalPath,
      unreadCount: item.unreadCount,
      totalChapterCount: item.totalChapterCount,
      readChapterCount: item.readChapterCount,
      addedAt: item.addedAt,
      lastReadAt: item.lastReadAt,
      workUpdatedAt: item.workUpdatedAt,
      lastCheckedAt: item.lastCheckedAt,
      lastFetchedAt: item.lastFetchedAt,
      hasTags: item.hasTags,
      isDownloaded: item.isDownloaded,
    );
  }

  LibraryWorkItem _copyForCustomRemoteFallback(LibraryWorkItem item) {
    return LibraryWorkItem(
      workId: item.workId,
      categoryId: item.categoryId,
      title: item.title,
      secondaryName: item.secondaryName,
      coverImageUrl: item.coverImageUrl,
      customCoverImageUrl: item.customCoverImageUrl,
      coverLocalPath: null,
      customCoverLocalPath: item.customCoverLocalPath,
      unreadCount: item.unreadCount,
      totalChapterCount: item.totalChapterCount,
      readChapterCount: item.readChapterCount,
      addedAt: item.addedAt,
      lastReadAt: item.lastReadAt,
      workUpdatedAt: item.workUpdatedAt,
      lastCheckedAt: item.lastCheckedAt,
      lastFetchedAt: item.lastFetchedAt,
      hasTags: item.hasTags,
      isDownloaded: item.isDownloaded,
    );
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
