import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/app/theme/app_theme.dart';
import 'package:y300/features/library_shared/domain/contracts/detail_module_adapter.dart';
import 'package:y300/features/library_shared/domain/models/library_filter_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/models/library_sort_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/presentation/pages/unified_detail_page.dart';

void main() {
  testWidgets('UnifiedDetailPage renders header/chapter and FAB', (
    tester,
  ) async {
    ReaderRouteTarget? openedTarget;
    final adapter = _FakeDetailAdapter(
      module: LibraryModuleKey.comic,
      isDownloaded: true,
    );
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

    expect(
      find.byKey(const Key('unified-detail-header-section')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('unified-detail-header-section')),
        matching: find.byKey(const Key('unified-detail-header-actions-row')),
      ),
      findsOneWidget,
    );
    expect(find.text('测试作品'), findsWidgets);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('unified-detail-hero-title')))
          .maxLines,
      3,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('unified-detail-hero-title')))
          .style
          ?.fontWeight,
      FontWeight.normal,
    );
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).titleTextStyle?.fontWeight,
      FontWeight.normal,
    );
    expect(find.byKey(const Key('unified-detail-author-row')), findsOneWidget);
    expect(find.text('UID: 10001'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('unified-detail-author-row')),
        matching: find.byIcon(Icons.person_outlined),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Opacity>(
        find.ancestor(
          of: find.byKey(const Key('unified-detail-collapsed-title')),
          matching: find.byType(Opacity),
        ),
      ),
      isA<Opacity>().having((w) => w.opacity, 'opacity', 0),
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Opacity>(
        find.ancestor(
          of: find.byKey(const Key('unified-detail-collapsed-title')),
          matching: find.byType(Opacity),
        ),
      ),
      isA<Opacity>().having((w) => w.opacity, 'opacity', 1),
    );

    // 章节列表位于下方 sliver，测试中需要滚动后再断言。
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text('第1章')).style?.fontWeight,
      FontWeight.normal,
    );
    expect(find.textContaining('Pid:5001'), findsOneWidget);

    expect(find.text('继续'), findsOneWidget);
    expect(find.byIcon(Icons.file_download), findsAtLeastNWidgets(1));
    expect(find.byIcon(Icons.filter_list), findsAtLeastNWidgets(1));
    expect(find.byKey(const Key('unified-detail-tag-strip')), findsOneWidget);
    expect(find.text('韩国漫画'), findsOneWidget);
    final tagWidth = tester
        .getSize(find.byKey(const Key('unified-detail-source-tag')))
        .width;
    final labelWidth = tester.getSize(find.text('韩国漫画')).width;
    expect(tagWidth, closeTo(labelWidth + 22, 1));

    await tester.tap(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
    );
    await tester.pumpAndSettle();
    expect(openedTarget?.episodeId, 'e1');
    expect(adapter.markReadCallCount, 0);
    expect(adapter.loadChaptersCallCount, greaterThanOrEqualTo(2));

    await tester.longPress(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('删除该章节下载'), findsOneWidget);
  });

  testWidgets(
    'Phase 0 baseline commits initial detail content and refreshes in place',
    (tester) async {
      final adapter = _FakeDetailAdapter();
      var presentationCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedDetailPage(
            adapter: adapter,
            workId: 'work-1',
            onOpenReader: (context, target) async {},
            onOpenThread: (context, target) async {},
            onFirstContentPresented: (header, chapters) {
              presentationCount++;
            },
          ),
        ),
      );

      expect(
        find.byKey(const Key('unified-detail-header-section')),
        findsNothing,
      );

      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('unified-detail-header-section')),
        findsOneWidget,
      );
      expect(adapter.loadHeaderCallCount, 1);
      expect(adapter.loadChaptersCallCount, 1);
      expect(adapter.refreshWorkCallCount, 0);
      expect(presentationCount, 1);

      await tester.tap(find.text('更新').first);
      await tester.pumpAndSettle();

      expect(adapter.refreshWorkCallCount, 1);
      expect(adapter.loadHeaderCallCount, 2);
      expect(adapter.loadChaptersCallCount, 2);
      expect(
        find.byKey(const Key('unified-detail-header-section')),
        findsOneWidget,
      );
      expect(presentationCount, 1);
    },
  );

  testWidgets(
    'UnifiedDetailPage edits custom metadata through optional adapter',
    (tester) async {
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

      expect(
        find.byKey(const Key('unified-detail-metadata-sheet')),
        findsOneWidget,
      );
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
    },
  );

  testWidgets('UnifiedDetailPage only exposes parsed source tag', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: _FakeDetailAdapter(),
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('韩国漫画'), findsOneWidget);
    expect(find.text('自定义标签'), findsNothing);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('管理标签'), findsNothing);
    expect(find.text('添加标签'), findsNothing);
    expect(find.text('移除标签'), findsNothing);
    expect(find.text('配置目录'), findsNothing);
  });

  testWidgets('UnifiedDetailPage configures catalog through optional adapter', (
    tester,
  ) async {
    final adapter = _CatalogEditableDetailAdapter();
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
    await tester.tap(find.byKey(const Key('unified-detail-configure-catalog')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('unified-detail-catalog-sheet')),
      findsOneWidget,
    );
    expect(
      find.text('来源目录：https://bbs.yamibo.com/misc.php?mod=tag&id=1'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('unified-detail-catalog-url-input')),
          )
          .controller
          ?.text,
      'https://bbs.yamibo.com/misc.php?mod=tag&id=1',
    );

    await tester.enterText(
      find.byKey(const Key('unified-detail-catalog-url-input')),
      'https://bbs.yamibo.com/misc.php?mod=tag&id=2',
    );
    await tester.tap(find.byKey(const Key('unified-detail-save-catalog')));
    await tester.pumpAndSettle();

    expect(
      adapter.lastCatalogUrl,
      'https://bbs.yamibo.com/misc.php?mod=tag&id=2',
    );
    expect(find.byKey(const Key('unified-detail-catalog-sheet')), findsNothing);
  });

  testWidgets(
    'UnifiedDetailPage shows cover-edit menu only when editor + picker present',
    (tester) async {
      final adapter = _CoverEditableDetailAdapter();
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedDetailPage(
            adapter: adapter,
            workId: 'work-1',
            onOpenReader: (context, target) async {},
            onOpenThread: (context, target) async {},
            pickCoverImage: () async => null,
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('unified-detail-set-cover')), findsOneWidget);
      // 无自定义封面时不显示“取消封面”。
      expect(
        find.byKey(const Key('unified-detail-remove-cover')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'UnifiedDetailPage hides cover-edit menu when picker not injected',
    (tester) async {
      final adapter = _CoverEditableDetailAdapter();
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

      expect(find.byKey(const Key('unified-detail-set-cover')), findsNothing);
    },
  );

  testWidgets('UnifiedDetailPage removes custom cover through cover editor', (
    tester,
  ) async {
    final adapter = _CoverEditableDetailAdapter(hasCustomCover: true);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
          pickCoverImage: () async => null,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('unified-detail-remove-cover')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('unified-detail-remove-cover')));
    await tester.pumpAndSettle();

    expect(adapter.coverRemoved, isTrue);
    expect(find.text('已取消封面'), findsOneWidget);
  });

  testWidgets('UnifiedDetailPage can cancel a source cover by adapter policy', (
    tester,
  ) async {
    final adapter = _CoverEditableDetailAdapter(hasSourceCover: true);
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
          pickCoverImage: () async => null,
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('unified-detail-remove-cover')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('unified-detail-remove-cover')));
    await tester.pumpAndSettle();

    expect(adapter.coverRemoved, isTrue);
    expect(
      find.byKey(const Key('unified-detail-plain-header')),
      findsOneWidget,
    );
  });

  testWidgets('UnifiedDetailPage header gradient follows scaffold background', (
    tester,
  ) async {
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

    expect(tester.widget<AppBar>(find.byType(AppBar)).backgroundColor?.a, 0);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      pageBackground,
    );
    expect(_headerGradient(tester).colors.last, pageBackground);
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const Key('unified-detail-header-seam-bridge')),
          )
          .color,
      pageBackground,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));

    final appearingAlpha = tester
        .widget<AppBar>(find.byType(AppBar))
        .backgroundColor!
        .a;
    expect(appearingAlpha, greaterThan(0));
    expect(appearingAlpha, lessThan(1));

    await tester.pumpAndSettle();

    expect(
      tester.widget<AppBar>(find.byType(AppBar)).backgroundColor,
      pageBackground,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    final disappearingAlpha = tester
        .widget<AppBar>(find.byType(AppBar))
        .backgroundColor!
        .a;
    expect(disappearingAlpha, greaterThan(0));
    expect(disappearingAlpha, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.widget<AppBar>(find.byType(AppBar)).backgroundColor?.a, 0);
  });

  testWidgets(
    'UnifiedDetailPage uses dark hero metadata on a light covered header',
    (tester) async {
      const pageBackground = Color(0xFFF1F3F5);
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

      expect(
        tester
            .widget<Text>(find.byKey(const Key('unified-detail-hero-title')))
            .style
            ?.color,
        Colors.black,
      );
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).foregroundColor,
        Colors.white,
      );
    },
  );

  testWidgets(
    'UnifiedDetailPage no-cover header remains available with custom theme',
    (tester) async {
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

      expect(
        find.byKey(const Key('unified-detail-header-section')),
        findsOneWidget,
      );
      final plainHeaderHeight = tester
          .getSize(find.byKey(const Key('unified-detail-plain-header')))
          .height;
      expect(
        find.byKey(const Key('unified-detail-hero-title')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('unified-detail-plain-header')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Align>(
              find.byKey(const Key('unified-detail-plain-header-content')),
            )
            .alignment,
        Alignment.centerLeft,
      );
      expect(
        find.byKey(const Key('unified-detail-header-gradient')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('unified-detail-header-seam-bridge')),
        findsNothing,
      );
      expect(find.byType(ImageFiltered), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('unified-detail-header-section')),
          matching: find.byKey(const Key('unified-detail-header-actions-row')),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
            scaffoldBackgroundColor: pageBackground,
          ),
          home: UnifiedDetailPage(
            key: const ValueKey('covered-detail-page'),
            adapter: _FakeDetailAdapter(
              coverLocalPath: 'missing-y300-detail-cover.png',
            ),
            workId: 'work-1',
            onOpenReader: (context, target) async {},
            onOpenThread: (context, target) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .getSize(find.byKey(const Key('unified-detail-cover-header')))
            .height,
        plainHeaderHeight,
      );
    },
  );

  testWidgets('UnifiedDetailPage builds dark theme chrome and sheets', (
    tester,
  ) async {
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
    expect(
      find.byKey(const Key('unified-detail-header-section')),
      findsOneWidget,
    );
    expect(find.byType(PopupMenuButton<String>), findsAtLeastNWidgets(2));

    await tester.tap(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.filter_list),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('unified-detail-chapter-filter-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('unified-detail-sort-source')), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unified-detail-edit-metadata')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('unified-detail-metadata-sheet')),
      findsOneWidget,
    );
  });

  testWidgets('UnifiedDetailPage header seam bridge does not block actions', (
    tester,
  ) async {
    final adapter =
        _FakeDetailAdapter(coverLocalPath: 'missing-y300-detail-cover.png')
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

    expect(
      find.byKey(const Key('unified-detail-header-seam-bridge')),
      findsOneWidget,
    );
    await tester.tap(find.text('更新').first);
    await tester.pumpAndSettle();

    expect(find.text('更新预计耗时10.5s'), findsOneWidget);
  });

  testWidgets('UnifiedDetailPage renders comic progress beside source id', (
    tester,
  ) async {
    final adapter = _FakeDetailAdapter(
      module: LibraryModuleKey.comic,
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

    expect(
      find.byKey(
        const ValueKey<String>('unified-detail-chapter-inline-progress-e1'),
      ),
      findsOneWidget,
    );
    final progressLine = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('unified-detail-chapter-inline-progress-e1'),
        ),
        matching: find.byType(RichText),
      ),
    );
    expect(progressLine.text.toPlainText(), contains('  ·  第 3 页'));
    expect(
      find.byKey(const ValueKey<String>('unified-detail-chapter-progress-e1')),
      findsNothing,
    );
  });

  testWidgets('UnifiedDetailPage renders novel last-read marker inline', (
    tester,
  ) async {
    final adapter = _FakeDetailAdapter(
      progressInfo: const LibraryChapterProgressInfo(
        label: '上次阅读',
        isCurrent: true,
        fraction: 0.42,
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

    expect(
      find.byKey(const ValueKey<String>('unified-detail-chapter-progress-e1')),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey<String>('unified-detail-chapter-inline-progress-e1'),
      ),
      findsOneWidget,
    );
    final progressLine = tester.widget<RichText>(
      find.descendant(
        of: find.byKey(
          const ValueKey<String>('unified-detail-chapter-inline-progress-e1'),
        ),
        matching: find.byType(RichText),
      ),
    );
    expect(progressLine.text.toPlainText(), contains('  ·  上次阅读'));
  });

  testWidgets(
    'UnifiedDetailPage renders chapter indicators without status text',
    (tester) async {
      final adapter = _FakeDetailAdapter(
        module: LibraryModuleKey.comic,
        progressInfo: const LibraryChapterProgressInfo(
          label: '第 3 页',
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

      expect(
        find.byKey(
          const ValueKey<String>('unified-detail-chapter-inline-progress-e1'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>(
            'unified-detail-chapter-bookmark-indicator-e1',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('unified-detail-chapter-downloaded-badge-e1'),
        ),
        findsNothing,
      );
      expect(
        find.byKey(
          const ValueKey<String>('unified-detail-chapter-read-badge-e1'),
        ),
        findsNothing,
      );
      expect(find.text('书签'), findsNothing);
      expect(
        find.byKey(
          const ValueKey<String>('unified-detail-chapter-bookmark-button-e1'),
        ),
        findsNothing,
      );
      expect(find.text('已下载'), findsNothing);
      expect(find.byTooltip('已下载，点击删除下载'), findsOneWidget);
      expect(find.text('已读'), findsNothing);
    },
  );

  testWidgets(
    'UnifiedDetailPage AppBar filter opens sheet and filters unread',
    (tester) async {
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

      expect(
        find.byKey(const Key('unified-detail-chapter-toolbar')),
        findsOneWidget,
      );
      expect(find.text('共2章'), findsOneWidget);
      expect(find.text('全部章节'), findsNothing);

      await tester.tap(find.byKey(const Key('unified-detail-appbar-filter')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('unified-detail-chapter-filter-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('unified-detail-filter-downloaded')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('unified-detail-filter-unread')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('unified-detail-filter-bookmarked')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('unified-detail-sort-source')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('unified-detail-sort-direction')),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('unified-detail-filter-unread')));
      await tester.ensureVisible(
        find.byKey(const Key('unified-detail-apply-filter-sort')),
      );
      await tester.tap(
        find.byKey(const Key('unified-detail-apply-filter-sort')),
      );
      await tester.pumpAndSettle();

      expect(find.text('未读'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('unified-detail-chapter-e2')),
        findsNothing,
      );
      expect(adapter.lastFilters.unread, TriStateFilterValue.include);

      await tester.drag(
        find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
        const Offset(500, 0),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
        findsNothing,
      );
    },
  );

  testWidgets('UnifiedDetailPage chapter filter keeps bookmark semantics', (
    tester,
  ) async {
    final adapter = _FakeDetailAdapter(secondIsBookmarked: true);

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

    await tester.tap(find.byKey(const Key('unified-detail-appbar-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('unified-detail-filter-bookmarked')));
    await tester.ensureVisible(
      find.byKey(const Key('unified-detail-apply-filter-sort')),
    );
    await tester.tap(find.byKey(const Key('unified-detail-apply-filter-sort')));
    await tester.pumpAndSettle();

    expect(find.text('已加书签'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e2')),
      findsOneWidget,
    );
    expect(adapter.lastFilters.bookmarked, TriStateFilterValue.include);
  });

  testWidgets('UnifiedDetailPage chapter toolbar omits duplicate actions', (
    tester,
  ) async {
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

    final toolbar = find.byKey(const Key('unified-detail-chapter-toolbar'));
    expect(find.text('共2章'), findsOneWidget);
    expect(find.text('全部章节'), findsNothing);
    expect(
      find.descendant(of: toolbar, matching: find.byIcon(Icons.filter_list)),
      findsNothing,
    );
    expect(
      find.descendant(of: toolbar, matching: find.byIcon(Icons.arrow_upward)),
      findsNothing,
    );
    expect(
      find.descendant(of: toolbar, matching: find.byIcon(Icons.file_download)),
      findsNothing,
    );
    expect(
      find.byKey(const Key('unified-detail-appbar-download')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('unified-detail-appbar-filter')),
      findsOneWidget,
    );
  });

  testWidgets(
    'UnifiedDetailPage chapter filter sheet only exposes source sorting',
    (tester) async {
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

      await tester.tap(find.byKey(const Key('unified-detail-appbar-filter')));
      await tester.pumpAndSettle();

      expect(find.text('按来源'), findsOneWidget);
      expect(find.text('按章节编号'), findsNothing);
      expect(find.text('按日期'), findsNothing);
      expect(find.text('按名称'), findsNothing);
      expect(
        find.byWidgetPredicate((widget) => widget is DropdownButtonFormField),
        findsNothing,
      );
      expect(find.byType(SegmentedButton<LibrarySortDirection>), findsNothing);

      final sourceSort = find.byKey(const Key('unified-detail-sort-source'));
      expect(
        find.descendant(
          of: sourceSort,
          matching: find.byIcon(Icons.arrow_upward),
        ),
        findsOneWidget,
      );
      await tester.tap(sourceSort);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: sourceSort,
          matching: find.byIcon(Icons.arrow_downward),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('unified-detail-apply-filter-sort')),
      );
      await tester.tap(
        find.byKey(const Key('unified-detail-apply-filter-sort')),
      );
      await tester.pumpAndSettle();

      expect(adapter.lastSortOption.direction, LibrarySortDirection.desc);

      final chapterTiles = tester
          .widgetList<Material>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Material &&
                  widget.key is ValueKey<String> &&
                  (widget.key! as ValueKey<String>).value.startsWith(
                    'unified-detail-chapter-',
                  ),
            ),
          )
          .toList();
      expect(
        (chapterTiles.first.key! as ValueKey<String>).value,
        'unified-detail-chapter-e2',
      );
    },
  );

  testWidgets('UnifiedDetailPage toggles chapter bookmark from long press', (
    tester,
  ) async {
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
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('unified-detail-chapter-bookmark-indicator-e1'),
      ),
      findsNothing,
    );
    expect(
      find.byKey(
        const ValueKey<String>('unified-detail-chapter-bookmark-button-e1'),
      ),
      findsNothing,
    );

    await tester.longPress(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('添加书签'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('unified-detail-chapter-bookmark-action-e1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(adapter.isBookmarked, isTrue);
    expect(adapter.lastBookmarkEpisodeId, 'e1');
    expect(adapter.loadChaptersCallCount, greaterThanOrEqualTo(2));
    expect(
      find.byKey(
        const ValueKey<String>('unified-detail-chapter-bookmark-indicator-e1'),
      ),
      findsOneWidget,
    );

    await tester.longPress(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('移除书签'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey<String>('unified-detail-chapter-bookmark-action-e1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(adapter.isBookmarked, isFalse);
    expect(
      find.byKey(
        const ValueKey<String>('unified-detail-chapter-bookmark-indicator-e1'),
      ),
      findsNothing,
    );
  });

  testWidgets('UnifiedDetailPage toggles unread chapter read by right swipe', (
    tester,
  ) async {
    final adapter = _FakeDetailAdapter(module: LibraryModuleKey.comic);

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
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();

    expect(adapter.markReadCallCount, 1);
    expect(adapter.isRead, isTrue);
    expect(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
      findsOneWidget,
    );
  });

  testWidgets('UnifiedDetailPage resets read chapter by right swipe', (
    tester,
  ) async {
    final adapter = _FakeDetailAdapter(
      module: LibraryModuleKey.comic,
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

    await tester.drag(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();

    expect(adapter.lastResetEpisodeId, 'e1');
    expect(adapter.isRead, isFalse);
  });

  testWidgets('UnifiedDetailPage caps chapter swipe at one third width', (
    tester,
  ) async {
    final adapter = _FakeDetailAdapter(module: LibraryModuleKey.comic);
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
    final chapter = find.byKey(
      const ValueKey<String>('unified-detail-chapter-e1'),
    );
    await tester.scrollUntilVisible(
      chapter,
      300,
      scrollable: find.byType(Scrollable).first,
    );

    final gesture = await tester.startGesture(tester.getCenter(chapter));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(300, 0));
    await tester.pump();

    final foreground = tester.widget<FractionalTranslation>(
      find.byKey(
        const ValueKey<String>(
          'unified-detail-chapter-read-swipe-foreground-e1',
        ),
      ),
    );
    expect(foreground.translation.dx, closeTo(1 / 3, 0.001));
    expect(adapter.markReadCallCount, 0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(adapter.markReadCallCount, 1);
  });

  testWidgets('UnifiedDetailPage keeps physical right swipe in RTL', (
    tester,
  ) async {
    final adapter = _FakeDetailAdapter(module: LibraryModuleKey.comic);
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: UnifiedDetailPage(
            adapter: adapter,
            workId: 'work-1',
            onOpenReader: (context, target) async {},
            onOpenThread: (context, target) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chapter = find.byKey(
      const ValueKey<String>('unified-detail-chapter-e1'),
    );
    await tester.scrollUntilVisible(
      chapter,
      300,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.drag(chapter, const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(adapter.markReadCallCount, 1);
    expect(adapter.isRead, isTrue);
  });

  testWidgets('UnifiedDetailPage ignores right-to-left chapter swipe', (
    tester,
  ) async {
    final adapter = _FakeDetailAdapter(module: LibraryModuleKey.comic);
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

    await tester.drag(
      find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(adapter.markReadCallCount, 0);
    expect(adapter.lastResetEpisodeId, isNull);
  });

  testWidgets('UnifiedDetailPage reports chapter read mutation failure', (
    tester,
  ) async {
    final adapter = _FakeDetailAdapter(
      module: LibraryModuleKey.comic,
      failMarkRead: true,
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
    final chapter = find.byKey(
      const ValueKey<String>('unified-detail-chapter-e1'),
    );
    await tester.scrollUntilVisible(
      chapter,
      300,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.drag(chapter, const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(find.text('阅读状态更新失败'), findsOneWidget);
    expect(adapter.isRead, isFalse);
    expect(chapter, findsOneWidget);
  });

  testWidgets('UnifiedDetailPage confirms resetting the whole comic', (
    tester,
  ) async {
    final adapter = _FakeDetailAdapter(
      module: LibraryModuleKey.comic,
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
    final chapter = find.byKey(
      const ValueKey<String>('unified-detail-chapter-e1'),
    );
    await tester.scrollUntilVisible(
      chapter,
      300,
      scrollable: find.byType(Scrollable).first,
    );

    await tester.longPress(chapter);
    await tester.pumpAndSettle();
    expect(find.text('重置本章阅读'), findsNothing);
    expect(find.text('重置本漫画阅读'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('unified-detail-work-reset-reading-action')),
    );
    await tester.pumpAndSettle();
    expect(find.text('重置本漫画阅读？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(adapter.resetWorkCallCount, 0);

    await tester.longPress(chapter);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('unified-detail-work-reset-reading-action')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('unified-detail-work-reset-reading-confirm')),
    );
    await tester.pumpAndSettle();

    expect(adapter.resetWorkCallCount, 1);
    expect(adapter.isRead, isFalse);
  });

  testWidgets('UnifiedDetailPage keeps download action without status badge', (
    tester,
  ) async {
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

    expect(
      find.byKey(
        const ValueKey<String>('unified-detail-chapter-downloaded-badge-e1'),
      ),
      findsNothing,
    );

    await tester.tap(find.byTooltip('下载该章节'));
    await tester.pumpAndSettle();

    expect(adapter.isDownloaded, isTrue);
    expect(adapter.lastDownloadedEpisodeId, 'e1');
    expect(
      find.byKey(
        const ValueKey<String>('unified-detail-chapter-downloaded-badge-e1'),
      ),
      findsNothing,
    );
    expect(find.text('已下载'), findsNothing);
    expect(find.byTooltip('已下载，点击删除下载'), findsOneWidget);

    await tester.tap(find.byTooltip('已下载，点击删除下载'));
    await tester.pumpAndSettle();

    expect(adapter.isDownloaded, isFalse);
    expect(adapter.lastDeletedDownloadEpisodeId, 'e1');
    expect(
      find.byKey(
        const ValueKey<String>('unified-detail-chapter-downloaded-badge-e1'),
      ),
      findsNothing,
    );
  });

  testWidgets(
    'UnifiedDetailPage keeps spinner until the queued chapter finishes',
    (tester) async {
      final adapter = _QueuedDownloadDetailAdapter();
      final refreshBus = LibraryShelfRefreshBus();
      addTearDown(() {
        adapter.dispose();
        refreshBus.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedDetailPage(
            adapter: adapter,
            workId: 'work-1',
            shelfRefreshBus: refreshBus,
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byTooltip('正在下载'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('已加入下载队列'), findsNothing);

      adapter.complete('e1');
      refreshBus.notify(
        modules: const <LibraryModuleKey>{LibraryModuleKey.comic},
        reason: 'comic_download_completed',
        source: LibraryMutationSource.bulkDownload,
        workId: 'work-1',
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('正在下载'), findsNothing);
      expect(find.byTooltip('已下载，点击删除下载'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'UnifiedDetailPage omits chapter progress badge when progress is null',
    (tester) async {
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

      expect(
        find.byKey(
          const ValueKey<String>('unified-detail-chapter-progress-e1'),
        ),
        findsNothing,
      );
    },
  );

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

  testWidgets('UnifiedDetailPage shows refresh fallback snackbars', (
    tester,
  ) async {
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

  testWidgets(
    'UnifiedDetailPage reloads when current work refresh signal arrives',
    (tester) async {
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final adapter = _FakeDetailAdapter();
      var presentationCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: UnifiedDetailPage(
            adapter: adapter,
            workId: 'work-1',
            shelfRefreshBus: bus,
            onOpenReader: (context, target) async {},
            onOpenThread: (context, target) async {},
            onFirstContentPresented: (header, chapters) {
              presentationCount++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initialLoadCount = adapter.loadChaptersCallCount;
      expect(presentationCount, 1);

      bus.notify(
        modules: const <LibraryModuleKey>{LibraryModuleKey.novel},
        reason: 'comic_search_refresh_completed',
        source: LibraryMutationSource.comicSearchQueue,
        workId: 'other-work',
      );
      await tester.pumpAndSettle();

      expect(adapter.loadChaptersCallCount, initialLoadCount);

      bus.notify(
        modules: const <LibraryModuleKey>{LibraryModuleKey.novel},
        reason: 'comic_search_refresh_completed',
        source: LibraryMutationSource.comicSearchQueue,
        workId: 'work-1',
      );
      await tester.pumpAndSettle();

      expect(adapter.loadChaptersCallCount, initialLoadCount + 1);
      expect(presentationCount, 1);
    },
  );

  testWidgets('UnifiedDetailPage shows error panel and retries initial load', (
    tester,
  ) async {
    final adapter = _FakeDetailAdapter()..failLoadHeaderOnce = true;
    var presentationCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: adapter,
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
          onFirstContentPresented: (header, chapters) {
            presentationCount++;
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-detail-error-panel')), findsOneWidget);
    expect(find.byKey(const Key('unified-detail-error-retry')), findsOneWidget);
    expect(find.textContaining('加载失败'), findsOneWidget);
    expect(presentationCount, 0);

    await tester.ensureVisible(
      find.byKey(const Key('unified-detail-error-retry')),
    );
    await tester.tap(find.byKey(const Key('unified-detail-error-retry')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unified-detail-error-panel')), findsNothing);
    expect(find.text('测试作品'), findsWidgets);
    expect(presentationCount, 1);
  });

  testWidgets('UnifiedDetailPage isolates first content callback failures', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UnifiedDetailPage(
          adapter: _FakeDetailAdapter(),
          workId: 'work-1',
          onOpenReader: (context, target) async {},
          onOpenThread: (context, target) async {},
          onFirstContentPresented: (header, chapters) {
            throw StateError('history unavailable');
          },
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('测试作品'), findsWidgets);
    expect(find.byKey(const Key('unified-detail-error-panel')), findsNothing);
  });

  testWidgets('each UnifiedDetailPage route presents the same work once', (
    tester,
  ) async {
    var presentationCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-detail-route'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => UnifiedDetailPage(
                        adapter: _FakeDetailAdapter(),
                        workId: 'work-1',
                        onOpenReader: (context, target) async {},
                        onOpenThread: (context, target) async {},
                        onFirstContentPresented: (header, chapters) {
                          presentationCount++;
                        },
                      ),
                    ),
                  );
                },
                child: const Text('打开详情'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-detail-route')));
    await tester.pumpAndSettle();
    expect(presentationCount, 1);

    Navigator.of(tester.element(find.text('测试作品').first)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-detail-route')));
    await tester.pumpAndSettle();

    expect(presentationCount, 2);
  });

  testWidgets(
    'UnifiedDetailPage keeps existing content when chapter reload fails',
    (tester) async {
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
        find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
      await tester.pumpAndSettle();

      adapter.failLoadChaptersOnce = true;
      await tester.longPress(
        find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey<String>('unified-detail-chapter-bookmark-action-e1'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('unified-detail-error-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('unified-detail-error-retry')),
      );
      await tester.tap(find.byKey(const Key('unified-detail-error-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('unified-detail-error-panel')), findsNothing);
    },
  );

  testWidgets(
    'UnifiedDetailPage reports chapter download failures without stale spinner',
    (tester) async {
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
      expect(
        find.byKey(
          const ValueKey<String>('unified-detail-chapter-downloaded-badge-e1'),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'UnifiedDetailPage recovers from hide-all through the AppBar chapter manager',
    (tester) async {
      final adapter = _ManageableDetailAdapter();
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
      await tester.tap(find.byKey(const Key('unified-detail-manage-chapters')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('unified-detail-chapter-management-sheet')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('unified-detail-chapter-management-hide-all')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();

      // 全部隐藏后章节列表为空，长按入口随之消失，只有 AppBar 菜单能救回来。
      expect(
        find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
        findsNothing,
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('unified-detail-manage-chapters')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('unified-detail-chapter-management-show-all')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.byKey(const ValueKey<String>('unified-detail-chapter-e1')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'UnifiedDetailPage reports delete download failures and keeps download state',
    (tester) async {
      final adapter = _FakeDetailAdapter(isDownloaded: true)
        ..failDeleteDownload = true;
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
      expect(
        find.byKey(
          const ValueKey<String>('unified-detail-chapter-downloaded-badge-e1'),
        ),
        findsNothing,
      );
      expect(find.text('已下载'), findsNothing);
      expect(find.byTooltip('已下载，点击删除下载'), findsOneWidget);
    },
  );
}

class _FakeDetailAdapter
    implements
        DetailModuleAdapter,
        DetailChapterReadStateAdapter,
        DetailWorkReadingResetAdapter,
        DetailChapterDownloadAdapter {
  _FakeDetailAdapter({
    this.module = LibraryModuleKey.novel,
    this.coverLocalPath,
    this.progressInfo,
    this.isBookmarked = false,
    this.isDownloaded = false,
    this.isRead = false,
    this.failMarkRead = false,
    this.includeSecondChapter = false,
    this.secondIsBookmarked = false,
    this.secondIsDownloaded = false,
    this.secondIsRead = false,
  });

  int markReadCallCount = 0;
  int loadHeaderCallCount = 0;
  int loadChaptersCallCount = 0;
  int refreshWorkCallCount = 0;
  int resetWorkCallCount = 0;
  String? lastBookmarkEpisodeId;
  String? lastResetEpisodeId;
  String? lastDownloadedEpisodeId;
  String? lastDeletedDownloadEpisodeId;
  LibraryFilterSet lastFilters = LibraryFilterSet.defaults;
  LibraryChapterSortOption lastSortOption = LibraryChapterSortOption.defaults;
  DetailRefreshResult refreshResult = DetailRefreshResult.immediate;
  bool failLoadHeaderOnce = false;
  bool failLoadChaptersOnce = false;
  bool failMarkDownload = false;
  bool failDeleteDownload = false;
  final bool failMarkRead;
  final String? coverLocalPath;
  final LibraryModuleKey module;
  final LibraryChapterProgressInfo? progressInfo;
  bool isBookmarked;
  bool isDownloaded;
  bool isRead;
  final bool includeSecondChapter;
  final bool secondIsBookmarked;
  final bool secondIsDownloaded;
  final bool secondIsRead;

  @override
  Future<void> resetChapterReadingState({
    required String workId,
    required String episodeId,
  }) async {
    lastResetEpisodeId = episodeId;
    isRead = false;
  }

  @override
  Future<void> resetWorkReadingState({required String workId}) async {
    resetWorkCallCount++;
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
  Future<ThreadRouteTarget?> getThreadRouteTarget({
    required String workId,
  }) async {
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
      if (includeSecondChapter ||
          secondIsBookmarked ||
          secondIsDownloaded ||
          secondIsRead)
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
      final compared = (a.sourceTid ?? '').compareTo(b.sourceTid ?? '');
      return sortOption.direction == LibrarySortDirection.asc
          ? compared
          : -compared;
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
    loadHeaderCallCount++;
    if (failLoadHeaderOnce) {
      failLoadHeaderOnce = false;
      throw StateError('header failed');
    }
    return LibraryDetailHeader(
      workId: 'work-1',
      title: '测试作品',
      author: '作者A',
      sourceAuthorId: '10001',
      coverLocalPath: coverLocalPath,
      inShelf: true,
      intro: '这是一段简介',
      sourceTypeId: '398',
      sourceTagName: '韩国漫画',
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
    if (failMarkRead) {
      throw StateError('mark read failed');
    }
    this.isRead = isRead;
  }

  @override
  LibraryModuleKey get moduleKey => module;

  @override
  Future<DetailRefreshResult> refreshWork({required String workId}) async {
    refreshWorkCallCount++;
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
}

final class _QueuedDownloadDetailAdapter extends _FakeDetailAdapter
    implements DetailChapterDownloadActivityAdapter {
  _QueuedDownloadDetailAdapter() : super(module: LibraryModuleKey.comic);

  final ValueNotifier<Set<String>> _activeEpisodeIds =
      ValueNotifier<Set<String>>(<String>{});

  @override
  Listenable get chapterDownloadActivityListenable => _activeEpisodeIds;

  @override
  bool isChapterDownloadActive({
    required String workId,
    required String episodeId,
  }) {
    return _activeEpisodeIds.value.contains(episodeId);
  }

  @override
  Future<void> markChapterDownloaded({
    required String workId,
    required String episodeId,
    required bool isDownloaded,
  }) async {
    lastDownloadedEpisodeId = episodeId;
    _activeEpisodeIds.value = <String>{episodeId};
  }

  void complete(String episodeId) {
    isDownloaded = true;
    _activeEpisodeIds.value = <String>{};
  }

  void dispose() {
    _activeEpisodeIds.dispose();
  }
}

class _EditableDetailAdapter extends _FakeDetailAdapter
    implements DetailMetadataEditor {
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
  DetailMetadataEditorConfig get metadataEditorConfig =>
      const DetailMetadataEditorConfig();

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

class _CatalogEditableDetailAdapter extends _FakeDetailAdapter
    implements DetailCatalogEditor {
  String? lastCatalogUrl;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.comic;

  @override
  Future<DetailCatalogConfiguration> loadCatalogConfiguration({
    required String workId,
  }) async {
    return const DetailCatalogConfiguration(
      sourceCatalogUrl: 'https://bbs.yamibo.com/misc.php?mod=tag&id=1',
      customCatalogUrl: null,
    );
  }

  @override
  Future<void> updateCatalogOverride({
    required String workId,
    String? catalogUrl,
  }) async {
    lastCatalogUrl = catalogUrl;
  }
}

/// 隐藏状态由 adapter 自己维护，[loadChapters] 只返回可见章节——与真实
/// 存储层「隐藏在读取边界过滤」的语义一致。
class _ManageableDetailAdapter extends _FakeDetailAdapter
    implements DetailChapterManagementAdapter {
  _ManageableDetailAdapter() : super(module: LibraryModuleKey.comic);

  final Map<String, bool> _hidden = <String, bool>{'e1': false};

  @override
  Future<List<LibraryChapterItem>> loadChapters({
    required String workId,
    required LibraryFilterSet filters,
    required LibraryChapterSortOption sortOption,
  }) async {
    final chapters = await super.loadChapters(
      workId: workId,
      filters: filters,
      sortOption: sortOption,
    );
    return chapters
        .where((chapter) => _hidden[chapter.episodeId] != true)
        .toList(growable: false);
  }

  @override
  Future<List<DetailManagedChapter>> loadManagedChapters({
    required String workId,
  }) async {
    return _hidden.entries
        .map(
          (entry) => DetailManagedChapter(
            episodeId: entry.key,
            title: '第1章',
            sourceTid: '100',
            isManual: false,
            isHidden: entry.value,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<bool> addManualChapter({
    required String workId,
    required String input,
  }) async {
    _hidden[input] = false;
    return true;
  }

  @override
  Future<DetailChapterRemovalResult> removeManualChapter({
    required String workId,
    required String episodeId,
  }) async => const DetailChapterRemovalResult(removed: false);

  @override
  Future<void> setChapterHidden({
    required String workId,
    required String episodeId,
    required bool isHidden,
  }) async {
    _hidden[episodeId] = isHidden;
  }

  @override
  Future<void> setAllChaptersHidden({
    required String workId,
    required bool isHidden,
  }) async {
    for (final key in _hidden.keys.toList(growable: false)) {
      _hidden[key] = isHidden;
    }
  }
}

class _CoverEditableDetailAdapter extends _FakeDetailAdapter
    implements DetailCoverEditor {
  _CoverEditableDetailAdapter({
    this.hasCustomCover = false,
    this.hasSourceCover = false,
  });

  bool hasCustomCover;
  final bool hasSourceCover;
  bool coverHidden = false;
  bool coverRemoved = false;
  String? lastSourcePath;
  double? lastFocusX;
  double? lastFocusY;

  @override
  LibraryModuleKey get moduleKey => LibraryModuleKey.comic;

  @override
  Future<LibraryDetailHeader> loadHeader({required String workId}) async {
    return LibraryDetailHeader(
      workId: 'work-1',
      title: '测试作品',
      sourceTitle: '来源标题',
      coverLocalPath: hasSourceCover && !coverHidden
          ? 'missing-y300-source-cover.png'
          : null,
      customCoverLocalPath: hasCustomCover && !coverHidden
          ? 'missing-y300-custom-cover.png'
          : null,
      inShelf: true,
      intro: '简介',
    );
  }

  @override
  bool canRemoveCover(LibraryDetailHeader header) {
    return header.customCoverLocalPath != null || header.coverLocalPath != null;
  }

  @override
  Future<void> setCustomCoverFromLocalFile({
    required String workId,
    required String sourceLocalPath,
    double? focusX,
    double? focusY,
  }) async {
    lastSourcePath = sourceLocalPath;
    lastFocusX = focusX;
    lastFocusY = focusY;
  }

  @override
  Future<void> updateCustomCoverFocus({
    required String workId,
    required double? focusX,
    required double? focusY,
  }) async {
    lastFocusX = focusX;
    lastFocusY = focusY;
  }

  @override
  Future<void> removeCustomCover({required String workId}) async {
    coverRemoved = true;
    hasCustomCover = false;
    coverHidden = true;
  }
}

LinearGradient _headerGradient(WidgetTester tester) {
  final gradientBox = tester.widget<DecoratedBox>(
    find.byKey(const Key('unified-detail-header-gradient')),
  );
  final decoration = gradientBox.decoration as BoxDecoration;
  return decoration.gradient! as LinearGradient;
}
