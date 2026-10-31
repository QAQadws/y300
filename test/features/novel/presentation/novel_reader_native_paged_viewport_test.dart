import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_native_paged_controller.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_paged_navigation_controller.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_chapter_turn.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_viewport.dart';

import '../test_support/native_reader_test_fixture.dart';

String get _html => '<p>${List.filled(12, 'abcdefghijklmnopqrst').join()}</p>';

NovelReaderNativePagedController _controller(
  NativeReaderTestFixture fixture, {
  int offset = 0,
  bool futureAnchor = false,
  _FrameGate? frames,
  Future<void> Function()? idle,
}) {
  final anchor = fixture.anchors.segments.first.projection.baseAnchor;
  final controller = NovelReaderNativePagedController(
    session: fixture.session,
    anchors: fixture.anchors,
    position: NovelReaderProgressSnapshot(
      novelId: 'novel',
      episodeId: 'episode',
      flowMode: NovelReaderFlowMode.pagedLtr,
      scrollOffset: 0,
      pageIndex: 0,
      anchorNodeId: anchor.nodeId,
      anchorTextOffset: offset,
      anchorFormatVersion: futureAnchor ? 37 : anchor.formatVersion,
      anchorTextIdentity: anchor.textIdentity,
      progressPercent: offset == 0 ? 0 : .95,
      isProgressPercentValid: true,
    ),
    paginationKey: '${fixture.session.snapshot.width}:20',
    parent: fixture.parent,
    scheduler: frames == null
        ? const NovelReaderNativeWorkScheduler()
        : NovelReaderNativeWorkScheduler(nextFrame: frames.next),
    performance: const NovelReaderPaginationPerformancePolicy(
      enforceBudgets: false,
    ),
    idleScheduler: idle ?? () async {},
  );
  addTearDown(controller.close);
  return controller;
}

NativeReaderTestFixture _fixture({
  double width = 100,
  String layoutId = 'layout-a',
  ForumBodyParagraphCache? cache,
  String? html,
}) => NativeReaderTestFixture(
  html ?? _html,
  width: width,
  height: 20,
  layoutId: layoutId,
  cacheOwner: cache,
  complete: false,
);

Widget _reader(
  NovelReaderNativePagedController controller,
  Object owner,
  Object authority,
  List<NovelReaderPaginationPosition> reports, {
  double width = 100,
  double height = 20,
  bool reverse = false,
  NovelReaderPagedNavigationController? navigation,
  bool Function(NovelReaderChapterEdge)? onChapter,
  bool chapterInFlight = false,
  bool active = true,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      height: height,
      child: NovelReaderNativePagedViewport(
        controller: controller,
        ownerIdentity: owner,
        readingAuthorityIdentity: authority,
        reverse: reverse,
        active: active,
        navigationController: navigation,
        onTurnToAdjacentChapter: onChapter,
        chapterTurnIsInFlight: chapterInFlight,
        placeholder: const SizedBox(key: Key('native-waiting')),
        onPositionChanged: reports.add,
      ),
    ),
  ),
);

final class _FrameGate {
  _FrameGate({bool held = true}) : _pending = held ? Completer<void>() : null;
  Completer<void>? _pending;
  Future<void> next() async {
    final pending = _pending;
    if (pending != null) {
      await pending.future;
    } else {
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  void hold() => _pending ??= Completer<void>();

  void release() {
    final pending = _pending;
    _pending = null;
    pending?.complete();
  }
}

double _physicalPage(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!.page!;

Future<void> _startTapMotion(WidgetTester tester, int from) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 1));
    if (_physicalPage(tester) != from) break;
  }
  await tester.pump(const Duration(milliseconds: 60));
  expect(_physicalPage(tester), greaterThan(from + .5));
  expect(_physicalPage(tester), lessThan(from + 1));
}

