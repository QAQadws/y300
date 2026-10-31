import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/domain/models/novel_reader_preferences.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_native_paged_controller.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_paged_navigation_controller.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_chapter_turn.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_position.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';
import 'package:y300/features/novel/presentation/widgets/novel_reader_native_paged_viewport.dart';

import '../test_support/native_reader_test_fixture.dart';

class _Reader {
  _Reader({
    String html = '<p>abcd</p>',
    Future<void> Function()? idle,
    double width = 100,
  }) {
    fixture = NativeReaderTestFixture(
      html,
      width: width,
      height: 20,
      complete: false,
    );
    final anchor = fixture.anchors.segments.first.projection.baseAnchor;
    controller = NovelReaderNativePagedController(
      session: fixture.session,
      anchors: fixture.anchors,
      position: NovelReaderProgressSnapshot(
        novelId: 'novel',
        episodeId: 'episode',
        flowMode: NovelReaderFlowMode.pagedLtr,
        scrollOffset: 0,
        pageIndex: 0,
        anchorNodeId: anchor.nodeId,
        anchorTextOffset: 0,
        anchorFormatVersion: 37,
        anchorTextIdentity: anchor.textIdentity,
        progressPercent: 0,
        isProgressPercentValid: true,
      ),
      paginationKey: 'layout:$width',
      parent: fixture.parent,
      performance: const NovelReaderPaginationPerformancePolicy(
        enforceBudgets: false,
      ),
      idleScheduler: idle ?? () async {},
    );
    addTearDown(controller.close);
    addTearDown(navigation.dispose);
  }
  late final NativeReaderTestFixture fixture;
  late final NovelReaderNativePagedController controller;
  final navigation = NovelReaderPagedNavigationController();
  final owner = Object();
  final authority = Object();
  final positions = <NovelReaderPaginationPosition>[];
  final hints = <NovelReaderChapterTurnHint?>[];
  final edges = <NovelReaderChapterEdge>[];
  final endConfirmations = <bool>[];
  bool accept = true;
  bool confirmEnd = true;

  Widget widget({
    bool active = true,
    bool reverse = false,
    double width = 100,
    bool inFlight = false,
    String? previousTitle = ' previous ',
    String? nextTitle = ' next ',
    NovelReaderPagedNavigationController? port,
    NovelReaderChapterTurnPolicy policy = const NovelReaderChapterTurnPolicy(),
    ValueChanged<NovelReaderChapterTurnHint?>? onHint,
    Object? ownerIdentity,
    Object? authorityIdentity,
  }) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: 20,
        child: NovelReaderNativePagedViewport(
          controller: controller,
          ownerIdentity: ownerIdentity ?? owner,
          readingAuthorityIdentity: authorityIdentity ?? authority,
          active: active,
          reverse: reverse,
          navigationController: port ?? navigation,
          previousChapterTitle: previousTitle,
          nextChapterTitle: nextTitle,
          chapterTurnPolicy: policy,
          chapterTurnIsInFlight: inFlight,
          onChapterTurnHintChanged: onHint ?? hints.add,
          onPositionChanged: positions.add,
          onTurnToAdjacentChapter: (edge) {
            edges.add(edge);
            if (accept && confirmEnd && edge == NovelReaderChapterEdge.end) {
              endConfirmations.add(
                (port ?? navigation).confirmChapterEndNavigation(),
              );
            }
            return accept;
          },
        ),
      ),
    ),
  );
}

Future<TestGesture> _pull(WidgetTester tester, double distance) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(PageView)),
  );
  await gesture.moveBy(Offset(distance, 0));
  await tester.pump();
  return gesture;
}

