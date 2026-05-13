import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:y300/features/cache/domain/image_cache_keys.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_cache_service.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_query_utils.dart';
import 'package:y300/features/library_shared/domain/services/shelf_cover_warmup_service.dart';

/// 漫画书架适配器（Phase 0 骨架版）。
///
/// 目标：先把“统一接口 -> 现有仓储”的映射打通，后续 Phase 1/2 再逐步填充
/// 筛选、排序、状态位（未读/已下载/标签）等增强能力。
class ComicShelfAdapter
    implements ShelfModuleAdapter, ShelfSnapshotAdapter, ShelfCoverWarmupAdapter {
  ComicShelfAdapter(
    this._repository, {
    required LibraryStateRepository stateRepository,
    ImageCacheService? imageCacheService,
    ImageCacheServiceResolver? imageCacheServiceResolver,
    ComicReaderFeatureFlags featureFlags = ComicReaderFeatureFlags.defaults,
  })  : _stateRepository = stateRepository,
        _featureFlags = featureFlags,
        _coverCacheService = imageCacheServiceResolver == null
            ? LibraryCoverCacheService(imageCacheService)
            : LibraryCoverCacheService.lazy(imageCacheServiceResolver);

  final ComicRepository _repository;
  final LibraryStateRepository _stateRepository;
  final ComicReaderFeatureFlags _featureFlags;
  final LibraryCoverCacheService _coverCacheService;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.comic;

  @override
  String get moduleTitle => '漫画';

  @override
  LibraryDisplayMode get defaultDisplayMode => LibraryDisplayMode.grid;

  @override
  ValueListenable<LibraryShelfTaskProgress?>? get taskProgress => null;

  @override
  Future<List<LibraryCategory>> loadCategories() async {
    final categories = await _repository.getCategories();
    return categories.map(_mapCategory).toList(growable: false);
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems({required String categoryId}) async {
    final items = await _repository.getShelfItems(categoryId: categoryId);
    return Future.wait(items.map(_mapWork));
  }

  @override
  Future<Map<String, List<LibraryWorkItem>>> searchItemsByKeyword({
    required String keyword,
  }) async {
    final categories = await _repository.getCategories();
    final result = <String, List<LibraryWorkItem>>{};
    for (final category in categories) {
      final items = await _repository.getShelfItems(categoryId: category.categoryId);
      final mappedSource = await Future.wait(items.map(_mapWork));
      result[category.categoryId] = LibraryShelfQueryUtils.filterAndSort(
        source: mappedSource,
        filters: LibraryFilterSet.defaults,
        sortOption: LibraryShelfSortOption.defaults,
        keyword: keyword,
      );
    }
    return result;
  }

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    final source = await _loadMappedItemsByCategory(categories);
    final output = <String, List<LibraryWorkItem>>{};
    for (final category in categories) {
      var items = source[category.categoryId] ?? const <LibraryWorkItem>[];
      items = LibraryShelfQueryUtils.filterAndSort(
        source: items,
        filters: filters,
        sortOption: sortOption,
        keyword: keyword,
      );
      output[category.categoryId] = items;
    }
    return output;
  }

  @override
  Future<LibraryShelfSnapshot> querySnapshot({
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    final snapshotRepository = _repository is ComicShelfSnapshotRepository
        ? _repository as ComicShelfSnapshotRepository
        : null;
    if (snapshotRepository != null &&
        _featureFlags.readerCustomMetadataEnabled) {
      final snapshot = await snapshotRepository.queryShelfSnapshot(
        filters: filters,
        sortOption: sortOption,
        keyword: keyword,
      );
      return snapshot;
    }

    // Snapshot rows only expose the already-composed display fields. When
    // custom metadata is disabled, use the item mapping path so source/custom
    // columns can be separated before reaching shared shelf UI.
    final categories = await loadCategories();
    final itemsByCategory = await queryItems(
      categories: categories,
      filters: filters,
      sortOption: sortOption,
      keyword: keyword,
    );
    return LibraryShelfSnapshot(
      categories: categories,
      itemsByCategory: itemsByCategory,
      visibleMatchCountByCategory: <String, int>{
        for (final category in categories)
          category.categoryId: (itemsByCategory[category.categoryId] ?? const <LibraryWorkItem>[]).length,
      },
    );
  }

  @override
  Future<void> refreshShelf() async {
    // 当前漫画书架数据主要来自本地，Phase 0 保留空实现接口以对齐统一控制器合同。
  }

  @override
  Future<Object> buildDetailRouteArgument({required String workId}) async {
    // 统一层只透传参数，不感知具体页面类型。
    return workId;
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
  }) {
    return _repository.moveComicToCategory(
      comicId: workId,
      fromCategoryId: fromCategoryId,
      toCategoryId: toCategoryId,
    );
  }

  @override
  Future<void> updateDisplayPreference({
    required LibraryDisplayMode displayMode,
    required int gridColumnCount,
  }) async {
    await _stateRepository.upsertDisplaySettings(
      moduleKey: LibraryModuleKey.comic,
      displayMode: displayMode,
      gridColumns: gridColumnCount,
    );
  }

  @override
  Future<LibraryDisplayPreference> loadDisplayPreference() async {
    final stateSettings = await _stateRepository.getDisplaySettings(
      moduleKey: LibraryModuleKey.comic,
      defaultDisplayMode: LibraryDisplayMode.grid,
    );
    // 兼容历史数据：若统一配置不存在，回退旧设置表。
    final legacy = await _repository.getDisplaySettings();
    return LibraryDisplayPreference(
      displayMode: stateSettings.displayMode,
      gridColumnCount: stateSettings.gridColumns == 3
          ? legacy.gridColumnCount
          : stateSettings.gridColumns,
    );
  }

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) async {
    final items = await loadCategoryItems(categoryId: categoryId);
    if (items.isEmpty) {
      return null;
    }
    final random = Random();
    return items[random.nextInt(items.length)].workId;
  }

  Future<Map<String, List<LibraryWorkItem>>> _loadMappedItemsByCategory(
    List<LibraryCategory> categories,
  ) async {
    final output = <String, List<LibraryWorkItem>>{};
    for (final category in categories) {
      final items = await _repository.getShelfItems(
        categoryId: category.categoryId,
      );
      output[category.categoryId] = await Future.wait(items.map(_mapWork));
    }
    return output;
  }

  LibraryCategory _mapCategory(ComicShelfCategory source) {
    return LibraryCategory(
      categoryId: source.categoryId,
      name: source.name,
      sortOrder: source.sortOrder,
      createdAt: source.createdAt,
    );
  }

  Future<LibraryWorkItem> _mapWork(ComicShelfItem source) async {
    final statsRepository = _repository is ComicShelfStatsRepository
        ? _repository as ComicShelfStatsRepository
        : null;
    final stats = statsRepository == null
        ? null
        : await statsRepository.getShelfWorkStats(comicId: source.comicId);
    final unread = stats?.unreadCount ??
        await _stateRepository.countUnreadEpisodes(
          moduleKey: LibraryModuleKey.comic,
          workId: source.comicId,
        );
    final read = stats?.readCount ??
        await _stateRepository.countReadEpisodes(
          moduleKey: LibraryModuleKey.comic,
          workId: source.comicId,
        );
    final downloaded = stats?.downloadedCount ??
        await _stateRepository.countDownloadedEpisodes(
          moduleKey: LibraryModuleKey.comic,
          workId: source.comicId,
        );
    final hasTags = await _stateRepository.hasAnyTag(
      moduleKey: LibraryModuleKey.comic,
      workId: source.comicId,
    );
    final useCustomMetadata = _featureFlags.readerCustomMetadataEnabled;
    final customSource =
        useCustomMetadata ? source.customCoverImageUrl?.trim() : null;
    final customLocal =
        useCustomMetadata ? source.customCoverLocalPath?.trim() : null;
    final hasPendingCustomCover =
        customSource != null && customSource.isNotEmpty && (customLocal == null || customLocal.isEmpty);
    return LibraryWorkItem(
      workId: source.comicId,
      categoryId: source.categoryId,
      title: useCustomMetadata
          ? source.title
          : (source.sourceTitle ?? source.title),
      secondaryName: _shelfSecondaryName(
        author: useCustomMetadata
            ? source.author
            : (source.sourceAuthor ?? source.author),
        translationGroup: useCustomMetadata
            ? source.translationGroup
            : (source.sourceTranslationGroup ?? source.translationGroup),
      ),
      coverImageUrl: useCustomMetadata
          ? source.coverImageUrl
          : _sourceCoverImageUrl(
              coverImageUrl: source.coverImageUrl,
              customCoverImageUrl: source.customCoverImageUrl,
            ),
      customCoverImageUrl: useCustomMetadata ? source.customCoverImageUrl : null,
      // If a remote custom cover exists but is not cached yet, keep the normal
      // local cover out of the preferred path so the UI does not flash an older
      // ordinary cover while the custom one warms in the background.
      coverLocalPath: hasPendingCustomCover
          ? null
          : useCustomMetadata
              ? source.coverLocalPath
              : _sourceCoverLocalPath(
                  coverLocalPath: source.coverLocalPath,
                  customCoverLocalPath: source.customCoverLocalPath,
                ),
      customCoverLocalPath: useCustomMetadata ? source.customCoverLocalPath : null,
      unreadCount: unread,
      totalChapterCount: stats?.totalCount ?? unread + read,
      readChapterCount: read,
      addedAt: source.addedAt,
      hasTags: hasTags,
      isDownloaded: downloaded > 0,
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
      final customSource = item.customCoverImageUrl?.trim();
      final customLocal = item.customCoverLocalPath?.trim();
      if (customSource != null && customSource.isNotEmpty) {
        if (customLocal == null || customLocal.isEmpty) {
          requests.add(
            ShelfCoverWarmupRequest(
              moduleKey: LibraryModuleKey.comic,
              workId: item.workId,
              cacheKey: ImageCacheKeys.customCover(
                ownerType: ImageCacheOwnerType.comic.dbValue,
                ownerId: item.workId,
              ),
              sourceUrl: customSource,
              ownerType: ImageCacheOwnerType.comic,
              ownerId: item.workId,
              role: ImageCacheRole.customCover,
              useCustomCover: true,
            ),
          );
        }
        continue;
      }

      final local = item.coverLocalPath?.trim();
      final sourceUrl = item.coverImageUrl?.trim();
      if ((local == null || local.isEmpty) && sourceUrl != null && sourceUrl.isNotEmpty) {
        requests.add(
          ShelfCoverWarmupRequest(
            moduleKey: LibraryModuleKey.comic,
            workId: item.workId,
            cacheKey: ImageCacheKeys.comicCover(item.workId),
            sourceUrl: sourceUrl,
            ownerType: ImageCacheOwnerType.comic,
            ownerId: item.workId,
            role: ImageCacheRole.cover,
            useCustomCover: false,
          ),
        );
      }
    }
    return requests;
  }

  @override
  Future<ShelfCoverWarmupResult?> warmCover(ShelfCoverWarmupRequest request) async {
    final cached = await _coverCacheService.ensureProtectedCover(
      cacheKey: request.cacheKey,
      sourceUrl: request.sourceUrl,
      ownerType: ImageCacheOwnerType.comic,
      ownerId: request.ownerId,
      role: request.role,
    );
    final localPath = cached?.localPath?.trim();
    if (localPath == null || localPath.isEmpty) {
      return null;
    }
    if (_repository is ComicCoverCacheWriter) {
      await (_repository as ComicCoverCacheWriter).updateCoverCache(
        comicId: request.ownerId,
        coverImageUrl: request.useCustomCover ? null : request.sourceUrl,
        coverLocalPath: request.useCustomCover ? null : localPath,
        customCoverLocalPath: request.useCustomCover ? localPath : null,
      );
    }
    return ShelfCoverWarmupResult(
      workId: request.workId,
      coverLocalPath: request.useCustomCover ? null : localPath,
      customCoverLocalPath: request.useCustomCover ? localPath : null,
    );
  }

  String? _sourceCoverImageUrl({
    required String? coverImageUrl,
    required String? customCoverImageUrl,
  }) {
    final custom = customCoverImageUrl?.trim();
    final cover = coverImageUrl?.trim();
    if (custom != null && custom.isNotEmpty && cover == custom) {
      return null;
    }
    return cover == null || cover.isEmpty ? null : cover;
  }

  String? _sourceCoverLocalPath({
    required String? coverLocalPath,
    required String? customCoverLocalPath,
  }) {
    final custom = customCoverLocalPath?.trim();
    final cover = coverLocalPath?.trim();
    if (custom != null && custom.isNotEmpty && cover == custom) {
      return null;
    }
    return cover == null || cover.isEmpty ? null : cover;
  }

  String? _shelfSecondaryName({
    required String? author,
    required String? translationGroup,
  }) {
    final normalizedAuthor = author?.trim();
    final normalizedGroup = translationGroup?.trim();
    final hasAuthor = normalizedAuthor != null && normalizedAuthor.isNotEmpty;
    final hasGroup = normalizedGroup != null && normalizedGroup.isNotEmpty;
    if (hasAuthor && hasGroup) {
      return '$normalizedAuthor / $normalizedGroup';
    }
    if (hasGroup) {
      return normalizedGroup;
    }
    return hasAuthor ? normalizedAuthor : null;
  }
}
