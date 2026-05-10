import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:y300/features/cache/domain/image_cache_keys.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_cover_cache_service.dart';
import 'package:y300/features/library_shared/domain/services/shelf_cover_warmup_service.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_repository.dart';

/// 小说书架适配器（Phase 0 骨架版）。
class NovelShelfAdapter implements ShelfModuleAdapter, ShelfCoverWarmupAdapter {
  NovelShelfAdapter(
    this._repository, {
    required LibraryStateRepository stateRepository,
    ImageCacheService? imageCacheService,
    ImageCacheServiceResolver? imageCacheServiceResolver,
  })  : _stateRepository = stateRepository,
        _coverCacheService = imageCacheServiceResolver == null
            ? LibraryCoverCacheService(imageCacheService)
            : LibraryCoverCacheService.lazy(imageCacheServiceResolver);

  final NovelRepository _repository;
  final LibraryStateRepository _stateRepository;
  final LibraryCoverCacheService _coverCacheService;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.novel;

  @override
  String get moduleTitle => '小说';

  @override
  LibraryDisplayMode get defaultDisplayMode => LibraryDisplayMode.list;

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
    // Phase 0 保持空实现：后续可在此增加批量章节刷新策略。
  }

  @override
  Future<Object> buildDetailRouteArgument({required String workId}) async {
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
    return _repository.moveNovelToCategory(
      novelId: workId,
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
      moduleKey: LibraryModuleKey.novel,
      displayMode: displayMode,
      gridColumns: gridColumnCount,
    );
  }

  @override
  Future<LibraryDisplayPreference> loadDisplayPreference() async {
    final stateSettings = await _stateRepository.getDisplaySettings(
      moduleKey: LibraryModuleKey.novel,
      defaultDisplayMode: LibraryDisplayMode.list,
    );
    return LibraryDisplayPreference(
      displayMode: stateSettings.displayMode,
      gridColumnCount: stateSettings.gridColumns,
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

  LibraryCategory _mapCategory(NovelShelfCategory source) {
    return LibraryCategory(
      categoryId: source.categoryId,
      name: source.name,
      sortOrder: source.sortOrder,
      createdAt: source.createdAt,
    );
  }

  Future<LibraryWorkItem> _mapWork(NovelItem source) async {
    final unread = await _stateRepository.countUnreadEpisodes(
      moduleKey: LibraryModuleKey.novel,
      workId: source.novelId,
    );
    final read = await _stateRepository.countReadEpisodes(
      moduleKey: LibraryModuleKey.novel,
      workId: source.novelId,
    );
    final downloaded = await _stateRepository.countDownloadedEpisodes(
      moduleKey: LibraryModuleKey.novel,
      workId: source.novelId,
    );
    final hasTags = await _stateRepository.hasAnyTag(
      moduleKey: LibraryModuleKey.novel,
      workId: source.novelId,
    );
    return LibraryWorkItem(
      workId: source.novelId,
      categoryId: source.categoryId,
      title: source.title,
      secondaryName: source.author,
      coverImageUrl: source.coverImageUrl,
      coverLocalPath: source.coverLocalPath,
      customCoverLocalPath: source.customCoverLocalPath,
      unreadCount: unread,
      totalChapterCount: source.episodeCount,
      readChapterCount: read,
      addedAt: source.updatedAt,
      workUpdatedAt: source.updatedAt,
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
      final customLocal = item.customCoverLocalPath?.trim();
      if (customLocal != null && customLocal.isNotEmpty) {
        continue;
      }
      final local = item.coverLocalPath?.trim();
      final sourceUrl = item.coverImageUrl?.trim();
      if ((local == null || local.isEmpty) && sourceUrl != null && sourceUrl.isNotEmpty) {
        requests.add(
          ShelfCoverWarmupRequest(
            moduleKey: LibraryModuleKey.novel,
            workId: item.workId,
            cacheKey: ImageCacheKeys.novelCover(item.workId),
            sourceUrl: sourceUrl,
            ownerType: ImageCacheOwnerType.novel,
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
      ownerType: ImageCacheOwnerType.novel,
      ownerId: request.ownerId,
      role: request.role,
    );
    final localPath = cached?.localPath?.trim();
    if (localPath == null || localPath.isEmpty) {
      return null;
    }
    if (_repository is NovelCoverCacheWriter) {
      await (_repository as NovelCoverCacheWriter).updateCoverCache(
        novelId: request.ownerId,
        coverImageUrl: request.sourceUrl,
        coverLocalPath: localPath,
      );
    }
    return ShelfCoverWarmupResult(
      workId: request.workId,
      coverLocalPath: localPath,
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
        case LibraryShelfSortField.chapterCount:
          cmp = a.totalChapterCount.compareTo(b.totalChapterCount);
          break;
        case LibraryShelfSortField.workUpdatedAt:
          cmp = (a.workUpdatedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(b.workUpdatedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
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
