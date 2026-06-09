import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(find.byIcon(Icons.file_download), findsOneWidget);
    expect(find.byIcon(Icons.filter_list), findsOneWidget);
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
}

class _FakeDetailAdapter implements DetailModuleAdapter {
  _FakeDetailAdapter({
    this.coverLocalPath,
    this.progressInfo,
    this.isBookmarked = false,
    this.isDownloaded = false,
    this.isRead = false,
  });

  int markReadCallCount = 0;
  int loadChaptersCallCount = 0;
  String? lastBookmarkEpisodeId;
  String? lastDownloadedEpisodeId;
  String? lastDeletedDownloadEpisodeId;
  DetailRefreshResult refreshResult = DetailRefreshResult.immediate;
  final String? coverLocalPath;
  final LibraryChapterProgressInfo? progressInfo;
  bool isBookmarked;
  bool isDownloaded;
  bool isRead;

  @override
  Future<void> clearAllReadState({required String workId}) async {
    isRead = false;
  }

  @override
  Future<void> deleteChapterDownload({
    required String workId,
    required String episodeId,
  }) async {
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
    loadChaptersCallCount++;
    return [
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
    ];
  }

  @override
  Future<LibraryDetailHeader> loadHeader({required String workId}) async {
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

