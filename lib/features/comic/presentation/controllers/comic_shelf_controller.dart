import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/domain/models/comic_shelf_models.dart';

final comicShelfControllerProvider =
    AsyncNotifierProvider.autoDispose<ComicShelfController, ComicShelfViewState>(
      ComicShelfController.new,
    );

class ComicShelfViewState {
  const ComicShelfViewState({
    required this.categories,
    required this.selectedCategoryId,
    required this.items,
    required this.gridColumnCount,
  });

  final List<ComicShelfCategory> categories;
  final String selectedCategoryId;
  final List<ComicShelfItem> items;
  final int gridColumnCount;

  bool get hasData => items.isNotEmpty;

  ComicShelfViewState copyWith({
    List<ComicShelfCategory>? categories,
    String? selectedCategoryId,
    List<ComicShelfItem>? items,
    int? gridColumnCount,
  }) {
    return ComicShelfViewState(
      categories: categories ?? this.categories,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      items: items ?? this.items,
      gridColumnCount: gridColumnCount ?? this.gridColumnCount,
    );
  }
}

/// 书架控制器：聚合分类、展示配置与当前分类下漫画列表。
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

    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(selectedCategoryId: categoryId));
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

    final items = await repository.getShelfItems(categoryId: resolvedCategoryId);

    return ComicShelfViewState(
      categories: categories,
      selectedCategoryId: resolvedCategoryId,
      items: items,
      gridColumnCount: settings.gridColumnCount,
    );
  }
}

