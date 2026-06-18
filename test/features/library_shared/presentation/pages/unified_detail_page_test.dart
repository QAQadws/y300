import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_detail_page.dart';

void main() {
  testWidgets('UnifiedDetailPage renders header/chapter and FAB', (tester) async {
    ReaderRouteTarget? openedTarget;
    final adapter = _FakeDetailAdapter();
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {
            openedTarget = target;
          },
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-detail-header-section')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('unified-detail-header-section')),
        matching: find.byKey(const Key('unified-detail-header-actions-row')),
      ),
      findsOneWidget,
    );
    expect(find.text('测试作品'), findsWidgets);
    expect(find.byKey(const Key('unified-detail-author-row')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('unified-detail-author-row')),
        matching: find.byIcon(Icons.person_outlined),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<AnimatedOpacity>(find.ancestor(
        of: find.byKey(const Key('unified-detail-collapsed-title')),
        matching: find.byType(AnimatedOpacity),
      )),
      isA<AnimatedOpacity>().having((w) => w.opacity, 'opacity', 0),
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
      tester.widget<AnimatedOpacity>(find.ancestor(
        of: find.byKey(const Key('unified-detail-collapsed-title')),
        matching: find.byType(AnimatedOpacity),
      )),
      isA<AnimatedOpacity>().having((w) => w.opacity, 'opacity', 1),
    );

    // 章节列表位于下方 sliver，测试中需要滚动后再断言。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-e1')), findsOneWidget);
    expect(find.textContaining('Pid:5001'), findsOneWidget);

    expect(find.text('继续'), findsOneWidget);
    expect(find.byIcon(Icons.file_download), findsAtLeastNWidgets(1));
    expect(find.byIcon(Icons.filter_list), findsAtLeastNWidgets(1));
    expect(find.byKey(const Key('unified-detail-tag-strip')), findsOneWidget);
    expect(find.text('韩国漫画'), findsOneWidget);
    expect(find.text('自定义标签'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('unified-detail-chapter-e1')));
    await tester.pumpAndSettle();
    expect(openedTarget?.episodeId, 'e1');
    expect(adapter.markReadCallCount, 0);
    expect(adapter.loadChaptersCallCount, greaterThanOrEqualTo(2));

    await tester.longPress(find.byKey(const ValueKey<String>('unified-detail-chapter-e1')));
    await tester.pumpAndSettle();
    expect(find.text('删除该章节下载'), findsOneWidget);
  });

  testWidgets('UnifiedDetailPage edits custom metadata through optional adapter', (tester) async {
    final adapter = _EditableDetailAdapter();
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unified-detail-edit-metadata')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-detail-metadata-sheet')), findsOneWidget);
    expect(find.text('来源标题：来源标题'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('unified-detail-custom-title-input')),
          )
          .controller
          ?.text,
      '测试作品',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('unified-detail-custom-author-input')),
          )
          .controller
          ?.text,
      '作者A',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('unified-detail-custom-group-input')),
          )
          .controller
          ?.text,
      '汉化组A',
    );

    await tester.enterText(
      find.byKey(const Key('unified-detail-custom-title-input')),
      '新标题',
    );
    await tester.enterText(
      find.byKey(const Key('unified-detail-custom-author-input')),
      '新作者',
    );
    await tester.enterText(
      find.byKey(const Key('unified-detail-custom-group-input')),
      '',
    );
    await tester.enterText(
      find.byKey(const Key('unified-detail-custom-search-title-input')),
      '刷新关键词',
    );
    await tester.tap(find.byKey(const Key('unified-detail-save-metadata')));
    await tester.pumpAndSettle();

    expect(adapter.lastCustomTitle, '新标题');
    expect(adapter.lastCustomAuthor, '新作者');
    expect(adapter.lastCustomTranslationGroup, isNull);
    expect(adapter.lastCustomSearchTitle, '刷新关键词');
    expect(find.text('新标题'), findsWidgets);
  });

  testWidgets('UnifiedDetailPage header gradient follows scaffold background', (tester) async {
    const pageBackground = Color(0xFF123456);
    final adapter = _FakeDetailAdapter(
      coverLocalPath: 'missing-y300-detail-cover.png',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          scaffoldBackgroundColor: pageBackground,
        ),
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, pageBackground);
    expect(_headerGradient(tester).colors.last, pageBackground);
    expect(tester.widget<ColoredBox>(
      find.byKey(const Key('unified-detail-header-seam-bridge')),
    ).color, pageBackground);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(tester.widget<AppBar>(find.byType(AppBar)).backgroundColor, pageBackground);
  });

  testWidgets('UnifiedDetailPage no-cover header remains available with custom theme', (tester) async {
    const pageBackground = Color(0xFFF1F3F5);
    final adapter = _FakeDetailAdapter();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
          scaffoldBackgroundColor: pageBackground,
        ),
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-detail-header-section')), findsOneWidget);
    expect(find.byKey(const Key('unified-detail-hero-title')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('unified-detail-header-section')),
        matching: find.byKey(const Key('unified-detail-header-actions-row')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('UnifiedDetailPage builds dark theme chrome and sheets', (tester) async {
    final adapter = _EditableDetailAdapter();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byKey(const Key('unified-detail-header-section')), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsAtLeastNWidgets(2));

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.filter_list),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unified-detail-chapter-filter-sheet')), findsOneWidget);
    expect(find.byKey(const Key('unified-detail-sort-field')), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unified-detail-edit-metadata')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unified-detail-metadata-sheet')), findsOneWidget);
  });

  testWidgets('UnifiedDetailPage header seam bridge does not block actions', (tester) async {
    final adapter = _FakeDetailAdapter()
      ..refreshResult = DetailRefreshResult.queued(
        estimatedDuration: const Duration(milliseconds: 10500),
        queuePosition: 1,
      );

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-detail-header-seam-bridge')), findsOneWidget);
    await tester.tap(find.text('更新').first);
    await tester.pumpAndSettle();

    expect(find.text('更新预计耗时10.5s'), findsOneWidget);
  });

  testWidgets('UnifiedDetailPage renders chapter progress badge', (tester) async {
    final adapter = _FakeDetailAdapter(
      progressInfo: const LibraryChapterProgressInfo(
        label: '第 3 页',
        isCurrent: true,
        fraction: 0.3,
        semanticLabel: '当前读到第 3 页',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-progress-e1')), findsOneWidget);
    expect(find.text('第 3 页'), findsOneWidget);
  });

  testWidgets('UnifiedDetailPage renders explicit chapter status badges', (tester) async {
    final adapter = _FakeDetailAdapter(
      progressInfo: const LibraryChapterProgressInfo(
        label: '已读 42%',
        isCurrent: true,
        fraction: 0.42,
      ),
      isBookmarked: true,
      isDownloaded: true,
      isRead: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-progress-e1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-bookmark-badge-e1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-downloaded-badge-e1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-read-badge-e1')), findsOneWidget);
    expect(find.text('书签'), findsOneWidget);
    expect(find.text('已下载'), findsOneWidget);
    expect(find.text('已读'), findsOneWidget);
  });

  testWidgets('UnifiedDetailPage chapter toolbar opens filter sheet and filters unread', (tester) async {
    final adapter = _FakeDetailAdapter(
      secondIsRead: true,
      secondIsDownloaded: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('unified-detail-chapter-toolbar')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.byKey(const Key('unified-detail-chapter-toolbar')), findsOneWidget);
    expect(find.text('共 2 章'), findsOneWidget);
    expect(find.text('全部章节'), findsOneWidget);
    expect(find.text('章节升序'), findsOneWidget);

    await tester.tap(find.text('筛选').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-detail-chapter-filter-sheet')), findsOneWidget);
    expect(find.byKey(const Key('unified-detail-filter-downloaded')), findsOneWidget);
    expect(find.byKey(const Key('unified-detail-filter-unread')), findsOneWidget);
    expect(find.byKey(const Key('unified-detail-filter-bookmarked')), findsOneWidget);
    expect(find.byKey(const Key('unified-detail-sort-field')), findsOneWidget);
    expect(find.byKey(const Key('unified-detail-sort-direction')), findsOneWidget);

    await tester.tap(find.byKey(const Key('unified-detail-filter-unread')));
    await tester.ensureVisible(find.byKey(const Key('unified-detail-apply-filter-sort')));
    await tester.tap(find.byKey(const Key('unified-detail-apply-filter-sort')));
    await tester.pumpAndSettle();

    expect(find.text('未读'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-e1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-e2')), findsNothing);
    expect(adapter.lastFilters.unread, TriStateFilterValue.include);
  });

  testWidgets('UnifiedDetailPage chapter filter keeps bookmark semantics', (tester) async {
    final adapter = _FakeDetailAdapter(
      secondIsBookmarked: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('unified-detail-chapter-toolbar')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('筛选').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unified-detail-filter-bookmarked')));
    await tester.ensureVisible(find.byKey(const Key('unified-detail-apply-filter-sort')));
    await tester.tap(find.byKey(const Key('unified-detail-apply-filter-sort')));
    await tester.pumpAndSettle();

    expect(find.text('已加书签'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-e1')), findsNothing);
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-e2')), findsOneWidget);
    expect(adapter.lastFilters.bookmarked, TriStateFilterValue.include);
  });

  testWidgets('UnifiedDetailPage chapter toolbar toggles sort direction', (tester) async {
    final adapter = _FakeDetailAdapter(includeSecondChapter: true);

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('unified-detail-chapter-toolbar')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('章节升序'), findsOneWidget);
    var chapterTiles = tester.widgetList<Material>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Material &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('unified-detail-chapter-'),
      ),
    ).toList();
    expect((chapterTiles.first.key! as ValueKey<String>).value, 'unified-detail-chapter-e1');

    await tester.tap(find.text('章节升序'));
    await tester.pumpAndSettle();

    expect(find.text('章节降序'), findsOneWidget);
    chapterTiles = tester.widgetList<Material>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Material &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('unified-detail-chapter-'),
      ),
    ).toList();
    expect((chapterTiles.first.key! as ValueKey<String>).value, 'unified-detail-chapter-e2');
    expect(adapter.lastSortOption.direction, LibrarySortDirection.desc);
  });

  testWidgets('UnifiedDetailPage chapter filter sheet applies sort field and direction', (tester) async {
    final adapter = _FakeDetailAdapter(includeSecondChapter: true);

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('unified-detail-chapter-toolbar')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.tap(find.text('筛选').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unified-detail-sort-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按名称').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('降序').last);
    await tester.ensureVisible(find.byKey(const Key('unified-detail-apply-filter-sort')));
    await tester.tap(find.byKey(const Key('unified-detail-apply-filter-sort')));
    await tester.pumpAndSettle();

    expect(find.text('名称降序'), findsOneWidget);
    expect(adapter.lastSortOption.field, LibraryChapterSortField.name);
    expect(adapter.lastSortOption.direction, LibrarySortDirection.desc);

    final chapterTiles = tester.widgetList<Material>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Material &&
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('unified-detail-chapter-'),
      ),
    ).toList();
    expect((chapterTiles.first.key! as ValueKey<String>).value, 'unified-detail-chapter-e2');
  });

  testWidgets('UnifiedDetailPage toggles chapter bookmark from row button', (tester) async {
    final adapter = _FakeDetailAdapter();

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('unified-detail-chapter-bookmark-button-e1')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-bookmark-badge-e1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('unified-detail-chapter-bookmark-button-e1')));
    await tester.pumpAndSettle();

    expect(adapter.isBookmarked, isTrue);
    expect(adapter.lastBookmarkEpisodeId, 'e1');
    expect(adapter.loadChaptersCallCount, greaterThanOrEqualTo(2));
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-bookmark-badge-e1')), findsOneWidget);
  });

  testWidgets('UnifiedDetailPage keeps download action and downloaded badge', (tester) async {
    final adapter = _FakeDetailAdapter();

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('下载该章节'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-downloaded-badge-e1')), findsNothing);

    await tester.tap(find.byTooltip('下载该章节'));
    await tester.pumpAndSettle();

    expect(adapter.isDownloaded, isTrue);
    expect(adapter.lastDownloadedEpisodeId, 'e1');
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-downloaded-badge-e1')), findsOneWidget);

    await tester.tap(find.byTooltip('已下载，点击删除下载'));
    await tester.pumpAndSettle();

    expect(adapter.isDownloaded, isFalse);
    expect(adapter.lastDeletedDownloadEpisodeId, 'e1');
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-downloaded-badge-e1')), findsNothing);
  });

  testWidgets('UnifiedDetailPage omits chapter progress badge when progress is null', (tester) async {
    final adapter = _FakeDetailAdapter();

    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-progress-e1')), findsNothing);
  });

  testWidgets('UnifiedDetailPage shows refresh queue snackbar', (tester) async {
    final adapter = _FakeDetailAdapter()
      ..refreshResult = DetailRefreshResult.queued(
        estimatedDuration: const Duration(milliseconds: 10500),
        queuePosition: 1,
      );
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('更新').first);
    await tester.pumpAndSettle();

    expect(find.text('更新预计耗时10.5s'), findsOneWidget);
  });

  testWidgets('UnifiedDetailPage shows refresh fallback snackbars', (tester) async {
    final adapter = _FakeDetailAdapter();
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.text('更新').first);
    await tester.pumpAndSettle();
    expect(find.text('已更新'), findsOneWidget);

    adapter.refreshResult = DetailRefreshResult.skipped;
    await tester.tap(find.text('更新').first);
    await tester.pumpAndSettle();
    expect(find.text('暂无可更新内容'), findsOneWidget);
  });

  testWidgets('UnifiedDetailPage shows error panel and retries initial load', (tester) async {
    final adapter = _FakeDetailAdapter()..failLoadHeaderOnce = true;
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-detail-error-panel')), findsOneWidget);
    expect(find.byKey(const Key('unified-detail-error-retry')), findsOneWidget);
    expect(find.textContaining('加载失败'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('unified-detail-error-retry')));
    await tester.tap(find.byKey(const Key('unified-detail-error-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-detail-error-panel')), findsNothing);
    expect(find.text('测试作品'), findsWidgets);
  });

  testWidgets('UnifiedDetailPage keeps existing content when chapter reload fails', (tester) async {
    final adapter = _FakeDetailAdapter();
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('unified-detail-chapter-bookmark-button-e1')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();

    adapter.failLoadChaptersOnce = true;
    await tester.tap(find.byKey(const ValueKey<String>('unified-detail-chapter-bookmark-button-e1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-detail-error-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-e1')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('unified-detail-error-retry')));
    await tester.tap(find.byKey(const Key('unified-detail-error-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('unified-detail-error-panel')), findsNothing);
  });

  testWidgets('UnifiedDetailPage reports chapter download failures without stale spinner', (tester) async {
    final adapter = _FakeDetailAdapter()..failMarkDownload = true;
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('下载该章节'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('下载该章节'));
    await tester.pumpAndSettle();

    expect(find.textContaining('下载失败'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-downloaded-badge-e1')), findsNothing);
  });

  testWidgets('UnifiedDetailPage reports delete download failures and keeps badge', (tester) async {
    final adapter = _FakeDetailAdapter(
      isDownloaded: true,
    )..failDeleteDownload = true;
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('已下载，点击删除下载'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('已下载，点击删除下载'));
    await tester.pumpAndSettle();

    expect(find.textContaining('删除下载失败'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('unified-detail-chapter-downloaded-badge-e1')), findsOneWidget);
  });
}

class _FakeDetailAdapter implements DetailModuleAdapter {
  _FakeDetailAdapter({
    this.coverLocalPath,
    this.progressInfo,
    this.isBookmarked = false,
    this.isDownloaded = false,
    this.isRead = false,
    this.includeSecondChapter = false,
    this.secondIsBookmarked = false,
    this.secondIsDownloaded = false,
    this.secondIsRead = false,
  });

  int markReadCallCount = 0;
  int loadChaptersCallCount = 0;
  String? lastBookmarkEpisodeId;
  String? lastDownloadedEpisodeId;
  String? lastDeletedDownloadEpisodeId;
  LibraryFilterSet lastFilters = LibraryFilterSet.defaults;
  LibraryChapterSortOption lastSortOption = LibraryChapterSortOption.defaults;
  DetailRefreshResult refreshResult = DetailRefreshResult.immediate;
  bool failLoadHeaderOnce = false;
  bool failLoadChaptersOnce = false;
  bool failMarkDownload = false;
  bool failDeleteDownload = false;
  final String? coverLocalPath;
  final LibraryChapterProgressInfo? progressInfo;
  bool isBookmarked;
  bool isDownloaded;
  bool isRead;
  final bool includeSecondChapter;
  final bool secondIsBookmarked;
  final bool secondIsDownloaded;
  final bool secondIsRead;

  @override
  Future<void> clearAllReadState({required String workId}) async {
    isRead = false;
  }

  @override
  Future<void> deleteChapterDownload({
    required String workId,
    required String episodeId,
  }) async {
    if (failDeleteDownload) {
      throw StateError('delete failed');
    }
    lastDeletedDownloadEpisodeId = episodeId;
    isDownloaded = false;
  }

  @override
  Future<void> downloadAll({required String workId}) async {}

  @override
  Future<void> downloadUnread({required String workId}) async {}

  @override
  Future<ReaderRouteTarget?> getReaderRouteTarget({
    required String workId,
    required bool preferContinue,
  }) async {
    return ReaderRouteTarget(workId: workId, episodeId: 'e1');
  }

  @override
  Future<ThreadRouteTarget?> getThreadRouteTarget({required String workId}) async {
    return const ThreadRouteTarget(tid: '100');
  }

  @override
  Future<List<LibraryChapterItem>> loadChapters({
    required String workId,
    required LibraryFilterSet filters,
    required LibraryChapterSortOption sortOption,
  }) async {
    if (failLoadChaptersOnce) {
      failLoadChaptersOnce = false;
      throw StateError('chapters failed');
    }
    loadChaptersCallCount++;
    lastFilters = filters;
    lastSortOption = sortOption;
    final chapters = [
      LibraryChapterItem(
        episodeId: 'e1',
        workId: 'work-1',
        title: '第1章',
        orderIndex: 1,
        sourceTid: '100',
        sourcePid: '5001',
        isBookmarked: isBookmarked,
        isDownloaded: isDownloaded,
        isRead: isRead,
        progressInfo: progressInfo,
      ),
      if (includeSecondChapter || secondIsBookmarked || secondIsDownloaded || secondIsRead)
        LibraryChapterItem(
          episodeId: 'e2',
          workId: 'work-1',
          title: '第2章',
          orderIndex: 2,
          sourceTid: '101',
          sourcePid: '5002',
          isBookmarked: secondIsBookmarked,
          isDownloaded: secondIsDownloaded,
          isRead: secondIsRead,
        ),
    ];
    final filtered = chapters.where((chapter) {
      return _match(filters.downloaded, chapter.isDownloaded) &&
          _match(filters.unread, !chapter.isRead) &&
          _match(filters.bookmarked, chapter.isBookmarked);
    }).toList();
    filtered.sort((a, b) {
      final compared = switch (sortOption.field) {
        LibraryChapterSortField.chapterIndex => a.orderIndex.compareTo(b.orderIndex),
        LibraryChapterSortField.date => (a.publishTimeText ?? '').compareTo(b.publishTimeText ?? ''),
        LibraryChapterSortField.name => a.title.compareTo(b.title),
        LibraryChapterSortField.tid => (a.sourceTid ?? '').compareTo(b.sourceTid ?? ''),
      };
      return sortOption.direction == LibrarySortDirection.asc ? compared : -compared;
    });
    return filtered;
  }

  bool _match(TriStateFilterValue filter, bool actual) {
    return switch (filter) {
      TriStateFilterValue.ignore => true,
      TriStateFilterValue.include => actual,
      TriStateFilterValue.exclude => !actual,
    };
  }

  @override
  Future<LibraryDetailHeader> loadHeader({required String workId}) async {
    if (failLoadHeaderOnce) {
      failLoadHeaderOnce = false;
      throw StateError('header failed');
    }
    return LibraryDetailHeader(
      workId: 'work-1',
      title: '测试作品',
      author: '作者A',
      coverLocalPath: coverLocalPath,
      inShelf: true,
      intro: '这是一段简介',
      sourceTypeId: '398',
      sourceTagName: '韩国漫画',
      customTags: <LibraryTag>[
        LibraryTag(
          tagId: 'tag-1',
          name: '自定义标签',
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
    );
  }

  @override
  Future<void> markChapterBookmarked({
    required String workId,
    required String episodeId,
    required bool isBookmarked,
  }) async {
    lastBookmarkEpisodeId = episodeId;
    this.isBookmarked = isBookmarked;
  }

  @override
  Future<void> markChapterDownloaded({
    required String workId,
    required String episodeId,
    required bool isDownloaded,
  }) async {
    if (failMarkDownload) {
      throw StateError('download failed');
    }
    lastDownloadedEpisodeId = episodeId;
    this.isDownloaded = isDownloaded;
  }

  @override
  Future<void> markChapterRead({
    required String workId,
    required String episodeId,
    required bool isRead,
  }) async {
    markReadCallCount++;
    this.isRead = isRead;
  }

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.novel;

  @override
  Future<DetailRefreshResult> refreshWork({required String workId}) async {
    return refreshResult;
  }

  @override
  Future<void> updateIntro({
    required String workId,
    required String intro,
  }) async {}

  @override
  Future<void> moveWorkToCategory({
    required String workId,
    required String toCategoryId,
  }) async {}

  @override
  Future<List<LibraryCategory>> loadCategories() async {
    return const [];
  }

  @override
  Future<List<LibraryTag>> getWorkTags({required String workId}) async {
    return const [];
  }

  @override
  Future<List<LibraryTag>> getAllTags() async {
    return const [];
  }

  @override
  Future<void> addExistingTagToWork({
    required String workId,
    required String tagId,
  }) async {}

  @override
  Future<void> addNewTagToWork({
    required String workId,
    required String tagName,
  }) async {}

  @override
  Future<void> removeTagFromWork({
    required String workId,
    required String tagId,
  }) async {}
}

class _EditableDetailAdapter extends _FakeDetailAdapter implements DetailMetadataEditor {
  String title = '测试作品';
  String? author = '作者A';
  String? translationGroup = '汉化组A';
  String? lastCustomTitle;
  String? lastCustomAuthor;
  String? lastCustomTranslationGroup;
  String? lastCustomSearchTitle;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.comic;

  @override
  Future<LibraryDetailHeader> loadHeader({required String workId}) async {
    return LibraryDetailHeader(
      workId: 'work-1',
      title: title,
      sourceTitle: '来源标题',
      customTitle: lastCustomTitle,
      author: author,
      sourceAuthor: '来源作者',
      customAuthor: lastCustomAuthor,
      translationGroup: translationGroup,
      sourceTranslationGroup: '来源汉化组',
      customTranslationGroup: lastCustomTranslationGroup,
      customSearchTitle: lastCustomSearchTitle,
      inShelf: true,
      intro: '这是一段简介',
    );
  }

  @override
  Future<void> updateCustomMetadata({
    required String workId,
    String? customTitle,
    String? customAuthor,
    String? customTranslationGroup,
    String? customSearchTitle,
  }) async {
    lastCustomTitle = customTitle;
    lastCustomAuthor = customAuthor;
    lastCustomTranslationGroup = customTranslationGroup;
    lastCustomSearchTitle = customSearchTitle;
    title = customTitle ?? '来源标题';
    author = customAuthor ?? '来源作者';
    translationGroup = customTranslationGroup ?? '来源汉化组';
  }
}

LinearGradient _headerGradient(WidgetTester tester) {
  final gradientBox = tester.widget<DecoratedBox>(
    find.byKey(const Key('unified-detail-header-gradient')),
  );
  final decoration = gradientBox.decoration as BoxDecoration;
  return decoration.gradient! as LinearGradient;
}

