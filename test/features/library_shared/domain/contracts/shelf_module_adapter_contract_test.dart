import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

void main() {
  test('ShelfModuleAdapter contract can be implemented by fake', () async {
    final adapter = _FakeShelfModuleAdapter();
    final categories = await adapter.loadCategories();
    expect(categories, isNotEmpty);
    expect(adapter.moduleTitle, 'Fake');
  });
}

class _FakeShelfModuleAdapter implements ShelfModuleAdapter {
  @override
  LibraryDisplayMode get defaultDisplayMode => LibraryDisplayMode.grid;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.comic;

  @override
  String get moduleTitle => 'Fake';

  @override
  ValueListenable<LibraryShelfTaskProgress?>? get taskProgress => null;

  @override
  ValueListenable<LibraryShelfRefreshSignal?>? get shelfRefreshSignals => null;

  @override
  Future<Object> buildDetailRouteArgument({required String workId}) async =>
      workId;

  @override
  Future<String> createCategory({required String name}) async => 'c1';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<LibraryCategory>> loadCategories() async {
    return [
      LibraryCategory(
        categoryId: 'default',
        name: '默认',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems({
    required String categoryId,
  }) async {
    return const [];
  }

  @override
  Future<void> moveWorkToCategory({
    required String workId,
    required String fromCategoryId,
    required String toCategoryId,
  }) async {}

  @override
  Future<String?> pickRandomWorkId({required String categoryId}) async => null;

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    return const {};
  }

  @override
  Future<void> refreshShelf() async {}

  @override
  Future<void> renameCategory({
    required String categoryId,
    required String newName,
  }) async {}

  @override
  Future<Map<String, List<LibraryWorkItem>>> searchItemsByKeyword({
    required String keyword,
  }) async {
    return const {};
  }
}
