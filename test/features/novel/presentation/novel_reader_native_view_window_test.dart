import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_page_view.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_view_window.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_source_run.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_page_view_job.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_demand.dart';

import '../test_support/native_reader_test_fixture.dart';

const _html = '<p>ab</p><p>cd</p><p>ef</p><p>gh</p>';

Future<void> _flush() async {
  for (var turn = 0; turn < 40; turn++) {
    await Future<void>.value();
  }
}

NovelReaderNativeViewWindow _window(
  NativeReaderTestFixture fixture, {
  int center = 0,
  NovelReaderNativeWorkScheduler? scheduler,
  NovelReaderNativeViewWindowLimits limits =
      const NovelReaderNativeViewWindowLimits(),
}) {
  final window = NovelReaderNativeViewWindow(
    session: fixture.session,
    anchors: fixture.anchors,
    parent: fixture.parent,
    centerPageIndex: center,
    scheduler:
        scheduler ?? NovelReaderNativeWorkScheduler(nextFrame: () async {}),
    limits: limits,
  );
  addTearDown(window.close);
  return window;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('target is published before serial neighbors and the window remains bounded', () async {
    final fixture = NativeReaderTestFixture(_html, width: 20, height: 10);
    final window = _window(fixture, center: 1);
    final observed = <List<int>>[];
    final subscription = window.changes.listen((_) {
      observed.add([
        for (var page = 0; page < 4; page++)
          if (window.viewForPage(page) != null) page,
      ]);
    });
    addTearDown(subscription.cancel);
    final builds = fixture.cache.layoutBuildCount;
    final run = window.prepareAvailable();
    expect(window.prepareAvailable(), same(run));
    await run;
    await _flush();
    expect(observed.first, [1]);
    expect(window.retainedPageCount, 3);
    expect(window.retainedFragments, 3);
    expect(window.retainedCoveragePoints, 12);
    expect(window.viewForPage(3), isNull);
    expect(fixture.cache.layoutBuildCount, builds);
    expect(fixture.session.pendingPreparationCount, 0);
    final retired = window.viewForPage(0)!;
    window.setCenter(2);
    await window.prepareAvailable();
    expect(retired.state, NovelReaderNativePageViewState.closed);
    expect(window.retainedPageCount, 3);
    expect(window.viewForPage(3)!.isReady, isTrue);
  });

  test('window retirement leaves transferred leases with their actual Surface owner', () async {
    final fixture = NativeReaderTestFixture(_html, width: 20, height: 10);
    final window = _window(
      fixture,
      limits: const NovelReaderNativeViewWindowLimits(radius: 0),
    );
    await window.prepareAvailable();
    final first = window.viewForPage(0)!;
    final leases = first.takeLeases();
    await window.prepareAvailable();
    expect(window.viewForPage(0), same(first));
    expect(fixture.session.activeIssuedLeases, 1);
    window.setCenter(2);
    await window.prepareAvailable();
    expect(first.state, NovelReaderNativePageViewState.closed);
    expect(leases.single.isActive, isTrue);
    window.close();
    expect(leases.single.isActive, isTrue);
    expect(fixture.session.isClosed, isFalse);
    leases.single.release();
    expect(fixture.session.activeIssuedLeases, 0);
  });

  test('optional pressure defers without waiting and the next target retires old unmounted pins', () async {
    final fixture = NativeReaderTestFixture(
      _html,
      cacheEntries: 1,
      width: 20,
      height: 10,
    );
    var frames = 0;
    final window = _window(
      fixture,
      scheduler: NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          frames++;
        },
      ),
    );
    await window.prepareAvailable();
    expect(window.retainedPageCount, 1);
    final previous = window.viewForPage(0)!;
    expect(window.viewForPage(1), isNull);
    final builds = fixture.cache.layoutBuildCount;
    final before = frames;
    await window.prepareAvailable();
    expect(frames, before);
    expect(fixture.cache.layoutBuildCount, builds);
    window.setCenter(1);
    await window.prepareAvailable();
    expect(previous.state, NovelReaderNativePageViewState.closed);
    expect(window.viewForPage(1)!.isReady, isTrue);
    expect(window.retainedPageCount, 1);
    expect(fixture.session.reservedViewLeases, 0);
  });

  test(
    'promoting a neighbor preserves its preparation and enables target waiting',
    () async {
      final fixture = NativeReaderTestFixture(
        '<p>ab</p><p>cd</p>',
        cacheEntries: 1,
        width: 20,
        height: 10,
      );
      final neighborFrame = Completer<void>();
      final neighborStarted = Completer<void>();
      var frames = 0;
      final window = _window(
        fixture,
        scheduler: NovelReaderNativeWorkScheduler(
          nextFrame: () {
            if (++frames == 2) {
              neighborStarted.complete();
              return neighborFrame.future;
            }
            return Future.value();
          },
        ),
      );
      var completed = false;
      final run = window.prepareAvailable().then((_) => completed = true);
      await neighborStarted.future;
      final preparationCount = fixture.session.pendingPreparationCount;
      expect(preparationCount, 1);
      window.setCenter(1);
      expect(fixture.session.pendingPreparationCount, preparationCount);
      final foreign = fixture.pinForeign();
      neighborFrame.complete();
      await _flush();
      expect(completed, isFalse);
      expect(window.viewForPage(1), isNull);
      final waitingFrames = frames;
      await _flush();
      expect(frames, waitingFrames);
      foreign.release();
      await run;
      expect(window.viewForPage(1)!.isReady, isTrue);
      expect(fixture.session.pendingPreparationCount, 0);
    },
  );

  test(
    'new center cancels an old frame task and cannot publish its obsolete page',
    () async {
      final fixture = NativeReaderTestFixture(_html, width: 20, height: 10);
      final firstFrame = Completer<void>();
      var frames = 0;
      final window = _window(
        fixture,
        scheduler: NovelReaderNativeWorkScheduler(
          nextFrame: () {
            return ++frames == 1 ? firstFrame.future : Future.value();
          },
        ),
      );
      final run = window.prepareAvailable();
      window.setCenter(3);
      await run;
      expect(window.viewForPage(0), isNull);
      expect(window.viewForPage(3)!.isReady, isTrue);
      expect(window.retainedPageCount, 2);
      firstFrame.completeError(StateError('late retired frame'));
      await _flush();
      expect(fixture.parent.isCancelled, isFalse);
    },
  );

  test('logical proof budgets defer neighbors once instead of a self-release retry loop', () async {
    final fixture = NativeReaderTestFixture(_html, width: 20, height: 10);
    var frames = 0;
    final window = _window(
      fixture,
      center: 1,
      scheduler: NovelReaderNativeWorkScheduler(
        nextFrame: () async {
          frames++;
        },
      ),
      limits: const NovelReaderNativeViewWindowLimits(
        maxRetainedCoveragePoints: 4,
      ),
    );
    await window.prepareAvailable();
    expect(window.retainedCoveragePoints, 4);
    expect(window.retainedPageCount, 1);
    expect(window.viewForPage(1)!.isReady, isTrue);
    final before = frames;
    await window.prepareAvailable();
    expect(frames, before);
    expect(fixture.session.reservedViewLeases, 0);
    expect(fixture.session.activeIssuedLeases, 1);
  });

  test(
    'an intrinsically impossible neighbor does not break the readable target',
    () async {
      final fixture = NativeReaderTestFixture(
        '<p style="font-size:20px">a</p><p>e</p><p>f</p>',
        cacheEntries: 1,
        width: 20,
        height: 20,
      );
      expect(fixture.session.snapshot[0].fragments, hasLength(1));
      expect(fixture.session.snapshot[1].fragments, hasLength(2));
      final window = _window(fixture);
      await window.prepareAvailable();
      expect(window.viewForPage(0)!.isReady, isTrue);
      expect(window.viewForPage(1), isNull);
      window.setCenter(1);
      await expectLater(
        window.prepareAvailable(),
        throwsA(isA<ForumBodyTextPagePreparationException>()),
      );
      expect(fixture.session.reservedViewLeases, 0);
    },
  );

  test('missing targets do not prepare preceding pages and can resume on a larger prefix', () async {
    final fixture = NativeReaderTestFixture(
      _html,
      width: 20,
      height: 10,
      complete: false,
    );
    fixture.finishSource(pages: 1);
    final window = _window(fixture, center: 2);
    final builds = fixture.cache.layoutBuildCount;
    await window.prepareAvailable();
    expect(window.retainedPageCount, 0);
    expect(fixture.cache.layoutBuildCount, builds);
    fixture.finishSource(pages: 3);
    await window.prepareAvailable();
    expect(window.viewForPage(2)!.isReady, isTrue);
    expect(window.viewForPage(0), isNull);
  });

  test(
    'late unmount acknowledgement cannot remove a replacement view',
    () async {
      final fixture = NativeReaderTestFixture(_html, width: 20, height: 10);
      final window = _window(
        fixture,
        limits: const NovelReaderNativeViewWindowLimits(radius: 0),
      );
      await window.prepareAvailable();
      final old = window.viewForPage(0)!;
      window.forgetPage(0, old);
      await window.prepareAvailable();
      final replacement = window.viewForPage(0)!;
      expect(replacement, isNot(same(old)));
      window.forgetPage(0, old);
      expect(window.viewForPage(0), same(replacement));
    },
  );

  test('terminal retirement closes pending work and drops owned views without closing the source', () async {
    final fixture = NativeReaderTestFixture(_html, width: 20, height: 10);
    final frame = Completer<void>();
    final window = _window(
      fixture,
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () => frame.future),
    );
    final run = window.prepareAvailable();
    fixture.parent.cancel();
    await run;
    expect(window.isClosed, isTrue);
    expect(window.retainedPageCount, 0);
    expect(fixture.session.reservedViewLeases, 0);
    expect(fixture.session.isClosed, isFalse);
    expect(fixture.cache.isClosed, isFalse);
    expect(window.prepareAvailable, throwsStateError);
    frame.complete();
  });

  test('a target exceeding the logical window budget releases its view and stays recoverable', () async {
    final fixture = NativeReaderTestFixture(_html, width: 20, height: 10);
    final window = _window(
      fixture,
      limits: const NovelReaderNativeViewWindowLimits(maxRetainedFragments: 0),
    );
    await expectLater(
      window.prepareAvailable(),
      throwsA(isA<NovelReaderNativeViewWindowBudgetException>()),
    );
    expect(window.retainedPageCount, 0);
    expect(fixture.session.activeIssuedLeases, 0);
    expect(fixture.session.isClosed, isFalse);
  });

  testWidgets(
    'mounted old content stays readable until the replacement Surface takes over',
    (tester) async {
      final fixture = NativeReaderTestFixture(_html, width: 20, height: 10);
      final window = _window(
        fixture,
        limits: const NovelReaderNativeViewWindowLimits(radius: 0),
      );
      await window.prepareAvailable();
      final first = window.viewForPage(0)!;
      final oldLeases = first.takeLeases();
      Widget surface(
        NovelReaderNativePageView view,
        List<ForumBodyParagraphLease> leases,
      ) => Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 20,
            height: 10,
            child: ForumBodyTextPageSurface(
              snapshot: view.snapshot,
              pageIndex: view.pageIndex,
              layoutId: 'generation-a',
              leases: leases,
            ),
          ),
        ),
      );
      await tester.pumpWidget(surface(first, oldLeases));
      final builds = fixture.cache.layoutBuildCount;
      window.setCenter(1);
      await window.prepareAvailable();
      expect(oldLeases.single.isActive, isTrue);
      expect(tester.takeException(), isNull);
      final second = window.viewForPage(1)!;
      final newLeases = second.takeLeases();
      await tester.pumpWidget(surface(second, newLeases));
      expect(oldLeases.single.isActive, isFalse);
      expect(newLeases.single.isActive, isTrue);
      expect(fixture.cache.layoutBuildCount, builds);
      window.close();
      expect(newLeases.single.isActive, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(newLeases.single.isActive, isFalse);
      expect(fixture.session.activeIssuedLeases, 0);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'optional deferral is terminal and rolls back its entire preparation',
    () async {
      final fixture = NativeReaderTestFixture('<p>abc</p>', cacheEntries: 1);
      final foreign = fixture.pinForeign();
      final job = NovelReaderNativePageViewJob(
        session: fixture.session,
        anchors: fixture.anchors,
        pageIndex: 0,
        parent: fixture.parent,
        waitForLayoutBudget: false,
        scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
      );
      await expectLater(
        job.run(),
        throwsA(isA<NovelReaderNativeViewBudgetDeferred>()),
      );
      expect(job.state, NovelReaderNativeViewJobState.deferred);
      expect(job.promote(), isFalse);
      expect(job.run, throwsStateError);
      expect(fixture.session.reservedViewLeases, 0);
      expect(fixture.cache.activeLeases, 1);
      foreign.release();
      job.close();
    },
  );

  test(
    'source publication and view windows share one serial lane until EOF',
    () async {
      final fixture = NativeReaderTestFixture(
        _html,
        width: 20,
        height: 10,
        complete: false,
      );
      final window = _window(fixture, center: 2);
      final demand = NovelReaderPaginationDemand(
        lookAhead: 0,
        idleScheduler: () async {},
      );
      addTearDown(demand.dispose);
      final run = NovelReaderNativeSourceRun(
        session: fixture.session,
        demand: demand,
        parent: fixture.parent,
        scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
        onPublication: (snapshot, _) async {
          await window.prepareAvailable();
          demand.update(
            targetPending: window.viewForPage(2) == null,
            pageIndex: 2,
          );
        },
      );
      addTearDown(run.close);
      await run.run();
      expect(window.viewForPage(0), isNull);
      expect(window.viewForPage(2)!.isReady, isTrue);
      expect(window.retainedPageCount, 3);
      expect(fixture.cache.layoutBuildCount, 4);
      expect(fixture.session.isComplete, isTrue);
      expect(fixture.session.reservedViewLeases, 0);
    },
  );
}
