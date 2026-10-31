import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/data/models/novel_models.dart';
import 'package:y300/features/novel/domain/services/novel_reader_progress_policy.dart';
import 'package:y300/features/novel/presentation/controllers/novel_reader_native_paged_controller.dart';
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
  bool reverse = false,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: width,
      height: 20,
      child: NovelReaderNativePagedViewport(
        controller: controller,
        ownerIdentity: owner,
        readingAuthorityIdentity: authority,
        reverse: reverse,
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

void main() {
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
