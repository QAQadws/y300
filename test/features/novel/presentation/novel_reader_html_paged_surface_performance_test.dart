import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_progress.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_forum_html_render_theme_factory.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_coordinator.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_paged_surface.dart';
import 'package:y300/features/library_shared/presentation/reader/reader_models.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  testWidgets('paged surface uses safe insets in its pagination geometry', (
    tester,
  ) async {
    final preferences = NovelReaderPreferences.defaults().copyWith(
      flowMode: NovelReaderFlowMode.pagedLtr,
    );
    final theme = ThemeData.light();
    final palette = const NovelReaderThemeResolver().resolve(
      preferences: preferences,
      theme: theme,
      platformBrightness: Brightness.light,
    );
    final htmlTheme = const NovelForumHtmlRenderThemeFactory().fromPalette(
      palette,
    );
    final coordinator = _CompleteRecordingPaginationCoordinator();

    Widget buildSurface(ReaderChromeInsets insets) {
      return MaterialApp(
        theme: theme,
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(top: 24, bottom: 30),
            ),
            child: NovelReaderHtmlPagedSurface(
              rawHtml: '<p>安全区分页几何</p>',
              episode: _episode,
              preferences: preferences,
              typography: const NovelReaderTypographyResolver().resolve(
                preferences: preferences,
                theme: theme,
                palette: palette,
              ),
              theme: htmlTheme,
              imageReferer: 'https://bbs.yamibo.com/',
              progressSnapshot: const NovelReaderProgressSnapshot(
                novelId: 'performance-novel',
                episodeId: 'performance-episode',
                flowMode: NovelReaderFlowMode.pagedLtr,
                scrollOffset: 0,
                pageIndex: 0,
                progressPercent: 0,
              ),
              chromeInsets: insets,
              coordinatorBuilder:
                  ({
                    required BuildContext context,
                    required ForumHtmlThemeContext theme,
                    required ForumHtmlReaderPreferences preferences,
                    required String sourceId,
                    required String? threadId,
                    required String? imageCacheOwnerId,
                    required ImageRequestHeaderBuilder? imageHeaderBuilder,
                  }) => coordinator,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(
      buildSurface(
        const ReaderChromeInsets(safeAreaTop: 24, safeAreaBottom: 30),
      ),
    );
    await tester.pumpAndSettle();
    final safeKey = coordinator.lastKey;

    await tester.pumpWidget(buildSurface(const ReaderChromeInsets.zero()));
    await tester.pumpAndSettle();
    final normalKey = coordinator.lastKey;

    expect(safeKey, isNotNull);
    expect(normalKey, isNotNull);
    expect(safeKey!.topChromeInsetPx, 24);
    expect(safeKey.bottomChromeInsetPx, 30);
    expect(normalKey!.topChromeInsetPx, 0);
    expect(normalKey.bottomChromeInsetPx, 0);
    expect(safeKey.viewportHeightPx, lessThan(normalKey.viewportHeightPx));
  });

  testWidgets('performance policy falls back through the surface callback', (
    tester,
  ) async {
    final preferences = NovelReaderPreferences.defaults().copyWith(
      flowMode: NovelReaderFlowMode.pagedLtr,
    );
    final theme = ThemeData.light();
    final palette = const NovelReaderThemeResolver().resolve(
      preferences: preferences,
      theme: theme,
      platformBrightness: Brightness.light,
    );
    final typography = const NovelReaderTypographyResolver().resolve(
      preferences: preferences,
      theme: theme,
      palette: palette,
    );
    final htmlTheme = const NovelForumHtmlRenderThemeFactory().fromPalette(
      palette,
    );
    var fallbackCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: NovelReaderHtmlPagedSurface(
            rawHtml: '<p>${List<String>.filled(80, '自动性能降级验证正文。').join()}</p>',
            episode: _episode,
            preferences: preferences,
            typography: typography,
            theme: htmlTheme,
            imageReferer: 'https://bbs.yamibo.com/',
            progressSnapshot: const NovelReaderProgressSnapshot(
              novelId: 'performance-novel',
              episodeId: 'performance-episode',
              flowMode: NovelReaderFlowMode.pagedLtr,
              scrollOffset: 0,
              pageIndex: 0,
              progressPercent: 0,
            ),
            performancePolicy: const NovelReaderPaginationPerformancePolicy(
              enforceBudgets: true,
              plainTextBudget: NovelReaderPaginationPerformanceBudget(
                firstPage: Duration.zero,
                fullPlan: Duration.zero,
              ),
              mixedContentBudget: NovelReaderPaginationPerformanceBudget(
                firstPage: Duration.zero,
                fullPlan: Duration.zero,
              ),
            ),
            onFallbackToVertical: () {
              fallbackCount += 1;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(fallbackCount, 1);
  });

  testWidgets('first-page timeout falls back when a plan emits nothing', (
    tester,
  ) async {
    final preferences = NovelReaderPreferences.defaults().copyWith(
      flowMode: NovelReaderFlowMode.pagedLtr,
    );
    final theme = ThemeData.light();
    final palette = const NovelReaderThemeResolver().resolve(
      preferences: preferences,
      theme: theme,
      platformBrightness: Brightness.light,
    );
    final typography = const NovelReaderTypographyResolver().resolve(
      preferences: preferences,
      theme: theme,
      palette: palette,
    );
    final htmlTheme = const NovelForumHtmlRenderThemeFactory().fromPalette(
      palette,
    );
    final coordinator = _StalledPaginationCoordinator();
    var fallbackCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: NovelReaderHtmlPagedSurface(
            rawHtml: '<p>不会产生分页事件的正文</p>',
            episode: _episode,
            preferences: preferences,
            typography: typography,
            theme: htmlTheme,
            imageReferer: 'https://bbs.yamibo.com/',
            progressSnapshot: const NovelReaderProgressSnapshot(
              novelId: 'performance-novel',
              episodeId: 'performance-episode',
              flowMode: NovelReaderFlowMode.pagedLtr,
              scrollOffset: 0,
              pageIndex: 0,
              progressPercent: 0,
            ),
            coordinatorBuilder:
                ({
                  required BuildContext context,
                  required ForumHtmlThemeContext theme,
                  required ForumHtmlReaderPreferences preferences,
                  required String sourceId,
                  required String? threadId,
                  required String? imageCacheOwnerId,
                  required ImageRequestHeaderBuilder? imageHeaderBuilder,
                }) => coordinator,
            performancePolicy: const NovelReaderPaginationPerformancePolicy(
              enforceBudgets: true,
              plainTextBudget: NovelReaderPaginationPerformanceBudget(
                firstPage: Duration(milliseconds: 5),
                fullPlan: Duration(milliseconds: 20),
              ),
              mixedContentBudget: NovelReaderPaginationPerformanceBudget(
                firstPage: Duration(milliseconds: 5),
                fullPlan: Duration(milliseconds: 20),
              ),
            ),
            onFallbackToVertical: () {
              fallbackCount += 1;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump();

    expect(fallbackCount, 1);
    expect(coordinator.cancelPendingCount, 0);
  });

  testWidgets('full-plan timeout falls back after a partial page', (
    tester,
  ) async {
    final preferences = NovelReaderPreferences.defaults().copyWith(
      flowMode: NovelReaderFlowMode.pagedLtr,
    );
    final theme = ThemeData.light();
    final palette = const NovelReaderThemeResolver().resolve(
      preferences: preferences,
      theme: theme,
      platformBrightness: Brightness.light,
    );
    final typography = const NovelReaderTypographyResolver().resolve(
      preferences: preferences,
      theme: theme,
      palette: palette,
    );
    final htmlTheme = const NovelForumHtmlRenderThemeFactory().fromPalette(
      palette,
    );
    final coordinator = _PartialThenStalledPaginationCoordinator();
    var fallbackCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: NovelReaderHtmlPagedSurface(
            rawHtml: '<p>只发布首个稳定页</p>',
            episode: _episode,
            preferences: preferences,
            typography: typography,
            theme: htmlTheme,
            imageReferer: 'https://bbs.yamibo.com/',
            progressSnapshot: const NovelReaderProgressSnapshot(
              novelId: 'performance-novel',
              episodeId: 'performance-episode',
              flowMode: NovelReaderFlowMode.pagedLtr,
              scrollOffset: 0,
              pageIndex: 0,
              progressPercent: 0,
            ),
            coordinatorBuilder:
                ({
                  required BuildContext context,
                  required ForumHtmlThemeContext theme,
                  required ForumHtmlReaderPreferences preferences,
                  required String sourceId,
                  required String? threadId,
                  required String? imageCacheOwnerId,
                  required ImageRequestHeaderBuilder? imageHeaderBuilder,
                }) => coordinator,
            performancePolicy: const NovelReaderPaginationPerformancePolicy(
              enforceBudgets: true,
              plainTextBudget: NovelReaderPaginationPerformanceBudget(
                firstPage: Duration(seconds: 1),
                fullPlan: Duration(milliseconds: 100),
              ),
              mixedContentBudget: NovelReaderPaginationPerformanceBudget(
                firstPage: Duration(seconds: 1),
                fullPlan: Duration(milliseconds: 100),
              ),
            ),
            onFallbackToVertical: () {
              fallbackCount += 1;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('novel-reader-paged-surface')), findsOneWidget);
    expect(fallbackCount, 0);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(fallbackCount, 1);
  });

  testWidgets(
    'incremental restore waits for the saved anchor before reporting progress',
    (tester) async {
      final preferences = NovelReaderPreferences.defaults().copyWith(
        flowMode: NovelReaderFlowMode.pagedLtr,
      );
      final theme = ThemeData.light();
      final palette = const NovelReaderThemeResolver().resolve(
        preferences: preferences,
        theme: theme,
        platformBrightness: Brightness.light,
      );
      final typography = const NovelReaderTypographyResolver().resolve(
        preferences: preferences,
        theme: theme,
        palette: palette,
      );
      final htmlTheme = const NovelForumHtmlRenderThemeFactory().fromPalette(
        palette,
      );
      final coordinator = _ControlledRestorePaginationCoordinator();
      final positions = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: NovelReaderHtmlPagedSurface(
              rawHtml: '<p>第一页</p><p>恢复目标页</p>',
              episode: _episode,
              preferences: preferences,
              typography: typography,
              theme: htmlTheme,
              imageReferer: 'https://bbs.yamibo.com/',
              progressSnapshot: const NovelReaderProgressSnapshot(
                novelId: 'performance-novel',
                episodeId: 'performance-episode',
                flowMode: NovelReaderFlowMode.pagedLtr,
                scrollOffset: 0,
                pageIndex: 1,
                anchorNodeId: 'paragraph-1',
                progressPercent: 0.5,
              ),
              coordinatorBuilder:
                  ({
                    required BuildContext context,
                    required ForumHtmlThemeContext theme,
                    required ForumHtmlReaderPreferences preferences,
                    required String sourceId,
                    required String? threadId,
                    required String? imageCacheOwnerId,
                    required ImageRequestHeaderBuilder? imageHeaderBuilder,
                  }) => coordinator,
              onPositionChanged: (position) {
                positions.add(position.pageIndex);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('novel-reader-paged-restoring-position')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('novel-reader-paged-page-view')),
        findsNothing,
      );
      expect(positions, isEmpty);

      coordinator.emitTargetPage();
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('novel-reader-paged-restoring-position')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('novel-reader-paged-page-view')),
        findsOneWidget,
      );
      expect(positions, <int>[1]);
    },
  );
}

const _episode = NovelEpisodeItem(
  episodeId: 'performance-episode',
  novelId: 'performance-novel',
  sourceTid: '6300',
  episodeTitle: '性能降级',
  orderIndex: 0,
);

final class _StalledPaginationCoordinator
    implements NovelReaderPaginationCoordinator {
  int cancelPendingCount = 0;

  @override
  Future<NovelReaderPaginationPlan> paginate({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) => Completer<NovelReaderPaginationPlan>().future;

  @override
  Stream<NovelReaderPaginationProgress> paginateIncrementally({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) => const Stream<NovelReaderPaginationProgress>.empty();

  @override
  bool isCached(NovelReaderPaginationKey key) => false;

  @override
  void cancelPending() {
    cancelPendingCount += 1;
  }

  @override
  void clear() {}

  @override
  void clearEpisode(String episodeId) {}
}

final class _PartialThenStalledPaginationCoordinator
    implements NovelReaderPaginationCoordinator {
  StreamController<NovelReaderPaginationProgress>? _controller;

  @override
  Future<NovelReaderPaginationPlan> paginate({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) => Completer<NovelReaderPaginationPlan>().future;

  @override
  Stream<NovelReaderPaginationProgress> paginateIncrementally({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    late final StreamController<NovelReaderPaginationProgress> controller;
    controller = StreamController<NovelReaderPaginationProgress>(
      onListen: () {
        const start = NovelReaderTextAnchor(
          episodeId: 'performance-episode',
          nodeId: 'paragraph-0',
        );
        const end = NovelReaderTextAnchor(
          episodeId: 'performance-episode',
          nodeId: 'paragraph-0',
          textOffset: 8,
        );
        controller.add(
          NovelReaderPaginationProgress(
            plan: NovelReaderPaginationPlan(
              key: key,
              episodeId: chapter.episodeId,
              pages: const <NovelReaderPageFragment>[
                NovelReaderPageFragment(
                  index: 0,
                  html: '<p>只发布首个稳定页</p>',
                  startAnchor: start,
                  endAnchor: end,
                  imageIndices: <int>[],
                  usedHeight: 100,
                  availableHeight: 600,
                ),
              ],
              atomCount: 2,
            ),
            isComplete: false,
            processedAtomCount: 1,
            totalAtomCount: 2,
          ),
        );
      },
    );
    _controller = controller;
    return controller.stream;
  }

  @override
  bool isCached(NovelReaderPaginationKey key) => false;

  @override
  void cancelPending() {
    unawaited(_controller?.close());
  }

  @override
  void clear() => cancelPending();

  @override
  void clearEpisode(String episodeId) => cancelPending();
}

final class _ControlledRestorePaginationCoordinator
    implements NovelReaderPaginationCoordinator {
  StreamController<NovelReaderPaginationProgress>? _controller;
  NovelReaderPreparedChapter? _chapter;
  NovelReaderPaginationKey? _key;

  @override
  Future<NovelReaderPaginationPlan> paginate({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) => Completer<NovelReaderPaginationPlan>().future;

  @override
  Stream<NovelReaderPaginationProgress> paginateIncrementally({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    _chapter = chapter;
    _key = key;
    late final StreamController<NovelReaderPaginationProgress> controller;
    controller = StreamController<NovelReaderPaginationProgress>(
      onListen: () {
        controller.add(_progress(pageCount: 1));
      },
    );
    _controller = controller;
    return controller.stream;
  }

  void emitTargetPage() {
    _controller?.add(_progress(pageCount: 2));
  }

  NovelReaderPaginationProgress _progress({required int pageCount}) {
    final chapter = _chapter!;
    final key = _key!;
    const firstStart = NovelReaderTextAnchor(
      episodeId: 'performance-episode',
      nodeId: 'paragraph-0',
    );
    const firstEnd = NovelReaderTextAnchor(
      episodeId: 'performance-episode',
      nodeId: 'paragraph-0',
      textOffset: 3,
    );
    const targetStart = NovelReaderTextAnchor(
      episodeId: 'performance-episode',
      nodeId: 'paragraph-1',
    );
    const targetEnd = NovelReaderTextAnchor(
      episodeId: 'performance-episode',
      nodeId: 'paragraph-1',
      textOffset: 5,
    );
    final pages = <NovelReaderPageFragment>[
      const NovelReaderPageFragment(
        index: 0,
        html: '<p>第一页</p>',
        startAnchor: firstStart,
        endAnchor: firstEnd,
        imageIndices: <int>[],
        usedHeight: 80,
        availableHeight: 600,
      ),
      if (pageCount > 1)
        const NovelReaderPageFragment(
          index: 1,
          html: '<p>恢复目标页</p>',
          startAnchor: targetStart,
          endAnchor: targetEnd,
          imageIndices: <int>[],
          usedHeight: 80,
          availableHeight: 600,
        ),
    ];
    return NovelReaderPaginationProgress(
      plan: NovelReaderPaginationPlan(
        key: key,
        episodeId: chapter.episodeId,
        pages: pages,
        atomCount: 3,
      ),
      isComplete: false,
      processedAtomCount: pageCount,
      totalAtomCount: 3,
    );
  }

  @override
  bool isCached(NovelReaderPaginationKey key) => false;

  @override
  void cancelPending() {
    unawaited(_controller?.close());
  }

  @override
  void clear() => cancelPending();

  @override
  void clearEpisode(String episodeId) => cancelPending();
}

final class _CompleteRecordingPaginationCoordinator
    implements NovelReaderPaginationCoordinator {
  NovelReaderPaginationKey? lastKey;

  @override
  Future<NovelReaderPaginationPlan> paginate({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) async {
    return _plan(chapter: chapter, key: key);
  }

  @override
  Stream<NovelReaderPaginationProgress> paginateIncrementally({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    lastKey = key;
    return Stream<NovelReaderPaginationProgress>.value(
      NovelReaderPaginationProgress(
        plan: _plan(chapter: chapter, key: key),
        isComplete: true,
        processedAtomCount: 1,
        totalAtomCount: 1,
      ),
    );
  }

  NovelReaderPaginationPlan _plan({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    final anchor = NovelReaderTextAnchor(
      episodeId: chapter.episodeId,
      nodeId: 'safe-area-paragraph',
    );
    return NovelReaderPaginationPlan(
      key: key,
      episodeId: chapter.episodeId,
      pages: <NovelReaderPageFragment>[
        NovelReaderPageFragment(
          index: 0,
          html: '<p>安全区分页几何</p>',
          startAnchor: anchor,
          endAnchor: anchor,
          imageIndices: const <int>[],
          usedHeight: 80,
          availableHeight: key.viewportHeightPx.toDouble(),
        ),
      ],
      atomCount: 1,
    );
  }

  @override
  bool isCached(NovelReaderPaginationKey key) => false;

  @override
  void cancelPending() {}

  @override
  void clear() {}

  @override
  void clearEpisode(String episodeId) {}
}