void main() {
  testWidgets(
    'seek during an interior drag cannot be hidden by its next physical page request',
    (tester) async {
      final reader = _Reader(
        html: '<p>${List.filled(12, 'abcdefghijklmnopqrst').join()}</p>',
      );
      await tester.pumpWidget(reader.widget());
      await tester.pumpAndSettle();
      final last = reader.controller.snapshot!.length - 1;
      expect(reader.controller.requestPage(last - 2), isTrue);
      await tester.pumpAndSettle();
      final gesture = await _pull(tester, -60);
      expect(reader.controller.requestPage(0), isTrue);
      // No frame/microtask drain between the explicit seek and physical motion.
      await gesture.moveBy(const Offset(-300, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(reader.edges, isEmpty);
      expect(reader.hints.whereType<NovelReaderChapterTurnHint>(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('hint-driven shell rebuilds do not replay unchanged callbacks', (
    tester,
  ) async {
    final reader = _Reader();
    final received = <NovelReaderChapterTurnHint?>[];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, rebuild) => reader.widget(
          onHint: (hint) {
            received.add(hint);
            rebuild(() {});
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final gesture = await _pull(tester, -80);
    await tester.pumpAndSettle();
    expect(received, hasLength(1));
    expect(received.single!.isReadyToCommit, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(received, hasLength(2));
    expect(received.last, isNull);
    expect(reader.edges, [NovelReaderChapterEdge.end]);
  });

  for (final interruption in ['cancel', 'seek', 'drag', 'hidden']) {
    testWidgets(
      '$interruption after release retires its queued chapter action',
      (tester) async {
        final reader = _Reader();
        await tester.pumpWidget(reader.widget());
        await tester.pumpAndSettle();
        final gesture = await _pull(tester, -80);
        await gesture.up();
        expect(reader.edges, isEmpty);
        TestGesture? next;
        switch (interruption) {
          case 'cancel':
            reader.navigation.cancelChapterTurn();
          case 'seek':
            reader.controller.requestPage(0);
          case 'drag':
            next = await _pull(tester, -20);
          case 'hidden':
            await tester.pumpWidget(reader.widget(active: false));
        }
        await next?.up();
        await tester.pumpAndSettle();
        expect(reader.edges, isEmpty);
        expect(reader.hints.last, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'ballistic and nested overscroll cannot inflate a real boundary pull',
    (tester) async {
      final reader = _Reader();
      await tester.pumpWidget(reader.widget());
      await tester.pumpAndSettle();
      final gesture = await _pull(tester, -20);
      expect(reader.hints.single!.isReadyToCommit, isFalse);
      final view = tester.widget<PageView>(find.byType(PageView));
      final context = tester.element(find.byType(PageView));
      OverscrollNotification(
        metrics: view.controller!.position,
        context: context,
        overscroll: 100,
      ).dispatch(context);
      final nested = tester.element(find.byType(ForumBodyParagraphSurface));
      OverscrollNotification(
        metrics: view.controller!.position,
        context: nested,
        dragDetails: DragUpdateDetails(
          globalPosition: Offset.zero,
          delta: const Offset(-100, 0),
        ),
        overscroll: 100,
      ).dispatch(nested);
      await tester.pump();
      expect(
        reader.hints.whereType<NovelReaderChapterTurnHint>().every(
          (hint) => !hint.isReadyToCommit,
        ),
        isTrue,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(reader.edges, isEmpty);
      expect(reader.hints.last, isNull);
      expect(reader.positions, hasLength(1));
    },
  );

  for (final title in [null, '   ']) {
    testWidgets('unavailable title $title cannot offer a chapter gesture', (
      tester,
    ) async {
      final reader = _Reader();
      await tester.pumpWidget(
        reader.widget(previousTitle: title, nextTitle: title),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(-100, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(PageView), const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(reader.edges, isEmpty);
      expect(reader.hints.whereType<NovelReaderChapterTurnHint>(), isEmpty);
    });
  }
  for (final reverse in [false, true]) {
    for (final edge in NovelReaderChapterEdge.values) {
      testWidgets(
        'hint, release and accepted latch in reverse=$reverse edge=$edge',
        (tester) async {
          final reader = _Reader();
          await tester.pumpWidget(reader.widget(reverse: reverse));
          await tester.pumpAndSettle();
          expect(
            reader.positions.single.isReadOnlyCompatibilityRestore,
            isTrue,
          );
          final direction =
              (edge == NovelReaderChapterEdge.end ? -1.0 : 1.0) *
              (reverse ? -1 : 1);
          final gesture = await _pull(tester, direction * 40);
          expect(
            reader.hints.last,
            NovelReaderChapterTurnHint(
              edge: edge,
              chapterTitle: edge == NovelReaderChapterEdge.end
                  ? 'next'
                  : 'previous',
              isReadyToCommit: false,
            ),
          );
          expect(reader.edges, isEmpty);
          await gesture.moveBy(Offset(direction * 40, 0));
          await tester.pump();
          expect(reader.hints.last!.isReadyToCommit, isTrue);
          expect(reader.positions, hasLength(1));
          await gesture.up();
          await tester.pumpAndSettle();
          expect(reader.edges, [edge]);
          expect(reader.hints.last, isNull);
          if (edge == NovelReaderChapterEdge.end) {
            expect(reader.endConfirmations, [true]);
            expect(reader.positions.last.hasUserNavigated, isTrue);
          } else {
            expect(reader.positions, hasLength(1));
          }
          await tester.drag(find.byType(PageView), Offset(direction * 100, 0));
          await tester.pumpAndSettle();
          expect(reader.edges, [edge]);
          reader.navigation.cancelChapterTurn();
          await tester.drag(find.byType(PageView), Offset(direction * 100, 0));
          await tester.pumpAndSettle();
          expect(reader.edges, [edge, edge]);
          await tester.pumpWidget(const SizedBox.shrink());
          reader.controller.close();
          expect(reader.fixture.session.activeIssuedLeases, 0);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'subthreshold release and declined turns preserve readonly state and remain retryable',
    (tester) async {
      final reader = _Reader()..accept = false;
      await tester.pumpWidget(reader.widget());
      await tester.pumpAndSettle();
      final small = await _pull(tester, -40);
      expect(reader.hints.last!.isReadyToCommit, isFalse);
      await small.up();
      await tester.pumpAndSettle();
      expect(reader.edges, isEmpty);
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.drag(find.byType(PageView), const Offset(-100, 0));
        await tester.pumpAndSettle();
        expect(reader.edges, hasLength(attempt + 1));
        expect(reader.hints.last, isNull);
      }
      expect(reader.positions, hasLength(1));
      expect(reader.positions.single.isReadOnlyCompatibilityRestore, isTrue);
    },
  );

  testWidgets('reversing a one-page pull discards its ready old peak', (
    tester,
  ) async {
    final reader = _Reader();
    await tester.pumpWidget(reader.widget());
    await tester.pumpAndSettle();
    final gesture = await _pull(tester, -80);
    expect(reader.hints.last!.edge, NovelReaderChapterEdge.end);
    expect(reader.hints.last!.isReadyToCommit, isTrue);
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(reader.hints.last!.edge, NovelReaderChapterEdge.start);
    expect(reader.hints.last!.isReadyToCommit, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(reader.edges, isEmpty);
    expect(reader.positions, hasLength(1));
  });

  for (final interruption in [
    'hidden',
    'reverse',
    'seek',
    'cancel',
    'suspended',
    'cropped',
    'titles',
    'policy',
    'inflight',
    'port',
  ]) {
    testWidgets('$interruption retires a ready pull and its eventual release', (
      tester,
    ) async {
      final reader = _Reader();
      await tester.pumpWidget(reader.widget());
      await tester.pumpAndSettle();
      final gesture = await _pull(tester, -80);
      expect(reader.hints.last!.isReadyToCommit, isTrue);
      switch (interruption) {
        case 'hidden':
          await tester.pumpWidget(reader.widget(active: false));
        case 'reverse':
          await tester.pumpWidget(reader.widget(reverse: true));
        case 'seek':
          expect(reader.controller.requestPage(0), isTrue);
        case 'cancel':
          reader.navigation.cancelChapterTurn();
        case 'suspended':
          reader.controller.suspend();
        case 'cropped':
          await tester.pumpWidget(reader.widget(width: 60));
        case 'titles':
          await tester.pumpWidget(reader.widget(nextTitle: 'changed'));
        case 'policy':
          await tester.pumpWidget(
            reader.widget(
              policy: const NovelReaderChapterTurnPolicy(
                minCommitDistance: 200,
              ),
            ),
          );
        case 'inflight':
          await tester.pumpWidget(reader.widget(inFlight: true));
        case 'port':
          final next = NovelReaderPagedNavigationController();
          addTearDown(next.dispose);
          await tester.pumpWidget(reader.widget(port: next));
      }
      await tester.pump();
      expect(reader.hints.last, isNull);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(reader.edges, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  for (final replacement in ['owner', 'reflow', 'dispose']) {
    testWidgets('$replacement suppresses old pull callbacks', (tester) async {
      final old = _Reader();
      await tester.pumpWidget(old.widget());
      await tester.pumpAndSettle();
      final gesture = await _pull(tester, -80);
      expect(old.hints.last!.isReadyToCommit, isTrue);
      final next = _Reader(width: replacement == 'reflow' ? 60 : 100);
      if (replacement == 'dispose') {
        await tester.pumpWidget(const SizedBox.shrink());
      } else {
        await tester.pumpWidget(
          next.widget(
            width: replacement == 'reflow' ? 60 : 100,
            ownerIdentity: replacement == 'reflow' ? old.owner : null,
            authorityIdentity: replacement == 'reflow' ? old.authority : null,
          ),
        );
      }
      old.controller.close();
      final oldEvents = old.hints.length;
      await gesture.up();
      await tester.pumpAndSettle();
      expect(old.edges, isEmpty);
      expect(next.edges, isEmpty);
      expect(old.hints, hasLength(oldEvents));
      expect(old.fixture.session.activeIssuedLeases, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'equivalent policy rebuild keeps the pull and uses the latest hint callback',
    (tester) async {
      final reader = _Reader();
      await tester.pumpWidget(reader.widget());
      await tester.pumpAndSettle();
      final gesture = await _pull(tester, -40);
      final oldEvents = reader.hints.length;
      final replacementHints = <NovelReaderChapterTurnHint?>[];
      await tester.pumpWidget(
        reader.widget(
          policy: NovelReaderChapterTurnPolicy(
            minCommitDistance: reader.positions.length * 44.0,
          ),
          onHint: replacementHints.add,
        ),
      );
      await tester.pump();
      expect(replacementHints, isEmpty);
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      expect(replacementHints.last!.isReadyToCommit, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(reader.edges, [NovelReaderChapterEdge.end]);
      expect(replacementHints.last, isNull);
      expect(reader.hints, hasLength(oldEvents));
    },
  );

  testWidgets(
    'EOF cannot arm a gesture that started with an incomplete prefix',
    (tester) async {
      final idle = Completer<void>();
      final reader = _Reader(
        html: '<p>${List.filled(12, 'abcdefghijklmnopqrst').join()}</p>',
        idle: () => idle.future,
      );
      await tester.pumpWidget(reader.widget());
      for (
        var attempt = 0;
        attempt < 50 && reader.positions.isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(reader.positions, hasLength(1));
      expect(reader.controller.snapshot!.isComplete, isFalse);
      final gesture = await _pull(tester, 80);
      idle.complete();
      await tester.pumpAndSettle();
      expect(reader.controller.snapshot!.isComplete, isTrue);
      await gesture.moveBy(const Offset(100, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(reader.edges, isEmpty);
      expect(reader.hints.whereType<NovelReaderChapterTurnHint>(), isEmpty);
      expect(reader.positions, hasLength(1));
      await tester.drag(find.byType(PageView), const Offset(100, 0));
      await tester.pumpAndSettle();
      expect(reader.edges, [NovelReaderChapterEdge.start]);
    },
  );

  for (final reverse in [false, true]) {
    for (final edge in NovelReaderChapterEdge.values) {
      testWidgets(
        'complete-chapter interior pull preserves direction=$reverse edge=$edge',
        (tester) async {
          final reader = _Reader(
            html: '<p>${List.filled(12, 'abcdefghijklmnopqrst').join()}</p>',
          );
          await tester.pumpWidget(reader.widget(reverse: reverse));
          await tester.pumpAndSettle();
          final last = reader.controller.snapshot!.length - 1;
          expect(
            reader.controller.requestPage(
              edge == NovelReaderChapterEdge.end ? last - 1 : 1,
            ),
            isTrue,
          );
          await tester.pumpAndSettle();
          final direction =
              (edge == NovelReaderChapterEdge.end ? -1.0 : 1.0) *
              (reverse ? -1 : 1);
          final gesture = await _pull(tester, direction * 150);
          await gesture.moveBy(Offset(direction * 100, 0));
          await tester.pump();
          await gesture.up();
          await tester.pumpAndSettle();
          expect(
            reader.positions.last.pageIndex,
            edge == NovelReaderChapterEdge.end ? last : 0,
          );
          expect(reader.edges, [edge]);
          if (edge == NovelReaderChapterEdge.end) {
            expect(reader.endConfirmations, [true]);
          }
          expect(reader.positions.last.hasUserNavigated, isTrue);
        },
      );
    }
  }
}
