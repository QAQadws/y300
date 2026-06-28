import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';

final comicShelfControllerProvider =
    AsyncNotifierProvider.autoDispose<ComicShelfController, ComicShelfViewState>(
      ComicShelfController.new,
    );

class ComicShelfViewState {
  const ComicShelfViewState({
    required this.categories,
    required this.selectedCategoryId,
    required this.itemsByCategory,
    required this.gridColumnCount,
  });

  final List<ComicShelfCategory> categories;
  final String selectedCategoryId;
  final Map<String, List<ComicShelfItem>> itemsByCategory;
  final int gridColumnCount;

  int get selectedIndex {
    final index = categories.indexWhere((category) => category.categoryId == selectedCategoryId);
    return index < 0 ? 0 : index;
  }

  List<ComicShelfItem> itemsOf(String categoryId) {
    return itemsByCategory[categoryId] ?? const <ComicShelfItem>[];
  }

  ComicShelfCategory? get selectedCategory {
    if (categories.isEmpty) {
      return null;
    }
    return categories[selectedIndex];
  }

  ComicShelfViewState copyWith({
    List<ComicShelfCategory>? categories,
    String? selectedCategoryId,
    Map<String, List<ComicShelfItem>>? itemsByCategory,
    int? gridColumnCount,
  }) {
    return ComicShelfViewState(
      categories: categories ?? this.categories,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      itemsByCategory: itemsByCategory ?? this.itemsByCategory,
      gridColumnCount: gridColumnCount ?? this.gridColumnCount,
    );
  }
}

/// 书架控制器：管理分类、各分类书架数据与展示配置。
class ComicShelfController extends AsyncNotifier<ComicShelfViewState> {
  @override
  FutureOr<ComicShelfViewState> build() {
    return _load();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<void> selectCategory(String categoryId) async {
    final current = state.value;
    if (current == null || current.selectedCategoryId == categoryId) {
      return;
    }

    state = AsyncData(current.copyWith(selectedCategoryId: categoryId));
  }

  Future<void> updateGridColumnCount(int columnCount) async {
    final repository = ref.read(comicRepositoryProvider);
    await repository.updateGridColumnCount(columnCount: columnCount);
    await refresh();
  }

  Future<void> createCategory(String name) async {
    final repository = ref.read(comicRepositoryProvider);
    final newCategoryId = await repository.createCategory(name: name);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(selectedCategoryId: newCategoryId));
  }

  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {
    final repository = ref.read(comicRepositoryProvider);
    await repository.renameCategory(categoryId: categoryId, newName: newName);
    await refresh();
  }

  Future<void> deleteCategory(String categoryId) async {
    final repository = ref.read(comicRepositoryProvider);
    await repository.deleteCategory(categoryId: categoryId);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(selectedCategoryId: 'default'));
  }

  Future<void> moveComicToCategory({
    required String comicId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {
    final repository = ref.read(comicRepositoryProvider);
    await repository.moveComicToCategory(
      comicId: comicId,
      fromCategoryId: fromCategoryId,
      toCategoryId: toCategoryId,
    );
    await refresh();
  }

  Future<void> updateCustomCover({
    required String comicId,
    required String? coverUrl,
  }) async {
    final repository = ref.read(comicRepositoryProvider);
    await repository.updateCustomCover(
      comicId: comicId,
      customCoverImageUrl: coverUrl,
    );
    await refresh();
  }

  Future<ComicShelfViewState> _load({String? selectedCategoryId}) async {
    final repository = ref.read(comicRepositoryProvider);
    final categories = await repository.getCategories();
    final settings = await repository.getDisplaySettings();

    final preferredCategory = selectedCategoryId ?? state.value?.selectedCategoryId ?? 'default';
    final exists = categories.any((category) => category.categoryId == preferredCategory);
    final resolvedCategoryId = exists
        ? preferredCategory
        : (categories.isEmpty ? 'default' : categories.first.categoryId);

    // 预先加载所有分类数据，支持 PageView 左右滑动时相邻分类即时可见。
    final entries = await Future.wait(
      categories.map((category) async {
        final items = await repository.getShelfItems(categoryId: category.categoryId);
        return MapEntry(category.categoryId, items);
      }),
    );

    final itemsByCategory = <String, List<ComicShelfItem>>{
      for (final entry in entries) entry.key: entry.value,
    };

    return ComicShelfViewState(
      categories: categories,
      selectedCategoryId: resolvedCategoryId,
      itemsByCategory: itemsByCategory,
      gridColumnCount: settings.gridColumnCount,
    );
  }
}
