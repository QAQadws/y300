import 'dart:math';

import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/novel_repository.dart';

/// 小说书架适配器（Phase 0 骨架版）。
class NovelShelfAdapter implements ShelfModuleAdapter {
  NovelShelfAdapter(this._repository);

  final NovelRepository _repository;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.novel;

  @override
  String get moduleTitle => '小说';

  @override
  LibraryDisplayMode get defaultDisplayMode => LibraryDisplayMode.list;

  @override
  Future<List<LibraryCategory>> loadCategories() async {
    final categories = await _repository.getCategories();
    return categories.map(_mapCategory).toList(growable: false);
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems({required String categoryId}) async {
    final items = await _repository.getShelfItems(categoryId: categoryId);
    return items.map(_mapWork).toList(growable: false);
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
      final mapped = items.map(_mapWork).where((item) {
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
    // Phase 0：小说尚无独立显示偏好持久化，先保留空实现合同。
  }

  @override
  Future<LibraryDisplayPreference> loadDisplayPreference() async {
    return const LibraryDisplayPreference(
      displayMode: LibraryDisplayMode.list,
      gridColumnCount: 1,
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

  LibraryWorkItem _mapWork(NovelItem source) {
    return LibraryWorkItem(
      workId: source.novelId,
      categoryId: source.categoryId,
      title: source.title,
      secondaryName: source.author,
      coverImageUrl: source.coverImageUrl,
      unreadCount: 0,
      totalChapterCount: source.episodeCount,
      readChapterCount: 0,
      addedAt: source.updatedAt,
      workUpdatedAt: source.updatedAt,
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

