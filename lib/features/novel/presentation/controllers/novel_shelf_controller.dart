import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';

class NovelShelfViewState {
  const NovelShelfViewState({
    required this.categories,
    required this.selectedCategoryId,
    required this.itemsByCategory,
    this.hint,
  });

  final List<NovelShelfCategory> categories;
  final String selectedCategoryId;
  final Map<String, List<NovelItem>> itemsByCategory;
  final String? hint;

  int get selectedIndex {
    final index = categories.indexWhere((category) => category.categoryId == selectedCategoryId);
    return index < 0 ? 0 : index;
  }

  NovelShelfCategory? get selectedCategory {
    if (categories.isEmpty) {
      return null;
    }
    return categories[selectedIndex];
  }

  List<NovelItem> itemsOf(String categoryId) {
    return itemsByCategory[categoryId] ?? const <NovelItem>[];
  }

  NovelShelfViewState copyWith({
    List<NovelShelfCategory>? categories,
    String? selectedCategoryId,
    Map<String, List<NovelItem>>? itemsByCategory,
    String? hint,
    bool clearHint = false,
  }) {
    return NovelShelfViewState(
      categories: categories ?? this.categories,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      itemsByCategory: itemsByCategory ?? this.itemsByCategory,
      hint: clearHint ? null : (hint ?? this.hint),
    );
  }
}

final novelShelfControllerProvider =
    AsyncNotifierProvider.autoDispose<NovelShelfController, NovelShelfViewState>(
  NovelShelfController.new,
);

class NovelShelfController extends AsyncNotifier<NovelShelfViewState> {
  static const String defaultCategoryId = 'default';

  @override
  FutureOr<NovelShelfViewState> build() async {
    return _load(selectedCategoryId: defaultCategoryId);
  }

  Future<void> selectCategory(String categoryId) async {
    final current = state.value;
    if (current == null || current.selectedCategoryId == categoryId) {
      return;
    }
    state = AsyncData(current.copyWith(selectedCategoryId: categoryId));
  }

  Future<void> refresh() async {
    final current = state.value;
    final selected = current?.selectedCategoryId ?? defaultCategoryId;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(selectedCategoryId: selected));
  }

  Future<void> createCategory(String name) async {
    final repository = ref.read(novelRepositoryProvider);
    final newCategoryId = await repository.createCategory(name: name);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(selectedCategoryId: newCategoryId));
  }

  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {
    final repository = ref.read(novelRepositoryProvider);
    await repository.renameCategory(categoryId: categoryId, newName: newName);
    await refresh();
  }

  Future<void> deleteCategory(String categoryId) async {
    final repository = ref.read(novelRepositoryProvider);
    await repository.deleteCategory(categoryId: categoryId);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(selectedCategoryId: defaultCategoryId));
  }

  Future<void> moveNovelToCategory({
    required String novelId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {
    final repository = ref.read(novelRepositoryProvider);
    await repository.moveNovelToCategory(
      novelId: novelId,
      fromCategoryId: fromCategoryId,
      toCategoryId: toCategoryId,
    );
    await refresh();
  }

  Future<String> addByForumThread({
    required String fid,
    required String tid,
  }) async {
    final repository = ref.read(novelRepositoryProvider);
    final normalizedFid = fid.trim();
    final normalizedTid = tid.trim();
    final novelId = 'novel:$normalizedFid:$normalizedTid';

    await repository.upsertNovelBySeed(
      seed: NovelRefreshSeed(fid: normalizedFid, tid: normalizedTid),
    );
    await repository.refreshEpisodes(novelId: novelId);

    final reloaded = await _load(
      selectedCategoryId: state.value?.selectedCategoryId ?? defaultCategoryId,
    );
    state = AsyncData(reloaded.copyWith(hint: '已加入小说书架并完成首轮章节刷新'));
    return novelId;
  }

  Future<NovelShelfViewState> _load({required String selectedCategoryId}) async {
    final repository = ref.read(novelRepositoryProvider);
    final categories = await repository.getCategories();

    final exists = categories.any((category) => category.categoryId == selectedCategoryId);
    final resolvedCategoryId = exists
        ? selectedCategoryId
        : (categories.isEmpty ? defaultCategoryId : categories.first.categoryId);

    final entries = await Future.wait(
      categories.map((category) async {
        final items = await repository.getShelfItems(categoryId: category.categoryId);
        return MapEntry(category.categoryId, items);
      }),
    );

    final itemsByCategory = <String, List<NovelItem>>{
      for (final entry in entries) entry.key: entry.value,
    };

    return NovelShelfViewState(
      categories: categories,
      selectedCategoryId: resolvedCategoryId,
      itemsByCategory: itemsByCategory,
      hint: null,
    );
  }
}
