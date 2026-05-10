import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/shelf_feature_flags.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_shelf_page.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_image.dart';

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
              _item(workId: '1', title: 'Comic A'),
            ],
          };
        }
        return {
          'default': [
            _item(workId: '1', title: 'Comic A'),
            _item(workId: '2', title: 'Comic B'),
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
    await tester.enterText(find.byKey(const Key('unified-shelf-search-input')), 'Comic');
    // UnifiedShelfController 对关键词查询有 250ms 防抖，等待防抖触发 reload。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Default 2'), findsOneWidget);
  });

  testWidgets('filter sheet and display mode switch work', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeShelfAdapter(initialDisplayMode: LibraryDisplayMode.grid),
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-shelf-grid-view')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.filter_list).first);
    await tester.pumpAndSettle();

    // 切到第 3 个 tab（显示），避免依赖具体文案。
    await tester.tap(find.byType(TextButton).at(2));
    await tester.pumpAndSettle();

    // 选择列表模式：第二个 Radio 对应 list。
    await tester.tap(find.byType(Radio<LibraryDisplayMode>).at(1));
    await tester.pumpAndSettle();

    // 点击底部右侧应用按钮（FilledButton）。
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-shelf-list-view')), findsOneWidget);
  });

  testWidgets('pull to refresh triggers adapter refresh in grid/list container', (tester) async {
    final adapter = _FakeShelfAdapter(initialDisplayMode: LibraryDisplayMode.grid);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: adapter,
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(adapter.refreshCalls, 0);
    // 下拉目标使用列表滚动容器，避免依赖页面结构中是否存在 CustomScrollView。
    await tester.drag(find.byKey(const Key('unified-shelf-grid-view')), const Offset(0, 300));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(adapter.refreshCalls, 1);
  });

  testWidgets('grid and list have cacheExtent for large shelf scrolling', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeShelfAdapter(initialDisplayMode: LibraryDisplayMode.grid),
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final grid = tester.widget<GridView>(find.byKey(const Key('unified-shelf-grid-view')));
    expect(grid.cacheExtent, 900);

    await tester.tap(find.byIcon(Icons.filter_list).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Radio<LibraryDisplayMode>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(find.byKey(const Key('unified-shelf-list-view')));
    expect(list.cacheExtent, 900);
  });

  testWidgets('cover image feature flag can fall back to LibraryCachedImage', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeShelfAdapter(initialDisplayMode: LibraryDisplayMode.grid),
          featureFlags: ShelfFeatureFlags.defaults.copyWith(useShelfCoverImage: false),
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LibraryCachedImage), findsOneWidget);
    expect(find.byType(ShelfCoverImage), findsNothing);
  });

  testWidgets('category pages keep stable PageStorage keys for scroll restoration', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeShelfAdapter(initialDisplayMode: LibraryDisplayMode.grid),
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const PageStorageKey<String>('unified-shelf-category-page-default')),
      findsOneWidget,
    );
    expect(
      find.byKey(const PageStorageKey<String>('unified-shelf-grid-storage-default')),
      findsOneWidget,
    );
  });

  testWidgets('optional task progress renders above shelf content', (tester) async {
    final progress = ValueNotifier<LibraryShelfTaskProgress?>(
      const LibraryShelfTaskProgress(
        message: '正在解析收藏详情',
        current: 3,
        total: 10,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeShelfAdapter(
            initialDisplayMode: LibraryDisplayMode.list,
            taskProgress: progress,
          ),
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-shelf-task-progress-bar')), findsOneWidget);
    expect(find.text('正在解析收藏详情'), findsOneWidget);
    expect(find.text('3/10'), findsOneWidget);

    progress.value = null;
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-shelf-task-progress-bar')), findsNothing);
  });

  testWidgets('initial loading does not flash empty shelf state', (tester) async {
    final adapter = _FakeShelfAdapter(
      initialDisplayMode: LibraryDisplayMode.grid,
      onQuery: ({
        required List<LibraryCategory> categories,
        required LibraryFilterSet filters,
        required LibraryShelfSortOption sortOption,
        required String keyword,
      }) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return {
          'default': [_item(workId: '1', title: 'Comic A')],
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

    expect(find.text('书架为空'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
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
    this.taskProgress,
  });

  final LibraryDisplayMode initialDisplayMode;
  @override
  final ValueListenable<LibraryShelfTaskProgress?>? taskProgress;
  int refreshCalls = 0;
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
  String get moduleTitle => 'Comic';

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
        name: 'Default',
        sortOrder: 0,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems({required String categoryId}) async {
    return [_item(workId: '1', title: 'Comic A')];
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
      'default': [_item(workId: '1', title: 'Comic A')],
    };
  }

  @override
  Future<void> refreshShelf() async {
    refreshCalls += 1;
  }

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
