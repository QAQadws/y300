import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/presentation/controllers/unified_shelf_controller.dart';

void main() {
  group('UnifiedShelfController', () {
    test('initialize should load categories and items', () async {
      final adapter = _FakeShelfAdapter(
        categories: [
          LibraryCategory(
            categoryId: 'default',
            name: 'default',
            sortOrder: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        queriedItems: {
          'default': [
            LibraryWorkItem(
              workId: 'w1',
              categoryId: 'default',
              title: 'title',
              unreadCount: 1,
              totalChapterCount: 3,
              readChapterCount: 2,
              addedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        },
      );
      final controller = UnifiedShelfController(adapter: adapter);
      await controller.initialize();

      expect(controller.state.isLoading, isFalse);
      expect(controller.state.categories.length, 1);
      expect(controller.state.itemsByCategory['default']?.length, 1);
    });

    test('hide default category when default is empty and others have items', () async {
      final adapter = _FakeShelfAdapter(
        categories: [
          LibraryCategory(
            categoryId: 'default',
            name: 'default',
            sortOrder: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
          LibraryCategory(
            categoryId: 'c1',
            name: 'follow',
            sortOrder: 1,
            createdAt: DateTime(2026, 1, 2),
          ),
        ],
        queriedItems: {
          'default': [],
          'c1': [
            LibraryWorkItem(
              workId: 'w1',
              categoryId: 'c1',
              title: 'title',
              unreadCount: 0,
              totalChapterCount: 1,
              readChapterCount: 1,
              addedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        },
      );
      final controller = UnifiedShelfController(adapter: adapter);
      await controller.initialize();

      expect(controller.state.categories.any((e) => e.categoryId == 'default'), isFalse);
      expect(controller.state.categories.any((e) => e.categoryId == 'c1'), isTrue);
    });

    test('keep default visible when it has items', () async {
      final adapter = _FakeShelfAdapter(
        categories: [
          LibraryCategory(
            categoryId: 'default',
            name: 'default',
            sortOrder: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
          LibraryCategory(
            categoryId: 'c1',
            name: 'follow',
            sortOrder: 1,
            createdAt: DateTime(2026, 1, 2),
          ),
        ],
        queriedItems: {
          'default': [
            LibraryWorkItem(
              workId: 'w0',
              categoryId: 'default',
              title: 'uncategorized',
              unreadCount: 1,
              totalChapterCount: 1,
              readChapterCount: 0,
              addedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
          'c1': [
            LibraryWorkItem(
              workId: 'w1',
              categoryId: 'c1',
              title: 'title',
              unreadCount: 0,
              totalChapterCount: 1,
              readChapterCount: 1,
              addedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        },
      );
      final controller = UnifiedShelfController(adapter: adapter);
      await controller.initialize();

      expect(controller.state.categories.any((e) => e.categoryId == 'default'), isTrue);
    });

    test('search keyword should reload and update match count map', () async {
      final adapter = _FakeShelfAdapter(
        categories: [
          LibraryCategory(
            categoryId: 'default',
            name: 'default',
            sortOrder: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        queriedItems: {
          'default': [
            LibraryWorkItem(
              workId: 'w1',
              categoryId: 'default',
              title: 'abc',
              unreadCount: 0,
              totalChapterCount: 1,
              readChapterCount: 1,
              addedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        },
      );
      final controller = UnifiedShelfController(adapter: adapter);
      await controller.initialize();
      await controller.updateKeyword('ab');

      expect(controller.state.keyword, 'ab');
      expect(controller.state.visibleMatchCountByCategory['default'], 1);
      expect(adapter.lastQueryKeyword, 'ab');
    });

    test('keyword debounce should coalesce fast consecutive input', () async {
      final adapter = _FakeShelfAdapter(
        categories: [
          LibraryCategory(
            categoryId: 'default',
            name: 'default',
            sortOrder: 0,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
        queriedItems: {
          'default': [
            LibraryWorkItem(
              workId: 'w1',
              categoryId: 'default',
              title: 'abc',
              unreadCount: 0,
              totalChapterCount: 1,
              readChapterCount: 1,
              addedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
        },
      );
      final controller = UnifiedShelfController(adapter: adapter);
      await controller.initialize();
      adapter.queryCallCount = 0;

      final f1 = controller.updateKeyword('a');
      final f2 = controller.updateKeyword('ab');
      final f3 = controller.updateKeyword('abc');
      await Future.wait([f1, f2, f3]);

      expect(controller.state.keyword, 'abc');
      expect(adapter.lastQueryKeyword, 'abc');
      expect(adapter.queryCallCount, 1);
      controller.dispose();
    });

    test('update display and grid columns should persist through adapter', () async {
      final adapter = _FakeShelfAdapter(
        categories: const [],
        queriedItems: const {},
      );
      final controller = UnifiedShelfController(adapter: adapter);
      await controller.initialize();
      await controller.updateDisplayMode(LibraryDisplayMode.list);
      await controller.updateGridColumnCount(2);

      expect(adapter.lastDisplayMode, LibraryDisplayMode.list);
      expect(adapter.lastGridColumns, 2);
    });
  });
}

class _FakeShelfAdapter implements ShelfModuleAdapter {
  _FakeShelfAdapter({
    required this.categories,
    required this.queriedItems,
  });

  final List<LibraryCategory> categories;
  final Map<String, List<LibraryWorkItem>> queriedItems;

  String? lastQueryKeyword;
  LibraryDisplayMode? lastDisplayMode;
  int? lastGridColumns;
  int queryCallCount = 0;

  @override
  LibraryDisplayMode get defaultDisplayMode => LibraryDisplayMode.grid;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.comic;

  @override
  String get moduleTitle => 'comic';

  @override
  ValueListenable<LibraryShelfTaskProgress?>? get taskProgress => null;

  @override
  Future<Object> buildDetailRouteArgument({required String workId}) async => workId;

  @override
  Future<String> createCategory({required String name}) async => 'new';

  @override
  Future<void> deleteCategory({required String categoryId}) async {}

  @override
  Future<List<LibraryCategory>> loadCategories() async => categories;

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems({required String categoryId}) async =>
      queriedItems[categoryId] ?? const <LibraryWorkItem>[];

  @override
  Future<LibraryDisplayPreference> loadDisplayPreference() async {
    return const LibraryDisplayPreference(
      displayMode: LibraryDisplayMode.grid,
      gridColumnCount: 3,
    );
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
    queryCallCount += 1;
    lastQueryKeyword = keyword;
    return queriedItems;
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
  }) async =>
      queriedItems;

  @override
  Future<void> updateDisplayPreference({
    required LibraryDisplayMode displayMode,
    required int gridColumnCount,
  }) async {
    lastDisplayMode = displayMode;
    lastGridColumns = gridColumnCount;
  }
}
