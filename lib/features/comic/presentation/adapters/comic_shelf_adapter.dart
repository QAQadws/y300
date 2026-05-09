import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';
import 'package:y300/features/library_shared/data/library_state_repository.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';

/// 漫画书架适配器（Phase 0 骨架版）。
///
/// 目标：先把“统一接口 -> 现有仓储”的映射打通，后续 Phase 1/2 再逐步填充
/// 筛选、排序、状态位（未读/已下载/标签）等增强能力。
class ComicShelfAdapter implements ShelfModuleAdapter {
  ComicShelfAdapter(
    this._repository, {
    required LibraryStateRepository stateRepository,
  }) : _stateRepository = stateRepository;

  final ComicRepository _repository;
  final LibraryStateRepository _stateRepository;

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
    return LibraryWorkItem(
      workId: source.comicId,
      categoryId: source.categoryId,
      title: source.title,
      secondaryName: source.author,
      coverImageUrl: source.coverImageUrl,
      coverLocalPath: source.coverLocalPath,
      customCoverLocalPath: source.customCoverLocalPath,
      unreadCount: unread,
      totalChapterCount: unread + read,
      readChapterCount: read,
      addedAt: source.addedAt,
      hasTags: hasTags,
      isDownloaded: downloaded > 0,
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
