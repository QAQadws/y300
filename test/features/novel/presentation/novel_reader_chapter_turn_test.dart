import 'dart:async';

import 'package:flutter/material.dart';
import '../../../test_support/localized_test_app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/models/novel_reader_marks.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_chapter_turn.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_page_fragment.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_key.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_plan.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_progress.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_prepared_chapter.dart';
import 'package:y300/features/novel/presentation/services/novel_forum_html_render_theme_factory.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_display_resolvers.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_coordinator.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_html_paged_surface.dart';
import 'package:y300/features/thread/presentation/html_rendering/forum_html_reader_preferences_provider.dart';
import 'package:y300/features/thread/presentation/html_rendering/theme/forum_html_theme_context.dart';

void main() {
  group('NovelReaderChapterTurnPolicy', () {
    test('commit distance takes the larger of the floor and the fraction', () {
      const policy = NovelReaderChapterTurnPolicy(
        minCommitDistance: 44,
        viewportCommitFraction: 0.1,
      );

      expect(policy.commitDistanceFor(360), 44);
      expect(policy.commitDistanceFor(800), 80);
    });

    test('degenerate viewports fall back to the floor', () {
      const policy = NovelReaderChapterTurnPolicy();

      expect(policy.commitDistanceFor(0), policy.minCommitDistance);
      expect(policy.commitDistanceFor(double.nan), policy.minCommitDistance);
    });

    test('the hint reveals strictly before the commit threshold', () {
      const policy = NovelReaderChapterTurnPolicy();
      const viewport = 800.0;

      expect(
        policy.hintRevealDistanceFor(viewport),
        lessThan(policy.commitDistanceFor(viewport)),
      );
      expect(
        policy.shouldRevealHint(
          overscrollDistance: policy.hintRevealDistanceFor(viewport),
          viewportDimension: viewport,
        ),
        isTrue,
      );
      expect(
        policy.shouldCommit(
          overscrollDistance: policy.hintRevealDistanceFor(viewport),
          viewportDimension: viewport,
        ),
        isFalse,
      );
    });
  });

  group('paged surface chapter turns', () {
    testWidgets('tap controller animates between pages and rejects overlap', (
      tester,
    ) async {
      final navigationController = NovelReaderPagedNavigationController();
      addTearDown(navigationController.dispose);
      final positions = <NovelReaderPaginationPosition>[];
      await tester.pumpWidget(
        _buildSurface(
          coordinator: _FixedPlanPaginationCoordinator(pageCount: 3),
          navigationController: navigationController,
          onPositionChanged: positions.add,
        ),
      );
      await tester.pumpAndSettle();

      expect(navigationController.turnNext(), isTrue);
      expect(navigationController.turnNext(), isFalse);
      await tester.pumpAndSettle();
      expect(positions.last.pageIndex, 1);

      expect(navigationController.turnPrevious(), isTrue);
      await tester.pumpAndSettle();
      expect(positions.last.pageIndex, 0);
    });

    testWidgets('tap controller turns chapters at final plan boundaries', (
      tester,
    ) async {
      final navigationController = NovelReaderPagedNavigationController();
      addTearDown(navigationController.dispose);
      final edges = <NovelReaderChapterEdge>[];
      await tester.pumpWidget(
        _buildSurface(
          coordinator: _FixedPlanPaginationCoordinator(pageCount: 1),
          navigationController: navigationController,
          previousChapterTitle: '第零章',
          nextChapterTitle: '第二章',
          onTurnToAdjacentChapter: _accepting(edges),
        ),
      );
      await tester.pumpAndSettle();

      expect(navigationController.turnNext(), isTrue);
      expect(navigationController.turnPrevious(), isFalse);
      expect(edges, <NovelReaderChapterEdge>[NovelReaderChapterEdge.end]);
    });

    testWidgets('tap controller does not cross an incomplete plan boundary', (
      tester,
    ) async {
      final navigationController = NovelReaderPagedNavigationController();
      addTearDown(navigationController.dispose);
      final coordinator = _GrowingPlanPaginationCoordinator();
      final edges = <NovelReaderChapterEdge>[];
      await tester.pumpWidget(
        _buildSurface(
          coordinator: coordinator,
          navigationController: navigationController,
          nextChapterTitle: '第二章',
          onTurnToAdjacentChapter: _accepting(edges),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(navigationController.turnNext(), isFalse);
      expect(edges, isEmpty);

      coordinator.complete();
      await tester.pumpAndSettle();
      expect(navigationController.turnNext(), isTrue);
      await tester.pumpAndSettle();
      expect(edges, isEmpty);
    });

    testWidgets('detached tap controller cannot drive a stale surface', (
      tester,
    ) async {
      final navigationController = NovelReaderPagedNavigationController();
      addTearDown(navigationController.dispose);
      await tester.pumpWidget(
        _buildSurface(
          coordinator: _FixedPlanPaginationCoordinator(pageCount: 2),
          navigationController: navigationController,
        ),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(navigationController.turnNext(), isFalse);
      expect(navigationController.turnPrevious(), isFalse);
    });

    testWidgets('dragging past the last page turns to the next chapter', (
      tester,
    ) async {
      final edges = <NovelReaderChapterEdge>[];
      await tester.pumpWidget(
        _buildSurface(
          coordinator: _FixedPlanPaginationCoordinator(pageCount: 2),
          nextChapterTitle: '第二章',
          onTurnToAdjacentChapter: _accepting(edges),
        ),
      );
      await tester.pumpAndSettle();

      await _advanceToLastPage(tester);
      expect(edges, isEmpty);

      await tester.drag(_pageView, const Offset(-160, 0));
      await tester.pumpAndSettle();

      expect(edges, <NovelReaderChapterEdge>[NovelReaderChapterEdge.end]);
    });

    testWidgets(
      'dragging before the first page turns to the previous chapter',
      (tester) async {
        final edges = <NovelReaderChapterEdge>[];
        await tester.pumpWidget(
          _buildSurface(
            coordinator: _FixedPlanPaginationCoordinator(pageCount: 2),
            previousChapterTitle: '第零章',
            onTurnToAdjacentChapter: _accepting(edges),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(_pageView, const Offset(160, 0));
        await tester.pumpAndSettle();

        expect(edges, <NovelReaderChapterEdge>[NovelReaderChapterEdge.start]);
      },
    );

    testWidgets('a short pull past the edge does not switch chapters', (
      tester,
    ) async {
      final edges = <NovelReaderChapterEdge>[];
      await tester.pumpWidget(
        _buildSurface(
          coordinator: _FixedPlanPaginationCoordinator(pageCount: 2),
          previousChapterTitle: '第零章',
          onTurnToAdjacentChapter: _accepting(edges),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(_pageView, const Offset(24, 0));
      await tester.pumpAndSettle();

      expect(edges, isEmpty);
      expect(
        find.byKey(const Key('novel-reader-chapter-turn-hint')),
        findsNothing,
      );
    });

    testWidgets('no neighbouring chapter means no turn', (tester) async {
      final edges = <NovelReaderChapterEdge>[];
      await tester.pumpWidget(
        _buildSurface(
          coordinator: _FixedPlanPaginationCoordinator(pageCount: 2),
          onTurnToAdjacentChapter: _accepting(edges),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(_pageView, const Offset(160, 0));
      await tester.pumpAndSettle();
      await _advanceToLastPage(tester);
      await tester.drag(_pageView, const Offset(-160, 0));
      await tester.pumpAndSettle();

      expect(edges, isEmpty);
    });

    testWidgets(
      'a single-page chapter can still be turned in both directions',
      (tester) async {
        final edges = <NovelReaderChapterEdge>[];
        await tester.pumpWidget(
          _buildSurface(
            coordinator: _FixedPlanPaginationCoordinator(pageCount: 1),
            previousChapterTitle: '第零章',
            nextChapterTitle: '第二章',
            onTurnToAdjacentChapter: _accepting(edges),
          ),
        );
        await tester.pumpAndSettle();

        await tester.drag(_pageView, const Offset(-160, 0));
        await tester.pumpAndSettle();

        expect(edges, <NovelReaderChapterEdge>[NovelReaderChapterEdge.end]);
      },
    );

    testWidgets('the boundary hint appears mid-drag and names the target', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildSurface(
          coordinator: _FixedPlanPaginationCoordinator(pageCount: 2),
          previousChapterTitle: '第零章',
          onTurnToAdjacentChapter: (_) => true,
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(tester.getCenter(_pageView));
      await gesture.moveBy(const Offset(160, 0));
      await tester.pump();

      expect(
        find.byKey(const Key('novel-reader-chapter-turn-hint')),
        findsOneWidget,
      );
      expect(find.textContaining('第零章'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('novel-reader-chapter-turn-hint')),
        findsNothing,
      );
    });

    testWidgets('one drag past the edge only requests one chapter turn', (
      tester,
    ) async {
      final edges = <NovelReaderChapterEdge>[];
      await tester.pumpWidget(
        _buildSurface(
          coordinator: _FixedPlanPaginationCoordinator(pageCount: 2),
          previousChapterTitle: '第零章',
          onTurnToAdjacentChapter: _accepting(edges),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(_pageView, const Offset(160, 0));
      await tester.pumpAndSettle();
      await tester.drag(_pageView, const Offset(160, 0));
      await tester.pumpAndSettle();

      expect(edges, <NovelReaderChapterEdge>[NovelReaderChapterEdge.start]);
    });

    testWidgets('a declined turn leaves the gesture armed for a retry', (
      tester,
    ) async {
      // The page declines while a switch is already running. Nothing goes in
      // flight, so nothing will ever arrive to unlock the gesture — it has to
      // stay usable on its own.
      final edges = <NovelReaderChapterEdge>[];
      await tester.pumpWidget(
        _buildSurface(
          coordinator: _FixedPlanPaginationCoordinator(pageCount: 2),
          previousChapterTitle: '第零章',
          onTurnToAdjacentChapter: (edge) {
            edges.add(edge);
            return false;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(_pageView, const Offset(160, 0));
      await tester.pumpAndSettle();
      await tester.drag(_pageView, const Offset(160, 0));
      await tester.pumpAndSettle();

      expect(edges, hasLength(2));
    });
  });

  group('paged surface chapter entry', () {
    testWidgets('an applied entry request is reported so it can be retired', (
      tester,
    ) async {
      final applied = <int>[];
      await tester.pumpWidget(
        _buildSurface(
          coordinator: _FixedPlanPaginationCoordinator(pageCount: 3),
          chapterEntryRequest: const NovelReaderChapterEntryRequest(
            requestId: 7,
            episodeId: _episodeId,
            edge: NovelReaderChapterEdge.end,
          ),
          onChapterEntryApplied: (request) => applied.add(request.requestId),
        ),
      );
      await tester.pumpAndSettle();

      expect(applied, <int>[7]);
    });

    testWidgets('a pending entry request is not reported before it resolves', (
      tester,
    ) async {
      final coordinator = _GrowingPlanPaginationCoordinator();
      final applied = <int>[];
      await tester.pumpWidget(
        _buildSurface(
          coordinator: coordinator,
          chapterEntryRequest: const NovelReaderChapterEntryRequest(
            requestId: 7,
            episodeId: _episodeId,
            edge: NovelReaderChapterEdge.end,
          ),
          onChapterEntryApplied: (request) => applied.add(request.requestId),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(applied, isEmpty);

      coordinator.complete();
      await tester.pumpAndSettle();

      expect(applied, <int>[7]);
    });

    testWidgets('turning again works once the entry request is retired', (
      tester,
    ) async {
      // The bug this guards: the request used to stay armed forever after the
      // first turn, which kept the gesture permanently locked. Only re-entering
      // the reader cleared it.
      final edges = <NovelReaderChapterEdge>[];
      NovelReaderChapterEntryRequest? request =
          const NovelReaderChapterEntryRequest(
            requestId: 1,
            episodeId: _episodeId,
            edge: NovelReaderChapterEdge.start,
          );
      late StateSetter setOuterState;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setOuterState = setState;
            return _buildSurface(
              coordinator: _FixedPlanPaginationCoordinator(pageCount: 2),
              previousChapterTitle: '第零章',
              chapterEntryRequest: request,
              onChapterEntryApplied: (applied) {
                setState(() => request = null);
              },
              onTurnToAdjacentChapter: _accepting(edges),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // The request has been applied and retired, so the surface is free again.
      await tester.drag(_pageView, const Offset(160, 0));
      await tester.pumpAndSettle();

      expect(edges, <NovelReaderChapterEdge>[NovelReaderChapterEdge.start]);
      setOuterState(() {});
    });
  });

  group('paged surface chapter entry lifecycle', () {
    testWidgets('an end-edge entry opens the chapter on its last page', (
      tester,
    ) async {
      final positions = <NovelReaderPaginationPosition>[];
      await tester.pumpWidget(
        _buildSurface(
          coordinator: _FixedPlanPaginationCoordinator(pageCount: 3),
          chapterEntryRequest: const NovelReaderChapterEntryRequest(
            requestId: 1,
            episodeId: _episodeId,
            edge: NovelReaderChapterEdge.end,
          ),
          onPositionChanged: positions.add,
        ),
      );
      await tester.pumpAndSettle();

      expect(positions.single.pageIndex, 2);
      expect(positions.single.pageCount, 3);
    });

    testWidgets('a start-edge entry opens the chapter on its first page', (
      tester,
    ) async {
      final positions = <NovelReaderPaginationPosition>[];
      await tester.pumpWidget(
        _buildSurface(
          coordinator: _FixedPlanPaginationCoordinator(pageCount: 3),
          // A resumable position that the entry request must override.
          progressSnapshot: const NovelReaderProgressSnapshot(
            novelId: _novelId,
            episodeId: _episodeId,
            flowMode: NovelReaderFlowMode.pagedLtr,
            scrollOffset: 0,
            pageIndex: 2,
            progressPercent: 0.9,
          ),
          chapterEntryRequest: const NovelReaderChapterEntryRequest(
            requestId: 1,
            episodeId: _episodeId,
            edge: NovelReaderChapterEdge.start,
          ),
          onPositionChanged: positions.add,
        ),
      );
      await tester.pumpAndSettle();

      expect(positions.single.pageIndex, 0);
    });

    testWidgets('an end-edge entry waits for the final page count', (
      tester,
    ) async {
      final coordinator = _GrowingPlanPaginationCoordinator();
      final positions = <NovelReaderPaginationPosition>[];
      await tester.pumpWidget(
        _buildSurface(
          coordinator: coordinator,
          chapterEntryRequest: const NovelReaderChapterEntryRequest(
            requestId: 1,
            episodeId: _episodeId,
            edge: NovelReaderChapterEdge.end,
          ),
          onPositionChanged: positions.add,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('novel-reader-paged-restoring-position')),
        findsOneWidget,
      );
      expect(positions, isEmpty);

      coordinator.complete();
      await tester.pumpAndSettle();

      expect(positions.single.pageIndex, 1);
      expect(positions.single.pageCount, 2);
    });

    testWidgets('an entry request for another episode is ignored', (
      tester,
    ) async {
      final positions = <NovelReaderPaginationPosition>[];
      await tester.pumpWidget(
        _buildSurface(
          coordinator: _FixedPlanPaginationCoordinator(pageCount: 3),
          chapterEntryRequest: const NovelReaderChapterEntryRequest(
            requestId: 1,
            episodeId: 'some-other-episode',
            edge: NovelReaderChapterEdge.end,
          ),
          onPositionChanged: positions.add,
        ),
      );
      await tester.pumpAndSettle();

      expect(positions.single.pageIndex, 0);
    });
  });
}

final Finder _pageView = find.byKey(const Key('novel-reader-paged-page-view'));

/// Records the turns a surface asks for and reports them as accepted, which is
/// what the real page does whenever it actually starts a chapter switch.
NovelReaderChapterTurnHandler _accepting(List<NovelReaderChapterEdge> edges) {
  return (edge) {
    edges.add(edge);
    return true;
  };
}

Future<void> _advanceToLastPage(WidgetTester tester) async {
  await tester.fling(_pageView, const Offset(-400, 0), 1200);
  await tester.pumpAndSettle();
}

Widget _buildSurface({
  required NovelReaderPaginationCoordinator coordinator,
  String? previousChapterTitle,
  String? nextChapterTitle,
  NovelReaderChapterEntryRequest? chapterEntryRequest,
  NovelReaderPagedNavigationController? navigationController,
  NovelReaderProgressSnapshot? progressSnapshot,
  NovelReaderChapterTurnHandler? onTurnToAdjacentChapter,
  ValueChanged<NovelReaderChapterEntryRequest>? onChapterEntryApplied,
  ValueChanged<NovelReaderPaginationPosition>? onPositionChanged,
}) {
  final preferences = NovelReaderPreferences.defaults().copyWith(
    flowMode: NovelReaderFlowMode.pagedLtr,
  );
  final theme = ThemeData.light();
  final palette = const NovelReaderThemeResolver().resolve(
    preferences: preferences,
    theme: theme,
  );
  return LocalizedTestApp(
    theme: theme,
    home: Scaffold(
      body: NovelReaderHtmlPagedSurface(
        rawHtml: '<p>翻页衔接正文</p>',
        episode: _episode,
        preferences: preferences,
        typography: const NovelReaderTypographyResolver().resolve(
          preferences: preferences,
          theme: theme,
          palette: palette,
        ),
        theme: const NovelForumHtmlRenderThemeFactory().fromPalette(palette),
        imageReferer: 'https://bbs.yamibo.com/',
        progressSnapshot:
            progressSnapshot ??
            const NovelReaderProgressSnapshot(
              novelId: _novelId,
              episodeId: _episodeId,
              flowMode: NovelReaderFlowMode.pagedLtr,
              scrollOffset: 0,
              pageIndex: 0,
              progressPercent: 0,
            ),
        previousChapterTitle: previousChapterTitle,
        nextChapterTitle: nextChapterTitle,
        chapterEntryRequest: chapterEntryRequest,
        navigationController: navigationController,
        onChapterEntryApplied: onChapterEntryApplied,
        onTurnToAdjacentChapter: onTurnToAdjacentChapter,
        onPositionChanged: onPositionChanged,
        coordinatorBuilder:
            ({
              required BuildContext context,
              required ForumHtmlThemeContext theme,
              required ForumHtmlReaderPreferences preferences,
              required String sourceId,
              required String? threadId,
              required String? imageCacheOwnerId,
              required String? imageReferer,
            }) => coordinator,
      ),
    ),
  );
}

const _episodeId = 'turn-episode';
const _novelId = 'turn-novel';

const _episode = NovelEpisodeItem(
  episodeId: _episodeId,
  novelId: _novelId,
  sourceTid: '6300',
  episodeTitle: '第一章',
  orderIndex: 0,
);

List<NovelReaderPageFragment> _pages(int pageCount) {
  return List<NovelReaderPageFragment>.generate(pageCount, (index) {
    return NovelReaderPageFragment(
      index: index,
      html: '<p>第 ${index + 1} 页</p>',
      startAnchor: NovelReaderTextAnchor(
        episodeId: _episode.episodeId,
        nodeId: 'paragraph-$index',
      ),
      endAnchor: NovelReaderTextAnchor(
        episodeId: _episode.episodeId,
        nodeId: 'paragraph-$index',
        textOffset: 4,
      ),
      imageIndices: const <int>[],
      usedHeight: 80,
      availableHeight: 600,
    );
  });
}

final class _FixedPlanPaginationCoordinator
    implements NovelReaderPaginationCoordinator {
  _FixedPlanPaginationCoordinator({required this.pageCount});

  final int pageCount;

  @override
  Future<NovelReaderPaginationPlan> paginate({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) async => _plan(chapter: chapter, key: key, pageCount: pageCount);

  @override
  Stream<NovelReaderPaginationProgress> paginateIncrementally({
    required NovelReaderPreparedChapter chapter,
    required NovelReaderPaginationKey key,
  }) {
    return Stream<NovelReaderPaginationProgress>.value(
      NovelReaderPaginationProgress(
        plan: _plan(chapter: chapter, key: key, pageCount: pageCount),
        isComplete: true,
        processedAtomCount: pageCount,
        totalAtomCount: pageCount,
      ),
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

final class _GrowingPlanPaginationCoordinator
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
        controller.add(
          NovelReaderPaginationProgress(
            plan: _plan(chapter: chapter, key: key, pageCount: 1),
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

  void complete() {
    _controller?.add(
      NovelReaderPaginationProgress(
        plan: _plan(chapter: _chapter!, key: _key!, pageCount: 2),
        isComplete: true,
        processedAtomCount: 2,
        totalAtomCount: 2,
      ),
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

NovelReaderPaginationPlan _plan({
  required NovelReaderPreparedChapter chapter,
  required NovelReaderPaginationKey key,
  required int pageCount,
}) {
  return NovelReaderPaginationPlan(
    key: key,
    episodeId: chapter.episodeId,
    pages: _pages(pageCount),
    atomCount: pageCount,
  );
}
