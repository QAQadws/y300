import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:y300/features/cache/domain/image_cache_keys.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_cache_service.dart';
import 'package:y300/features/library_shared/domain/services/shelf_cover_warmup_service.dart';

/// 漫画书架适配器（Phase 0 骨架版）。
///
/// 目标：先把“统一接口 -> 现有仓储”的映射打通，后续 Phase 1/2 再逐步填充
/// 筛选、排序、状态位（未读/已下载/标签）等增强能力。
class ComicShelfAdapter implements ShelfModuleAdapter, ShelfCoverWarmupAdapter {
  ComicShelfAdapter(
    this._repository, {
    required LibraryStateRepository stateRepository,
    ImageCacheService? imageCacheService,
    ImageCacheServiceResolver? imageCacheServiceResolver,
  })  : _stateRepository = stateRepository,
        _coverCacheService = imageCacheServiceResolver == null
            ? LibraryCoverCacheService(imageCacheService)
            : LibraryCoverCacheService.lazy(imageCacheServiceResolver);

  final ComicRepository _repository;
  final LibraryStateRepository _stateRepository;
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
    final normalized = keyword.trim().toLowerCase();
    final categories = await _repository.getCategories();
    final result = <String, List<LibraryWorkItem>>{};
    for (final category in categories) {
      final items = await _repository.getShelfItems(categoryId: category.categoryId);
      final mappedSource = await Future.wait(items.map(_mapWork));
      final mapped = mappedSource.where((item) {
        if (normalized.isEmpty) {
          return true;
        }
        final title = item.title.toLowerCase();
        final secondary = (item.secondaryName ?? '').toLowerCase();
        return title.contains(normalized) || secondary.contains(normalized);
      }).toList(growable: false);
      result[category.categoryId] = mapped;
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
    // Phase 0：筛选与排序先复用现有查询 + 本地搜索过滤，后续扩展状态表后再增强。
    final source = await searchItemsByKeyword(keyword: keyword);
    final output = <String, List<LibraryWorkItem>>{};
    for (final category in categories) {
      var items = source[category.categoryId] ?? const <LibraryWorkItem>[];
      items = _applyBasicSort(items, sortOption);
      output[category.categoryId] = items;
    }
    return output;
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

  LibraryCategory _mapCategory(ComicShelfCategory source) {
    return LibraryCategory(
      categoryId: source.categoryId,
      name: source.name,
      sortOrder: source.sortOrder,
      createdAt: source.createdAt,
    );
  }

  Future<LibraryWorkItem> _mapWork(ComicShelfItem source) async {
    final unread = await _stateRepository.countUnreadEpisodes(
      moduleKey: LibraryModuleKey.comic,
      workId: source.comicId,
    );
    final read = await _stateRepository.countReadEpisodes(
      moduleKey: LibraryModuleKey.comic,
      workId: source.comicId,
    );
    final downloaded = await _stateRepository.countDownloadedEpisodes(
      moduleKey: LibraryModuleKey.comic,
      workId: source.comicId,
    );
    final hasTags = await _stateRepository.hasAnyTag(
      moduleKey: LibraryModuleKey.comic,
      workId: source.comicId,
    );
    final customSource = source.customCoverImageUrl?.trim();
    final customLocal = source.customCoverLocalPath?.trim();
    final hasPendingCustomCover =
        customSource != null && customSource.isNotEmpty && (customLocal == null || customLocal.isEmpty);
    return LibraryWorkItem(
      workId: source.comicId,
      categoryId: source.categoryId,
      title: source.title,
      secondaryName: source.author,
      coverImageUrl: source.coverImageUrl,
      customCoverImageUrl: source.customCoverImageUrl,
      // If a remote custom cover exists but is not cached yet, keep the normal
      // local cover out of the preferred path so the UI does not flash an older
      // ordinary cover while the custom one warms in the background.
      coverLocalPath: hasPendingCustomCover ? null : source.coverLocalPath,
      customCoverLocalPath: source.customCoverLocalPath,
      unreadCount: unread,
      totalChapterCount: unread + read,
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

  List<LibraryWorkItem> _applyBasicSort(
    List<LibraryWorkItem> source,
    LibraryShelfSortOption sortOption,
  ) {
    final list = List<LibraryWorkItem>.from(source);
    list.sort((a, b) {
      int cmp;
      switch (sortOption.field) {
        case LibraryShelfSortField.name:
          cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case LibraryShelfSortField.favoriteAddedAt:
          cmp = a.addedAt.compareTo(b.addedAt);
          break;
        default:
          cmp = a.addedAt.compareTo(b.addedAt);
          break;
      }
      if (sortOption.direction == LibrarySortDirection.desc) {
        return -cmp;
      }
      return cmp;
    });
    return list;
  }
}
