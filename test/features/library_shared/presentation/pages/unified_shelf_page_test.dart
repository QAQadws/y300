import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/cache/presentation/widgets/library_cached_image.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_selection_action_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/shelf_feature_flags.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_shelf_page.dart';
import 'package:y300/features/library_shared/presentation/selection/shelf_selection_host_controller.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_card.dart';
import 'package:y300/shared/widgets/shelf/shelf_cover_image.dart';
import 'package:y300/shared/widgets/shelf/shelf_theme_palette.dart';

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

  testWidgets('grid and list have scrollCacheExtent for large shelf scrolling', (tester) async {
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
    expect(grid.scrollCacheExtent, const ScrollCacheExtent.pixels(900));

    await tester.tap(find.byIcon(Icons.filter_list).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Radio<LibraryDisplayMode>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    final list = tester.widget<ListView>(find.byKey(const Key('unified-shelf-list-view')));
    expect(list.scrollCacheExtent, const ScrollCacheExtent.pixels(900));
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

  testWidgets('list mode hides cover placeholder when item has no cover source', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeShelfAdapter(initialDisplayMode: LibraryDisplayMode.list),
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final listItem = find.byKey(const ValueKey<String>('unified-shelf-list-item-1'));
    expect(
      find.descendant(
        of: listItem,
        matching: find.byIcon(Icons.image_not_supported_outlined),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: listItem,
        matching: find.byType(ShelfCoverImage),
      ),
      findsNothing,
    );
  });

  testWidgets('list mode keeps leading cover when item has cover source', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: UnifiedShelfPage(
            adapter: _FakeShelfAdapter(
              initialDisplayMode: LibraryDisplayMode.list,
              onQuery: ({
                required List<LibraryCategory> categories,
                required LibraryFilterSet filters,
                required LibraryShelfSortOption sortOption,
                required String keyword,
              }) async {
                return {
                  'default': [
                    _item(
                      workId: 'covered',
                      title: 'Covered Comic',
                      coverImageUrl: 'https://example.com/covered.jpg',
                    ),
                  ],
                };
              },
            ),
            onOpenWork: (context, workId) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('unified-shelf-list-item-covered')),
        matching: find.byType(ShelfCoverImage),
      ),
      findsOneWidget,
    );
  });

  testWidgets('unread badge renders shelf aggregate count', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeShelfAdapter(
            initialDisplayMode: LibraryDisplayMode.list,
            onQuery: ({
              required List<LibraryCategory> categories,
              required LibraryFilterSet filters,
              required LibraryShelfSortOption sortOption,
              required String keyword,
            }) async {
              return {
                'default': [
                  LibraryWorkItem(
                    workId: 'badge-work',
                    categoryId: 'default',
                    title: 'Badge Comic',
                    unreadCount: 7,
                    totalChapterCount: 10,
                    readChapterCount: 3,
                    addedAt: DateTime(2026, 1, 1),
                  ),
                ],
              };
            },
          ),
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('unified-shelf-list-item-badge-work')),
        matching: find.text('7'),
      ),
      findsOneWidget,
    );
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
        message: '正在解析: 收藏帖',
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
    expect(find.text('正在解析: 收藏帖'), findsOneWidget);
    expect(find.text('3/10'), findsOneWidget);

    progress.value = null;
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-shelf-task-progress-bar')), findsNothing);
  });

  testWidgets('dark theme shelf surfaces use shelf palette', (tester) async {
    final theme = AppTheme.dark();
    final palette = const ShelfThemePaletteResolver().resolve(theme);
    final progress = ValueNotifier<LibraryShelfTaskProgress?>(
      const LibraryShelfTaskProgress(
        message: '正在解析: 收藏帖',
        current: 1,
        total: 2,
      ),
    );
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: theme,
          home: UnifiedShelfPage(
            adapter: _FakeShelfAdapter(
              initialDisplayMode: LibraryDisplayMode.list,
              taskProgress: progress,
              onQuery: ({
                required List<LibraryCategory> categories,
                required LibraryFilterSet filters,
                required LibraryShelfSortOption sortOption,
                required String keyword,
              }) async {
                return {
                  'default': [
                    _item(
                      workId: 'covered',
                      title: 'Covered Comic',
                      coverImageUrl: 'https://example.com/covered.jpg',
                    ),
                  ],
                };
              },
            ),
            onOpenWork: (context, workId) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final headerMaterial = tester.widget<Material>(
      find.ancestor(
        of: find.byKey(
          const ValueKey<String>('unified-shelf-category-tab-default'),
        ),
        matching: find.byType(Material),
      ).first,
    );
    final bannerMaterial = tester.widget<Material>(
      find.ancestor(
        of: find.byKey(const Key('unified-shelf-task-progress-bar')),
        matching: find.byType(Material),
      ).first,
    );
    final listItemMaterial = tester.widget<Material>(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('unified-shelf-list-item-covered'),
        ),
        matching: find.byType(Material),
      ).first,
    );

    expect(headerMaterial.color, palette.categoryBarBackground);
    expect(bannerMaterial.color, palette.taskProgressBackground);
    expect(listItemMaterial.color, palette.listItemBackground);

    await tester.tap(find.byIcon(Icons.filter_list).first);
    await tester.pumpAndSettle();

    expect(find.text('筛选'), findsWidgets);
    await tester.tap(find.byType(TextButton).at(2));
    await tester.pumpAndSettle();

    expect(find.text('网格'), findsOneWidget);
    expect(find.text('列表'), findsOneWidget);
  });

  testWidgets('task progress without total keeps banner indeterminate', (tester) async {
    final progress = ValueNotifier<LibraryShelfTaskProgress?>(
      const LibraryShelfTaskProgress(
        message: '排队漫画 正在等待搜索 预计耗时21s',
      ),
    );
    addTearDown(progress.dispose);
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('unified-shelf-task-progress-bar')),
    );
    expect(bar.value, isNull);
    expect(find.byKey(const Key('unified-shelf-task-progress-count')), findsNothing);
    expect(find.text('排队漫画 正在等待搜索 预计耗时21s'), findsOneWidget);
  });

  testWidgets('hidden task progress does not render banner', (tester) async {
    final progress = ValueNotifier<LibraryShelfTaskProgress?>(
      const LibraryShelfTaskProgress(
        message: '正在预热封面',
        source: LibraryMutationSource.coverWarmup,
        visible: false,
      ),
    );
    addTearDown(progress.dispose);
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

    expect(find.byKey(const Key('unified-shelf-task-progress-bar')), findsNothing);
    expect(find.text('正在预热封面'), findsNothing);
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

  testWidgets('long press enters selection mode and selected grid item is highlighted', (
    tester,
  ) async {
    final host = ShelfSelectionHostController();
    addTearDown(host.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeSelectableShelfAdapter(
            initialDisplayMode: LibraryDisplayMode.grid,
          ),
          selectionHost: host,
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(const ValueKey<String>('unified-shelf-grid-item-1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('selection-app-bar')), findsOneWidget);
    expect(host.state?.selectedCount, 1);
    final card = tester.widget<ShelfCoverCard>(
      find.byKey(const ValueKey<String>('unified-shelf-grid-item-1')),
    );
    expect(card.selected, isTrue);
  });

  testWidgets('selection mode tap toggles item without opening detail', (
    tester,
  ) async {
    final host = ShelfSelectionHostController();
    addTearDown(host.dispose);
    var openCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeSelectableShelfAdapter(
            initialDisplayMode: LibraryDisplayMode.grid,
          ),
          selectionHost: host,
          onOpenWork: (context, workId) async {
            openCount += 1;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final itemFinder =
        find.byKey(const ValueKey<String>('unified-shelf-grid-item-1'));
    await tester.longPress(itemFinder);
    await tester.pumpAndSettle();
    await tester.tap(itemFinder);
    await tester.pumpAndSettle();

    expect(openCount, 0);
    expect(find.byKey(const Key('selection-app-bar')), findsNothing);
    expect(host.isActive, isFalse);
  });

  testWidgets('selection mode disables category tap and page swipe', (tester) async {
    final host = ShelfSelectionHostController();
    addTearDown(host.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeSelectableShelfAdapter(
            initialDisplayMode: LibraryDisplayMode.grid,
            categories: [
              LibraryCategory(
                categoryId: 'default',
                name: 'Default',
                sortOrder: 0,
                createdAt: DateTime(2026, 1, 1),
              ),
              LibraryCategory(
                categoryId: 'other',
                name: 'Other',
                sortOrder: 1,
                createdAt: DateTime(2026, 1, 2),
              ),
            ],
            itemsByCategory: {
              'default': [_item(workId: '1', title: 'Comic A')],
              'other': [_item(workId: '2', title: 'Comic B')],
            },
          ),
          selectionHost: host,
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(const ValueKey<String>('unified-shelf-grid-item-1')),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('unified-shelf-category-tab-other')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('unified-shelf-grid-view')).first,
      const Offset(-300, 0),
    );
    await tester.pumpAndSettle();

    expect(host.state?.activeCategoryId, 'default');
    expect(
      find.byKey(const ValueKey<String>('unified-shelf-grid-item-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('unified-shelf-grid-item-2')),
      findsNothing,
    );
  });

  testWidgets('page back exits selection before popping route', (tester) async {
    final host = ShelfSelectionHostController();
    addTearDown(host.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeSelectableShelfAdapter(
            initialDisplayMode: LibraryDisplayMode.grid,
          ),
          selectionHost: host,
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(const ValueKey<String>('unified-shelf-grid-item-1')),
    );
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(UnifiedShelfPage), findsOneWidget);
    expect(find.byKey(const Key('selection-app-bar')), findsNothing);
    expect(host.isActive, isFalse);
  });

  testWidgets('list mode selected item shows border highlight', (tester) async {
    final host = ShelfSelectionHostController();
    addTearDown(host.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeSelectableShelfAdapter(
            initialDisplayMode: LibraryDisplayMode.list,
          ),
          selectionHost: host,
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final itemFinder =
        find.byKey(const ValueKey<String>('unified-shelf-list-item-1'));
    final sizeBefore = tester.getSize(itemFinder);
    await tester.longPress(itemFinder);
    await tester.pumpAndSettle();
    final sizeAfter = tester.getSize(itemFinder);

    expect(sizeAfter, sizeBefore);
    final tile = tester.widget<ListTile>(
      find.descendant(
        of: itemFinder,
        matching: find.byKey(
          const ValueKey<String>('unified-shelf-list-tile-1'),
        ),
      ),
    );
    expect(tile.selected, isTrue);
    expect(_borderColorForListItem(tester, itemFinder), isNot(Colors.transparent));
  });

  testWidgets('list mode select all highlights all visible items', (tester) async {
    final host = ShelfSelectionHostController();
    addTearDown(host.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeSelectableShelfAdapter(
            initialDisplayMode: LibraryDisplayMode.list,
            itemsByCategory: {
              'default': [
                _item(workId: '1', title: 'Comic A'),
                _item(workId: '2', title: 'Comic B'),
                _item(workId: '3', title: 'Comic C'),
              ],
            },
          ),
          selectionHost: host,
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(const ValueKey<String>('unified-shelf-list-item-1')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('selection-app-bar-select-all')));
    await tester.pumpAndSettle();

    expect(find.text('已选 3 项'), findsOneWidget);
    for (final workId in ['1', '2', '3']) {
      final itemFinder =
          find.byKey(ValueKey<String>('unified-shelf-list-item-$workId'));
      final tileFinder = find.descendant(
        of: itemFinder,
        matching: find.byKey(
          ValueKey<String>('unified-shelf-list-tile-$workId'),
        ),
      );
      expect(tester.widget<ListTile>(tileFinder).selected, isTrue);
      expect(_borderColorForListItem(tester, itemFinder), isNot(Colors.transparent));
    }
  });

  testWidgets('list mode invert updates highlighted items', (tester) async {
    final host = ShelfSelectionHostController();
    addTearDown(host.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeSelectableShelfAdapter(
            initialDisplayMode: LibraryDisplayMode.list,
            itemsByCategory: {
              'default': [
                _item(workId: '1', title: 'Comic A'),
                _item(workId: '2', title: 'Comic B'),
                _item(workId: '3', title: 'Comic C'),
              ],
            },
          ),
          selectionHost: host,
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(const ValueKey<String>('unified-shelf-list-item-1')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('selection-app-bar-invert')));
    await tester.pumpAndSettle();

    expect(find.text('已选 2 项'), findsOneWidget);
    for (final workId in ['2', '3']) {
      final itemFinder =
          find.byKey(ValueKey<String>('unified-shelf-list-item-$workId'));
      final tileFinder = find.descendant(
        of: itemFinder,
        matching: find.byKey(
          ValueKey<String>('unified-shelf-list-tile-$workId'),
        ),
      );
      expect(tester.widget<ListTile>(tileFinder).selected, isTrue);
      expect(_borderColorForListItem(tester, itemFinder), isNot(Colors.transparent));
    }

    final firstItemFinder =
        find.byKey(const ValueKey<String>('unified-shelf-list-item-1'));
    final firstTileFinder = find.descendant(
      of: firstItemFinder,
      matching: find.byKey(
        const ValueKey<String>('unified-shelf-list-tile-1'),
      ),
    );
    expect(tester.widget<ListTile>(firstTileFinder).selected, isFalse);
    expect(_borderColorForListItem(tester, firstItemFinder), Colors.transparent);
  });

  testWidgets('initial selection uses first visible category when controller starts empty', (
    tester,
  ) async {
    final host = ShelfSelectionHostController();
    addTearDown(host.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedShelfPage(
          adapter: _FakeSelectableShelfAdapter(
            initialDisplayMode: LibraryDisplayMode.list,
            categories: [
              LibraryCategory(
                categoryId: 'comic',
                name: 'Comic',
                sortOrder: 0,
                createdAt: DateTime(2026, 1, 1),
              ),
              LibraryCategory(
                categoryId: 'novel',
                name: 'Novel',
                sortOrder: 1,
                createdAt: DateTime(2026, 1, 2),
              ),
              LibraryCategory(
                categoryId: 'default',
                name: 'Default',
                sortOrder: 2,
                createdAt: DateTime(2026, 1, 3),
              ),
            ],
            itemsByCategory: {
              'comic': [
                _item(workId: 'comic-1', title: 'Comic A'),
                _item(workId: 'comic-2', title: 'Comic B'),
              ],
              'novel': [
                _item(workId: 'novel-1', title: 'Novel A'),
              ],
              'default': List<LibraryWorkItem>.generate(
                15,
                (index) => _item(
                  workId: 'default-${index + 1}',
                  title: 'Default ${index + 1}',
                ),
              ),
            },
          ),
          selectionHost: host,
          onOpenWork: (context, workId) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(const ValueKey<String>('unified-shelf-list-item-comic-1')),
    );
    await tester.pumpAndSettle();

    expect(host.state?.activeCategoryId, 'comic');

    await tester.tap(find.byKey(const Key('selection-app-bar-select-all')));
    await tester.pumpAndSettle();

    expect(find.text('已选 2 项'), findsOneWidget);
    for (final workId in ['comic-1', 'comic-2']) {
      final itemFinder =
          find.byKey(ValueKey<String>('unified-shelf-list-item-$workId'));
      final tileFinder = find.descendant(
        of: itemFinder,
        matching: find.byKey(
          ValueKey<String>('unified-shelf-list-tile-$workId'),
        ),
      );
      expect(tester.widget<ListTile>(tileFinder).selected, isTrue);
      expect(
        _borderColorForListItem(tester, itemFinder),
        isNot(Colors.transparent),
      );
    }
    expect(
      find.byKey(const ValueKey<String>('unified-shelf-list-item-default-1')),
      findsNothing,
    );
  });
}

Color _borderColorForListItem(WidgetTester tester, Finder itemFinder) {
  final container = tester.widget<AnimatedContainer>(itemFinder);
  final decoration = container.decoration as BoxDecoration;
  final border = decoration.border as Border;
  return border.top.color;
}

LibraryWorkItem _item({
  required String workId,
  required String title,
  String? coverImageUrl,
}) {
  return LibraryWorkItem(
    workId: workId,
    categoryId: 'default',
    title: title,
    coverImageUrl: coverImageUrl,
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
    List<LibraryCategory>? categories,
    Map<String, List<LibraryWorkItem>>? itemsByCategory,
  })  : categories = categories ??
            [
              LibraryCategory(
                categoryId: 'default',
                name: 'Default',
                sortOrder: 0,
                createdAt: DateTime(2026, 1, 1),
              ),
            ],
        itemsByCategory = itemsByCategory ??
            {
              'default': [_item(workId: '1', title: 'Comic A')],
            };

  final LibraryDisplayMode initialDisplayMode;
  @override
  final ValueListenable<LibraryShelfTaskProgress?>? taskProgress;
  @override
  ValueListenable<LibraryShelfRefreshSignal?>? get shelfRefreshSignals => null;

  int refreshCalls = 0;
  final Future<Map<String, List<LibraryWorkItem>>> Function({
    required List<LibraryCategory> categories,
    required LibraryFilterSet filters,
    required LibraryShelfSortOption sortOption,
    required String keyword,
  })? onQuery;
  final List<LibraryCategory> categories;
  final Map<String, List<LibraryWorkItem>> itemsByCategory;

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
    return categories;
  }

  @override
  Future<List<LibraryWorkItem>> loadCategoryItems({required String categoryId}) async {
    return itemsByCategory[categoryId] ?? const <LibraryWorkItem>[];
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
    return itemsByCategory;
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

class _FakeSelectableShelfAdapter extends _FakeShelfAdapter
    implements ShelfSelectionActionAdapter {
  _FakeSelectableShelfAdapter({
    required super.initialDisplayMode,
    super.categories,
    super.itemsByCategory,
  });

  @override
  List<SelectionAction> get selectionActions => const <SelectionAction>[
        SelectionAction(
          id: SelectionActionIds.assignCategory,
          icon: Icons.edit_outlined,
          label: '设置分类',
        ),
        SelectionAction(
          id: SelectionActionIds.download,
          icon: Icons.download_outlined,
          label: '下载',
        ),
      ];

  @override
  Future<SelectionActionResult> runSelectionAction(
    SelectionActionExecutionRequest request,
  ) async {
    return const SelectionActionResult(message: 'noop');
  }
}
