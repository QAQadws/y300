import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_shelf_page.dart';

void main() {
  testWidgets('search mode switches app bar layout', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeShelfAdapter(initialDisplayMode: LibraryDisplayMode.grid),
          onOpenWork: (context, workId) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.search), findsOneWidget);
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-shelf-search-input')), findsOneWidget);
    expect(find.text('搜索···'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testWidgets('search updates category match count label', (tester) async {
    final adapter = _FakeShelfAdapter(
      initialDisplayMode: LibraryDisplayMode.grid,
      onQuery: ({
        required List<LibraryCategory> categories,
        required LibraryFilterSet filters,
        required LibraryShelfSortOption sortOption,
        required String keyword,
      }) async {
        if (keyword.trim().isEmpty) {
          return {
            'default': [
              _item(workId: '1', title: '漫画A'),
            ],
          };
        }
        return {
          'default': [
            _item(workId: '1', title: '漫画A'),
            _item(workId: '2', title: '漫画B'),
          ],
        };
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: adapter,
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('unified-shelf-search-input')), '漫画');
    await tester.pumpAndSettle();

    expect(find.text('默认 2'), findsOneWidget);
  });

  testWidgets('filter sheet has 筛选/排序/显示 tabs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeShelfAdapter(initialDisplayMode: LibraryDisplayMode.grid),
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.filter_list).first);
    await tester.pumpAndSettle();

    expect(find.text('筛选'), findsWidgets);
    expect(find.text('排序'), findsOneWidget);
    expect(find.text('显示'), findsOneWidget);
    expect(find.text('已下载'), findsOneWidget);
  });

  testWidgets('display mode can switch list view rendering', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeShelfAdapter(initialDisplayMode: LibraryDisplayMode.grid),
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);

    await tester.tap(find.byIcon(Icons.filter_list).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('列表'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(find.byType(ListView), findsOneWidget);
  });
}

LibraryWorkItem _item({
  required String workId,
  required String title,
}) {
  return LibraryWorkItem(
    workId: workId,
    categoryId: 'default',
    title: title,
    unreadCount: 1,
    totalChapterCount: 3,
    readChapterCount: 2,
    addedAt: DateTime(2026, 1, 1),
  );
}

class _FakeShelfAdapter implements ShelfModuleAdapter {
  _FakeShelfAdapter({
    required this.initialDisplayMode,
    this.onQuery,
  });

  final LibraryDisplayMode initialDisplayMode;
  final Future<Map<String, List<LibraryWorkItem>>> Function({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  })? onQuery;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.comic;

  @override
  LibraryDisplayMode get defaultDisplayMode => initialDisplayMode;

  @override
  String get moduleTitle => '漫画';

  @override
  Future<Object> buildDetailRouteArgument({required String workId}) async => workId;

  @override
  Future<String> createCategory({required String name}) async => 'created';

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
  Future<List<LibraryWorkItem>> loadCategoryItems({required String categoryId}) async {
    return [_item(workId: '1', title: '漫画A')];
  }

  @override
  Future<LibraryDisplayPreference> loadDisplayPreference() async {
    return LibraryDisplayPreference(
      displayMode: initialDisplayMode,
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
  Future<String?> pickRandomWorkId({required String categoryId}) async => '1';

  @override
  Future<Map<String, List<LibraryWorkItem>>> queryItems({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  }) async {
    if (onQuery != null) {
      return onQuery!(
        categories: categories,
        filters: filters,
        sortOption: sortOption,
        keyword: keyword,
      );
    }
    return {
      'default': [_item(workId: '1', title: '漫画A')],
    };
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
    return queryItems(
      categories: await loadCategories(),
      filters: LibraryFilterSet.defaults,
      sortOption: LibraryShelfSortOption.defaults,
      keyword: keyword,
    );
  }

  @override
  Future<void> updateDisplayPreference({
    required LibraryDisplayMode displayMode,
    required int gridColumnCount,
  }) async {}
}