void main() {
  for (final reverse in [false, true]) {
    testWidgets(
      'a ready neighbor begins motion without an extra post-frame delay (reverse=$reverse)',
      (tester) async {
        final fixture = _fixture();
        final controller = _controller(fixture);
        final reports = <NovelReaderPaginationPosition>[];
        final navigation = NovelReaderPagedNavigationController();
        addTearDown(navigation.dispose);
        await tester.pumpWidget(
          _reader(
            controller,
            Object(),
            Object(),
            reports,
            reverse: reverse,
            navigation: navigation,
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.viewForPage(1)!.isReady, isTrue);
        expect(navigation.turnNext(), isTrue);
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        expect(_physicalPage(tester), greaterThan(0));
        expect(_physicalPage(tester), lessThan(1));
        expect(controller.visiblePageIndex, 0);
        expect(reports.map((report) => report.pageIndex), [0]);
        for (
          var frame = 0;
          frame < 30 && reports.last.pageIndex != 1;
          frame++
        ) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull);
        }
        expect(reports.map((report) => report.pageIndex), [0, 1]);
        // Return before the former origin's Element has a cleanup frame. It
        // must be reused without trying to transfer its handles a second time.
        expect(controller.viewForPage(0), isNotNull);
        expect(controller.viewForPage(0)!.isReady, isFalse);
        expect(navigation.turnPrevious(), isTrue);
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 16));
        expect(_physicalPage(tester), lessThan(1));
        expect(_physicalPage(tester), greaterThan(0));
        expect(controller.visiblePageIndex, 1);
        expect(reports.map((report) => report.pageIndex), [0, 1]);
        await tester.pumpAndSettle();
        expect(reports.map((report) => report.pageIndex), [0, 1, 0]);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.close();
        expect(fixture.cache.activeLeases, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final reverse in [false, true]) {
    testWidgets(
      'dense mixed turns retire far mounted pages before admitting the next target (reverse=$reverse)',
      (tester) async {
        final paragraph =
            '<p>${List.filled(100, '<ruby>A<rt>a</rt></ruby>').join()}</p>';
        final fixture = NativeReaderTestFixture(
          List.filled(5, paragraph).join(),
          width: 100,
          height: 150,
          maxIssuedLeases: 512,
          complete: false,
        );
        final controller = _controller(fixture);
        final reports = <NovelReaderPaginationPosition>[];
        final navigation = NovelReaderPagedNavigationController();
        addTearDown(navigation.dispose);
        await tester.pumpWidget(
          _reader(
            controller,
            Object(),
            Object(),
            reports,
            height: 150,
            reverse: reverse,
            navigation: navigation,
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.error, isNull);
        expect(reports.last.pageIndex, 0);
        expect(fixture.session.snapshot, hasLength(5));
        // One dense page owns 201 handles; two fit and a third must not be pinned.
        expect(fixture.session.activeIssuedLeases, 402);
        for (final target in [1, 2, 3, 4, 3, 2, 1, 0]) {
          expect(
            target > reports.last.pageIndex
                ? navigation.turnNext()
                : navigation.turnPrevious(),
            isTrue,
          );
          for (
            var frame = 0;
            frame < 100 && reports.last.pageIndex != target;
            frame++
          ) {
            await tester.pump(const Duration(milliseconds: 20));
            expect(controller.error, isNull);
            expect(fixture.session.activeIssuedLeases, lessThanOrEqualTo(512));
            expect(
              fixture.session.activeIssuedLeases +
                  fixture.session.reservedViewLeases,
              lessThanOrEqualTo(512),
            );
          }
          expect(reports.last.pageIndex, target);
          // Immediately request the next page before another cleanup frame: the
          // former origin may still have an Element while it loses keepAlive.
        }
        await tester.pumpWidget(const SizedBox.shrink());
        controller.close();
        expect(fixture.session.activeIssuedLeases, 0);
        expect(fixture.session.reservedViewLeases, 0);
        expect(fixture.cache.activeLeases, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final reverse in [false, true]) {
    testWidgets(
      'mixed native pages mount, navigate and preserve read-only restoration in reverse=$reverse',
      (tester) async {
        final fixture = _fixture(
          width: 30,
          html:
              '<p>${List.filled(10, 'X<ruby>AB<rt>xy</rt></ruby>').join()}</p>',
        );
        final controller = _controller(fixture, futureAnchor: true);
        final reports = <NovelReaderPaginationPosition>[];
        final navigation = NovelReaderPagedNavigationController();
        addTearDown(navigation.dispose);
        final owner = Object();
        final authority = Object();
        Widget reader() => _reader(
          controller,
          owner,
          authority,
          reports,
          width: 30,
          reverse: reverse,
          navigation: navigation,
        );
        await tester.pumpWidget(reader());
        await tester.pumpAndSettle();
        expect(find.byType(ForumBodyTextPageSurface), findsWidgets);
        expect(fixture.session.activeIssuedLeases, greaterThan(1));
        expect(reports, isNotEmpty);
        expect(reports.last.isReadOnlyCompatibilityRestore, isTrue);
        expect(reports.last.hasUserNavigated, isFalse);
        final firstIdentity = reports.last.anchor.textIdentity;
        await tester.pumpWidget(reader());
        await tester.pumpAndSettle();
        expect(
          reports.every((report) => report.isReadOnlyCompatibilityRestore),
          isTrue,
        );
        expect(navigation.turnNext(), isTrue);
        await tester.pumpAndSettle();
        expect(reports.last.pageIndex, 1);
        expect(reports.last.isReadOnlyCompatibilityRestore, isFalse);
        expect(reports.last.hasUserNavigated, isTrue);
        expect(reports.last.anchor.formatVersion, 1);
        expect(reports.last.anchor.textIdentity, firstIdentity);
        expect(reports.last.anchor.textOffset, greaterThan(0));
        await tester.pumpWidget(const SizedBox.shrink());
        controller.close();
        expect(fixture.session.activeIssuedLeases, 0);
        expect(fixture.session.reservedViewLeases, 0);
        expect(fixture.cache.activeLeases, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'inactive viewport defers a created source until it becomes active',
    (tester) async {
      final fixture = _fixture();
      final controller = _controller(fixture, futureAnchor: true);
      final owner = Object();
      final authority = Object();
      final positions = <NovelReaderPaginationPosition>[];
      await tester.pumpWidget(
        _reader(controller, owner, authority, positions, active: false),
      );
      await tester.pump(const Duration(hours: 1));
      expect(controller.phase, NovelReaderNativePagedPhase.created);
      expect(fixture.session.snapshot.length, 0);
      expect(fixture.cache.layoutBuildCount, 0);
      expect(positions, isEmpty);
      await tester.pumpWidget(_reader(controller, owner, authority, positions));
      await tester.pumpAndSettle();
      expect(positions.single.hasUserNavigated, isFalse);
      expect(positions.single.isReadOnlyCompatibilityRestore, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.close();
      expect(fixture.session.activeIssuedLeases, 0);
    },
  );
  for (final reverse in [false, true]) {
    testWidgets(
      'chrome turns use actual arrival and logical order in reverse=$reverse',
      (tester) async {
        final fixture = _fixture();
        final controller = _controller(fixture, offset: 45);
        final reports = <NovelReaderPaginationPosition>[];
        final navigation = NovelReaderPagedNavigationController();
        addTearDown(navigation.dispose);
        expect(navigation.turnNext(), isFalse);
        await tester.pumpWidget(
          _reader(
            controller,
            Object(),
            Object(),
            reports,
            reverse: reverse,
            navigation: navigation,
          ),
        );
        await tester.pumpAndSettle();
        expect(reports.last.pageIndex, 2);
        expect(navigation.turnNext(), isTrue);
        expect(navigation.turnNext(), isFalse);
        expect(reports, hasLength(1));
        await _startTapMotion(tester, 2);
        expect(reports, hasLength(1));
        expect(controller.visiblePageIndex, 2);
        expect(navigation.confirmChapterEndNavigation(), isFalse);
        await tester.pumpAndSettle();
        expect(reports.last.pageIndex, 3);
        expect(reports.last.hasUserNavigated, isTrue);
        expect(navigation.turnPrevious(), isTrue);
        await tester.pumpAndSettle();
        expect(reports.last.pageIndex, 2);
        expect(fixture.cache.layoutBuildCount, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(navigation.turnNext(), isFalse);
        controller.close();
        expect(fixture.session.activeIssuedLeases, 0);
      },
    );

    testWidgets(
      'opposite tap retires crossed-threshold motion in reverse=$reverse',
      (tester) async {
        final fixture = _fixture();
        final controller = _controller(fixture, offset: 45);
        final reports = <NovelReaderPaginationPosition>[];
        final navigation = NovelReaderPagedNavigationController();
        addTearDown(navigation.dispose);
        await tester.pumpWidget(
          _reader(
            controller,
            Object(),
            Object(),
            reports,
            reverse: reverse,
            navigation: navigation,
          ),
        );
        await tester.pumpAndSettle();
        expect(navigation.turnNext(), isTrue);
        await _startTapMotion(tester, 2);
        expect(navigation.turnPrevious(), isTrue);
        expect(_physicalPage(tester), 2);
        await tester.pumpAndSettle();
        expect(reports.map((position) => position.pageIndex), [2, 1]);
        await tester.pump(const Duration(seconds: 1));
        expect(_physicalPage(tester), 1);
        expect(reports, hasLength(2));
        expect(fixture.cache.layoutBuildCount, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.close();
        expect(fixture.session.activeIssuedLeases, 0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'external seek cancels moving pixels without canceling its new intent in reverse=$reverse',
      (tester) async {
        final fixture = _fixture();
        final controller = _controller(fixture, offset: 45);
        final reports = <NovelReaderPaginationPosition>[];
        final navigation = NovelReaderPagedNavigationController();
        addTearDown(navigation.dispose);
        await tester.pumpWidget(
          _reader(
            controller,
            Object(),
            Object(),
            reports,
            reverse: reverse,
            navigation: navigation,
          ),
        );
        await tester.pumpAndSettle();
        expect(navigation.turnNext(), isTrue);
        await _startTapMotion(tester, 2);
        expect(controller.requestPage(5), isTrue);
        await tester.pumpAndSettle();
        expect(reports.map((position) => position.pageIndex), [2, 5]);
        expect(reports.last.hasUserNavigated, isTrue);
        await tester.pump(const Duration(seconds: 1));
        expect(_physicalPage(tester), 5);
        expect(reports, hasLength(2));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'physical drag takes motion over without snapping back in reverse=$reverse',
      (tester) async {
        final fixture = _fixture();
        final controller = _controller(fixture, offset: 45);
        final reports = <NovelReaderPaginationPosition>[];
        final navigation = NovelReaderPagedNavigationController();
        addTearDown(navigation.dispose);
        await tester.pumpWidget(
          _reader(
            controller,
            Object(),
            Object(),
            reports,
            reverse: reverse,
            navigation: navigation,
          ),
        );
        await tester.pumpAndSettle();
        expect(navigation.turnNext(), isTrue);
        await _startTapMotion(tester, 2);
        await tester.drag(
          find.byType(PageView),
          Offset(reverse ? -100 : 100, 0),
        );
        await tester.pumpAndSettle();
        expect(reports.last.pageIndex, lessThanOrEqualTo(2));
        expect(reports.last.hasUserNavigated, isTrue);
        expect(reports.where((position) => position.pageIndex == 3), isEmpty);
        final settled = _physicalPage(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(_physicalPage(tester), settled);
        expect(controller.hasPendingNavigation, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final interruption in [
    'hidden',
    'reverse',
    'suspended',
    'cancelled',
    'cropped',
  ]) {
    testWidgets('tap motion is retired when $interruption', (tester) async {
      final fixture = _fixture();
      final controller = _controller(fixture, offset: 45, futureAnchor: true);
      final owner = Object();
      final authority = Object();
      final reports = <NovelReaderPaginationPosition>[];
      final navigation = NovelReaderPagedNavigationController();
      addTearDown(navigation.dispose);
      Widget reader({
        bool active = true,
        bool reverse = false,
        double width = 100,
      }) => _reader(
        controller,
        owner,
        authority,
        reports,
        active: active,
        reverse: reverse,
        navigation: navigation,
        width: width,
      );
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();
      final from = reports.single.pageIndex;
      expect(reports.single.isReadOnlyCompatibilityRestore, isTrue);
      expect(navigation.turnNext(), isTrue);
      await _startTapMotion(tester, from);
      switch (interruption) {
        case 'hidden':
          await tester.pumpWidget(reader(active: false));
        case 'reverse':
          await tester.pumpWidget(reader(reverse: true));
        case 'suspended':
          controller.suspend();
        case 'cancelled':
          controller.cancelPendingNavigation();
        case 'cropped':
          await tester.pumpWidget(reader(width: 60));
      }
      await tester.pumpAndSettle();
      expect(reports, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      if (interruption == 'suspended') controller.resume();
      await tester.pumpWidget(reader());
      await tester.pumpAndSettle();
      expect(_physicalPage(tester), from);
      expect(reports.every((position) => !position.hasUserNavigated), isTrue);
      expect(
        reports.every((position) => position.isReadOnlyCompatibilityRestore),
        isTrue,
      );
      expect(
        navigation.turnNext(),
        isTrue,
        reason:
            'after $interruption: '
            'pending=${controller.requestedPageIndex} visible=${controller.visiblePageIndex} '
            'scrolling=${tester.widget<PageView>(find.byType(PageView)).controller!.position.isScrollingNotifier.value}',
      );
      await tester.pumpAndSettle();
      expect(reports.last.pageIndex, from + 1);
      expect(reports.last.hasUserNavigated, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.close();
      expect(fixture.session.activeIssuedLeases, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'confirmed origin retention stays bounded across repeated tap turns',
    (tester) async {
      final fixture = _fixture();
      final controller = _controller(fixture);
      final reports = <NovelReaderPaginationPosition>[];
      final navigation = NovelReaderPagedNavigationController();
      addTearDown(navigation.dispose);
      await tester.pumpWidget(
        _reader(
          controller,
          Object(),
          Object(),
          reports,
          navigation: navigation,
        ),
      );
      await tester.pumpAndSettle();
      for (var page = 1; page < 10; page++) {
        expect(navigation.turnNext(), isTrue);
        await tester.pumpAndSettle();
        expect(reports.last.pageIndex, page);
        expect(fixture.session.activeIssuedLeases, lessThanOrEqualTo(3));
      }
      for (var page = 8; page >= 0; page--) {
        expect(navigation.turnPrevious(), isTrue);
        await tester.pumpAndSettle();
        expect(reports.last.pageIndex, page);
        expect(fixture.session.activeIssuedLeases, lessThanOrEqualTo(3));
      }
      expect(fixture.cache.layoutBuildCount, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.close();
      expect(fixture.session.activeIssuedLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final replacement in ['reflow', 'owner', 'dispose']) {
    testWidgets('$replacement retires a moving tap and its late completion', (
      tester,
    ) async {
      final old = _fixture();
      final oldController = _controller(old, offset: 45);
      final reports = <NovelReaderPaginationPosition>[];
      final navigation = NovelReaderPagedNavigationController();
      addTearDown(navigation.dispose);
      final owner = Object();
      final authority = Object();
      await tester.pumpWidget(
        _reader(
          oldController,
          owner,
          authority,
          reports,
          navigation: navigation,
        ),
      );
      await tester.pumpAndSettle();
      expect(navigation.turnNext(), isTrue);
      await _startTapMotion(tester, 2);
      NativeReaderTestFixture? next;
      _FrameGate? frames;
      if (replacement == 'dispose') {
        await tester.pumpWidget(const SizedBox.shrink());
      } else {
        next = _fixture(width: 60, layoutId: 'layout-b', cache: old.cache);
        frames = _FrameGate();
        final controller = _controller(next, offset: 45, frames: frames);
        await tester.pumpWidget(
          _reader(
            controller,
            replacement == 'owner' ? Object() : owner,
            authority,
            reports,
            width: 60,
            navigation: navigation,
          ),
        );
      }
      oldController.close();
      await tester.pump(const Duration(seconds: 1));
      expect(reports, hasLength(1));
      if (replacement == 'owner' || replacement == 'dispose') {
        expect(old.session.activeIssuedLeases, 0);
      }
      frames?.release();
      await tester.pumpAndSettle();
      expect(reports.every((position) => !position.hasUserNavigated), isTrue);
      if (next != null) {
        expect(reports.last.anchor.textOffset, 45);
        expect(old.session.activeIssuedLeases, 0);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(navigation.turnNext(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'rejected chapter commands cannot turn a readonly restore into navigation',
    (tester) async {
      final fixture = _fixture(html: '<p>abcd</p>');
      final controller = _controller(fixture, futureAnchor: true);
      final reports = <NovelReaderPaginationPosition>[];
      final navigation = NovelReaderPagedNavigationController();
      addTearDown(navigation.dispose);
      final edges = <NovelReaderChapterEdge>[];
      final confirmations = <bool>[];
      var accept = false;
      await tester.pumpWidget(
        _reader(
          controller,
          Object(),
          Object(),
          reports,
          navigation: navigation,
          onChapter: (edge) {
            edges.add(edge);
            if (accept && edge == NovelReaderChapterEdge.end) {
              confirmations.add(navigation.confirmChapterEndNavigation());
            }
            return accept;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(reports.single.isReadOnlyCompatibilityRestore, isTrue);
      expect(navigation.turnNext(), isFalse);
      expect(reports, hasLength(1));
      accept = true;
      expect(navigation.turnNext(), isTrue);
      expect(confirmations, [true]);
      expect(reports.last.hasUserNavigated, isTrue);
      expect(reports.last.isReadOnlyCompatibilityRestore, isFalse);
      expect(reports.last.isBodyEndVisible, isTrue);
      expect(navigation.turnNext(), isFalse);
      expect(edges, [NovelReaderChapterEdge.end, NovelReaderChapterEdge.end]);
      navigation.cancelChapterTurn();
      expect(navigation.turnPrevious(), isTrue);
      expect(edges.last, NovelReaderChapterEdge.start);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.session.activeIssuedLeases, 0);
    },
  );

  testWidgets(
    'cropping a mounted final page rejects chrome commands and end confirmation',
    (tester) async {
      final fixture = _fixture(html: '<p>abcd</p>');
      final controller = _controller(fixture, futureAnchor: true);
      final owner = Object();
      final authority = Object();
      final reports = <NovelReaderPaginationPosition>[];
      final navigation = NovelReaderPagedNavigationController();
      addTearDown(navigation.dispose);
      var chapters = 0;
      bool onChapter(NovelReaderChapterEdge _) {
        chapters++;
        return true;
      }

      await tester.pumpWidget(
        _reader(
          controller,
          owner,
          authority,
          reports,
          navigation: navigation,
          onChapter: onChapter,
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _reader(
          controller,
          owner,
          authority,
          reports,
          width: 50,
          navigation: navigation,
          onChapter: onChapter,
        ),
      );
      await tester.pumpAndSettle();
      expect(navigation.turnNext(), isFalse);
      expect(navigation.confirmChapterEndNavigation(), isFalse);
      expect(chapters, 0);
      expect(reports, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a drag cannot accept a chrome turn or confirm chapter end before settling',
    (tester) async {
      final fixture = _fixture();
      final controller = _controller(fixture, offset: 45);
      final reports = <NovelReaderPaginationPosition>[];
      final navigation = NovelReaderPagedNavigationController();
      addTearDown(navigation.dispose);
      await tester.pumpWidget(
        _reader(
          controller,
          Object(),
          Object(),
          reports,
          navigation: navigation,
        ),
      );
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 10));
      expect(navigation.turnNext(), isFalse);
      expect(navigation.turnPrevious(), isFalse);
      expect(navigation.confirmChapterEndNavigation(), isFalse);
      expect(reports, hasLength(1));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'canonical restore and external seek confirm settled mounted pages once',
    (tester) async {
      final fixture = _fixture();
      final controller = _controller(fixture, offset: 45);
      final reports = <NovelReaderPaginationPosition>[];
      await tester.pumpWidget(_reader(controller, Object(), Object(), reports));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(reports, hasLength(1));
      expect(reports.single.pageIndex, 2);
      expect(reports.single.anchor.textOffset, 45);
      expect(reports.single.hasUserNavigated, isFalse);
      expect(controller.requestPage(5), isTrue);
      expect(reports, hasLength(1));
      await tester.pumpAndSettle();
      expect(reports, hasLength(2));
      expect(reports.last.pageIndex, 5);
      expect(reports.last.hasUserNavigated, isTrue);
      expect(fixture.cache.layoutBuildCount, 1);
      expect(fixture.session.activeIssuedLeases, lessThanOrEqualTo(3));
      await tester.pumpWidget(const SizedBox.shrink());
      controller.close();
      expect(fixture.session.activeIssuedLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final reverse in [false, true]) {
    testWidgets('real drag navigates and returns in reverse=$reverse', (
      tester,
    ) async {
      final fixture = _fixture();
      final controller = _controller(fixture, offset: 45);
      final reports = <NovelReaderPaginationPosition>[];
      await tester.pumpWidget(
        _reader(controller, Object(), Object(), reports, reverse: reverse),
      );
      await tester.pumpAndSettle();
      final forward = reverse ? 80.0 : -80.0;
      await tester.drag(find.byType(PageView), Offset(forward, 0));
      await tester.pumpAndSettle();
      expect(reports.map((position) => position.pageIndex), [2, 3]);
      expect(reports.last.hasUserNavigated, isTrue);
      await tester.drag(find.byType(PageView), Offset(-forward, 0));
      await tester.pumpAndSettle();
      expect(reports.map((position) => position.pageIndex), [2, 3, 2]);
      expect(fixture.cache.layoutBuildCount, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'future anchor remains read-only through rebuild until a real drag',
    (tester) async {
      final fixture = _fixture();
      final controller = _controller(fixture, futureAnchor: true);
      final reports = <NovelReaderPaginationPosition>[];
      final owner = Object();
      final authority = Object();
      await tester.pumpWidget(_reader(controller, owner, authority, reports));
      await tester.pumpAndSettle();
      expect(reports.single.isReadOnlyCompatibilityRestore, isTrue);
      expect(reports.single.hasUserNavigated, isFalse);
      await tester.pumpWidget(_reader(controller, owner, authority, reports));
      await tester.pumpAndSettle();
      expect(reports, hasLength(1));
      await tester.drag(find.byType(PageView), const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(reports, hasLength(2));
      expect(reports.last.pageIndex, 1);
      expect(reports.last.isReadOnlyCompatibilityRestore, isFalse);
      expect(reports.last.hasUserNavigated, isTrue);
    },
  );

  testWidgets(
    'same-owner reflow retains the exact old box through controller retirement',
    (tester) async {
      final old = _fixture();
      final oldController = _controller(old, offset: 45);
      final reports = <NovelReaderPaginationPosition>[];
      final owner = Object();
      final authority = Object();
      await tester.pumpWidget(
        _reader(oldController, owner, authority, reports),
      );
      await tester.pumpAndSettle();
      final oldSurface = tester.renderObject(
        find.byType(ForumBodyParagraphSurface),
      );
      final next = _fixture(width: 60, layoutId: 'layout-b', cache: old.cache);
      final frames = _FrameGate();
      final controller = _controller(next, offset: 45, frames: frames);
      await tester.pumpWidget(
        _reader(controller, owner, authority, reports, width: 60),
      );
      oldController.close();
      await tester.pumpAndSettle();
      expect(
        tester.renderObject(find.byType(ForumBodyParagraphSurface)),
        same(oldSurface),
      );
      expect(
        tester.getSize(find.byType(ForumBodyTextPageSurface)),
        const Size(100, 20),
      );
      expect(reports, hasLength(1));
      expect(old.session.activeIssuedLeases, greaterThan(0));
      frames.release();
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(ForumBodyTextPageSurface)),
        const Size(60, 20),
      );
      expect(reports, hasLength(2));
      expect(reports.last.anchor.textOffset, 45);
      expect(reports.last.hasUserNavigated, isFalse);
      expect(old.session.activeIssuedLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new owner clears old mounted leases while its target is pending',
    (tester) async {
      final old = _fixture();
      final oldController = _controller(old);
      final reports = <NovelReaderPaginationPosition>[];
      await tester.pumpWidget(
        _reader(oldController, Object(), Object(), reports),
      );
      await tester.pumpAndSettle();
      final next = _fixture(layoutId: 'new-owner');
      final frames = _FrameGate();
      final controller = _controller(next, frames: frames);
      await tester.pumpWidget(_reader(controller, Object(), Object(), reports));
      await tester.pumpAndSettle();
      expect(find.byType(ForumBodyTextPageSurface), findsNothing);
      expect(find.byKey(const Key('native-waiting')), findsOneWidget);
      expect(old.session.activeIssuedLeases, lessThanOrEqualTo(2));
      oldController.close();
      expect(old.session.activeIssuedLeases, 0);
      frames.release();
      await tester.pumpAndSettle();
      expect(reports, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'authority replacement rejects old pending navigation and callbacks',
    (tester) async {
      final old = _fixture();
      final oldController = _controller(old);
      final owner = Object();
      final reports = <NovelReaderPaginationPosition>[];
      await tester.pumpWidget(_reader(oldController, owner, Object(), reports));
      await tester.pumpAndSettle();
      expect(oldController.requestPage(5), isTrue);
      final next = _fixture(layoutId: 'new-authority', cache: old.cache);
      final frames = _FrameGate();
      final controller = _controller(next, frames: frames, futureAnchor: true);
      final authority = Object();
      await tester.pumpWidget(_reader(controller, owner, authority, reports));
      await tester.pumpAndSettle();
      expect(reports, hasLength(1));
      expect(oldController.visiblePageIndex, 0);
      frames.release();
      await tester.pumpAndSettle();
      expect(reports, hasLength(2));
      expect(reports.last.pageIndex, 0);
      expect(reports.last.isReadOnlyCompatibilityRestore, isTrue);
      expect(reports.last.hasUserNavigated, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a new drag retires a missing-page arrival and keeps the confirmed mounted view',
    (tester) async {
      final idle = Completer<void>();
      final frames = _FrameGate(held: false);
      final fixture = _fixture();
      final controller = _controller(
        fixture,
        frames: frames,
        idle: () => idle.future,
      );
      final reports = <NovelReaderPaginationPosition>[];
      await tester.pumpWidget(_reader(controller, Object(), Object(), reports));
      await tester.pumpAndSettle();
      expect(controller.snapshot!.isComplete, isFalse);
      final original = tester.renderObject(
        find.byType(ForumBodyParagraphSurface),
      );
      frames.hold();
      expect(controller.requestPage(8), isTrue);
      await tester.pumpAndSettle();
      expect(controller.requestedPageIndex, 8);
      expect(reports, hasLength(1));
      await tester.drag(find.byType(PageView), const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(controller.requestedPageIndex, 0);
      frames.release();
      idle.complete();
      await tester.pumpAndSettle();
      expect(controller.visiblePageIndex, 0);
      expect(reports, hasLength(1));
      expect(
        tester.renderObject(find.byType(ForumBodyParagraphSurface)),
        same(original),
      );
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        0,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.close();
      expect(fixture.session.activeIssuedLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a cropped viewport cannot confirm a full content box', (
    tester,
  ) async {
    final fixture = _fixture();
    final controller = _controller(fixture);
    final owner = Object();
    final authority = Object();
    final reports = <NovelReaderPaginationPosition>[];
    await tester.pumpWidget(
      _reader(controller, owner, authority, reports, width: 60),
    );
    await tester.pumpAndSettle();
    expect(reports, isEmpty);
    expect(controller.visiblePageIndex, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(_reader(controller, owner, authority, reports));
    await tester.pumpAndSettle();
    expect(reports, hasLength(1));
    expect(controller.visiblePageIndex, 0);
    expect(fixture.cache.layoutBuildCount, 1);
  });

  testWidgets(
    'late source failure retains reading until real navigation within its accepted prefix',
    (tester) async {
      final idle = Completer<void>();
      final fixture = _fixture(
        html: '$_html<blockquote>unsupported</blockquote>',
      );
      final controller = _controller(fixture, idle: () => idle.future);
      final reports = <NovelReaderPaginationPosition>[];
      await tester.pumpWidget(_reader(controller, Object(), Object(), reports));
      await tester.pumpAndSettle();
      expect(reports, hasLength(1));
      expect(controller.error, isNull);
      idle.complete();
      await tester.pumpAndSettle();
      expect(controller.phase, NovelReaderNativePagedPhase.paused);
      expect(find.byType(ForumBodyTextPageSurface), findsOneWidget);
      expect(reports, hasLength(1));
      expect(controller.visiblePageIndex, 0);
      final prefix = controller.snapshot;
      final error = controller.error;
      final builds = fixture.cache.layoutBuildCount;
      await tester.drag(find.byType(PageView), const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(reports, hasLength(2));
      expect(reports.last.pageIndex, 1);
      expect(reports.last.hasUserNavigated, isTrue);
      expect(reports.last.isReadOnlyCompatibilityRestore, isFalse);
      expect(controller.phase, NovelReaderNativePagedPhase.paused);
      expect(controller.error, same(error));
      expect(controller.snapshot, same(prefix));
      await tester.drag(find.byType(PageView), const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(reports, hasLength(3));
      expect(reports.last.pageIndex, 0);
      expect(fixture.cache.layoutBuildCount, builds);
      expect(controller.requestPage(prefix!.length), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.session.activeIssuedLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
