import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_native_page_view.dart';
import 'package:y300/features/novel/presentation/models/novel_reader_pagination_exception.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_page_coverage_cursor.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_page_view_job.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';

import '../test_support/native_reader_test_fixture.dart';

final class _Frames {
  final pending = Queue<Completer<void>>();
  int calls = 0;
  Future<void> next() {
    calls++;
    final frame = Completer<void>();
    pending.add(frame);
    return frame.future;
  }

  Future<void> tick() async {
    await Future<void>.delayed(Duration.zero);
    expect(pending, isNotEmpty);
    pending.removeFirst().complete();
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> until(bool Function() condition) async {
    for (var turn = 0; turn < 1000 && !condition(); turn++) {
      if (pending.isNotEmpty) {
        await tick();
      } else {
        await Future<void>.delayed(Duration.zero);
      }
    }
    expect(
      condition(),
      isTrue,
      reason: 'Controlled frame task did not progress',
    );
  }
}

NovelReaderNativePageViewJob _job(
  NativeReaderTestFixture fixture,
  _Frames frames, {
  NovelReaderNativeViewJobLimits limits =
      const NovelReaderNativeViewJobLimits(),
}) => NovelReaderNativePageViewJob(
  session: fixture.session,
  anchors: fixture.anchors,
  pageIndex: 0,
  parent: fixture.parent,
  scheduler: NovelReaderNativeWorkScheduler(nextFrame: frames.next),
  limits: limits,
);

Matcher get _cancelled => throwsA(
  isA<NovelReaderPaginationException>().having(
    (error) => error.code,
    'code',
    'paginationCancelled',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cached page from an unfinished source needs no frame to become ready',
    () async {
      final fixture = NativeReaderTestFixture(
        '<p>abcdefghijklmnopqrst</p>',
        width: 20,
        height: 10,
        complete: false,
      );
      fixture.finishSource(pages: 1);
      expect(fixture.session.isComplete, false);
      final warmingFrames = _Frames();
      final warming = _job(fixture, warmingFrames);
      final first = warming.run();
      await warmingFrames.until(
        () => warming.state == NovelReaderNativeViewJobState.complete,
      );
      (await first).close();
      warming.close();
      final frames = _Frames();
      final job = _job(
        fixture,
        frames,
        limits: const NovelReaderNativeViewJobLimits(
          frameBudget: Duration(days: 1),
        ),
      );
      addTearDown(job.close);
      final builds = fixture.cache.layoutBuildCount;
      final future = job.run();
      future.ignore();
      await Future<void>.delayed(Duration.zero);
      expect(frames.calls, 0);
      expect(job.state, NovelReaderNativeViewJobState.complete);
      final view = await future;
      expect(view.isReady, true);
      expect(fixture.cache.layoutBuildCount, builds);
      view.close();
      expect(fixture.session.isClosed, false);
      fixture.session.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'a transferred table owns its generation before any cell is delivered',
    () async {
      final fixture = NativeReaderTestFixture(
        '<table><tr><td>cell</td></tr></table>',
        dedicatedTables: true,
      );
      final frames = _Frames();
      final active = _job(fixture, frames);
      addTearDown(active.close);
      final running = active.run();
      await frames.until(
        () => active.state == NovelReaderNativeViewJobState.complete,
      );
      final view = await running;
      expect(fixture.session.activeIssuedTablePages, 1);
      expect(fixture.cache.activeLeases, 0);
      expect(view.takeFragments, throwsStateError);
      final mount = view.takeMount();
      expect(mount.fragments, isEmpty);
      view.close();
      fixture.parent.cancel();
      expect(mount.table!.isActive, isTrue);
      expect(fixture.session.ownsTablePageLease(0, mount.table!), isTrue);
      mount.table!.close();
      expect(fixture.session.activeIssuedTablePages, 0);
      expect(mount.table!.isActive, isFalse);
    },
  );

  test('work records describe the actual cold and warm delivery without owning its leases', () async {
    final fixture = NativeReaderTestFixture('<p><ruby>A<rt>x</rt></ruby></p>');
    for (final warm in [false, true]) {
      final frames = _Frames();
      final job = _job(
        fixture,
        frames,
        limits: const NovelReaderNativeViewJobLimits(
          frameBudget: Duration(days: 1),
          maxStepsPerFrame: 1,
        ),
      );
      final layouts = fixture.cache.layoutBuildCount;
      final pictures = fixture.cache.pictureBuildCount;
      final running = job.run();
      await frames.until(
        () => job.state == NovelReaderNativeViewJobState.complete,
      );
      final view = await running;
      final work = view.work!;
      expect(work.preparationFrames + work.coverageFrames, job.framesWaited);
      expect(work.preparationFrames, greaterThan(0));
      expect(work.coverageFrames, greaterThan(0));
      expect(work.preparationSteps, greaterThan(0));
      expect(work.coverageSteps, greaterThan(0));
      expect(work.checkedGraphemes, 2);
      expect(work.layoutsBuilt, fixture.cache.layoutBuildCount - layouts);
      expect(work.picturesBuilt, fixture.cache.pictureBuildCount - pictures);
      expect(
        work.preparationAdvanceUs,
        inInclusiveRange(0, work.preparationUs),
      );
      expect(work.coverageAdvanceUs, inInclusiveRange(0, work.coverageUs));
      for (final advances in [
        work.preparationAdvances,
        work.coverageAdvances,
      ]) {
        expect(advances.budgetUs, const Duration(days: 1).inMicroseconds);
        expect(advances.maxUs, inInclusiveRange(1, advances.totalUs));
        expect(advances.overBudgetSteps, 0);
      }
      if (warm) {
        expect(work.layoutsBuilt, 0);
        expect(work.picturesBuilt, 0);
      } else {
        expect(work.picturesBuilt, greaterThan(0));
      }
      final fragments = view.takeFragments();
      view.close();
      expect(view.work, same(work));
      expect(fragments.every((f) => f.isActive), isTrue);
      for (final fragment in fragments) {
        fragment.close();
      }
      expect(fixture.session.activeIssuedLeases, 0);
      job.close();
    }
  });

  test('cached page uses only cached work before its first frame', () async {
    final fixture = NativeReaderTestFixture('<p><ruby>A<rt>x</rt></ruby></p>');
    const limits = NovelReaderNativeViewJobLimits(
      frameBudget: Duration(days: 1),
    );
    final frames = _Frames();
    final cold = _job(fixture, frames, limits: limits);
    addTearDown(cold.close);
    final layouts = fixture.cache.layoutBuildCount;
    final pictures = fixture.cache.pictureBuildCount;
    final pending = cold.run();
    await Future<void>.delayed(Duration.zero);
    expect(frames.calls, 1);
    expect(cold.state, NovelReaderNativeViewJobState.preparing);
    expect(fixture.cache.layoutBuildCount, layouts);
    expect(fixture.cache.pictureBuildCount, pictures);
    await frames.until(
      () => cold.state == NovelReaderNativeViewJobState.complete,
    );
    final first = await pending;
    expect(first.work!.picturesBuilt, greaterThan(0));
    first.close();

    final warmFrames = _Frames();
    final warm = _job(fixture, warmFrames, limits: limits);
    addTearDown(warm.close);
    final resumed = warm.run();
    await Future<void>.delayed(Duration.zero);
    expect(warmFrames.calls, 0);
    expect(warm.state, NovelReaderNativeViewJobState.complete);
    final visible = await resumed;
    expect(visible, isNot(same(first)));
    expect(visible.snapshot, same(first.snapshot));
    expect(visible.work!.layoutsBuilt, 0);
    expect(visible.work!.picturesBuilt, 0);
    expect(visible.work!.checkedGraphemes, 2);
    visible.close();
    expect(fixture.session.activeIssuedLeases, 0);
  });

  test(
    'resumed reservation waits for a former mounted page to release',
    () async {
      final fixture = NativeReaderTestFixture('<p>a</p>', maxIssuedLeases: 1);
      final preparation = fixture.session.openPagePreparation(0);
      while (!preparation.isReady) {
        preparation.advance(maxFragments: 1);
      }
      final former = preparation.takeFragments().single;
      final frames = _Frames();
      final job = _job(fixture, frames);
      expect(fixture.session.pendingPreparationCount, 0);
      expect(fixture.session.reservedViewLeases, 0);
      final running = job.run();
      expect(frames.calls, 1);
      expect(fixture.session.pendingPreparationCount, 0);
      expect(former.isActive, isTrue);
      former.close();
      await frames.until(
        () => job.state == NovelReaderNativeViewJobState.complete,
      );
      (await running).close();
      expect(fixture.session.activeIssuedLeases, 0);
    },
  );

  test(
    'cancelling an early resume releases only its new reservation',
    () async {
      final fixture = NativeReaderTestFixture('<p>a</p>', maxIssuedLeases: 2);
      final former = fixture.session.preparePageFragments(0).single;
      addTearDown(former.close);
      final frames = _Frames();
      final job = _job(fixture, frames);
      final pending = job.run();
      final cancelled = expectLater(pending, _cancelled);
      expect(fixture.session.reservedViewLeases, 1);
      fixture.parent.cancel();
      await cancelled;
      expect(frames.calls, 0);
      expect(fixture.session.pendingPreparationCount, 0);
      expect(fixture.session.reservedViewLeases, 0);
      expect(former.isActive, isTrue);
    },
  );

  test(
    'cancelling an early resume releases only its new reservation',
    () async {
      final fixture = NativeReaderTestFixture('<p>a</p>', maxIssuedLeases: 2);
      final former = fixture.session.preparePageFragments(0).single;
      addTearDown(former.close);
      final frames = _Frames();
      final job = _job(fixture, frames);
      final pending = job.run();
      final cancelled = expectLater(pending, _cancelled);
      expect(fixture.session.reservedViewLeases, 1);
      fixture.parent.cancel();
      await cancelled;
      expect(frames.calls, 0);
      expect(fixture.session.pendingPreparationCount, 0);
      expect(fixture.session.reservedViewLeases, 0);
      expect(former.isActive, isTrue);
    },
  );

  test('cancellation before the first frame never reserves or releases another view', () async {
    final fixture = NativeReaderTestFixture('<p>a</p>', maxIssuedLeases: 1);
    final preparation = fixture.session.openPagePreparation(0);
    while (!preparation.isReady) {
      preparation.advance(maxFragments: 1);
    }
    final former = preparation.takeFragments().single;
    final frames = _Frames();
    final job = _job(fixture, frames);
    final running = job.run();
    final cancelled = expectLater(running, _cancelled);
    fixture.parent.cancel();
    await cancelled;
    expect(fixture.session.pendingPreparationCount, 0);
    expect(fixture.session.reservedViewLeases, 0);
    expect(former.isActive, isTrue);
    frames.pending.removeFirst().completeError(
      StateError('late initial frame'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(former.isActive, isTrue);
    former.close();
    expect(fixture.session.activeIssuedLeases, 0);
  });

  testWidgets(
    'mixed jobs transfer all native children once and mounted surfaces own their lifetime',
    (tester) async {
      final fixture = NativeReaderTestFixture(
        '<p>X<ruby>AB<rp>(fallback)</rp><rt>xy</rt></ruby>Y</p>',
        width: 100,
        height: 30,
      );
      fixture.cache.clearUnpinned();
      final frames = _Frames();
      final job = _job(fixture, frames);
      final running = job.run();
      await tester.pump();
      while (job.state != NovelReaderNativeViewJobState.complete) {
        expect(frames.pending, isNotEmpty);
        frames.pending.removeFirst().complete();
        await tester.pump();
      }
      final view = await running;
      expect(view.coverage.points, hasLength(12));
      expect(view.takeLeases, throwsStateError);
      expect(view.isReady, isTrue);
      final fragments = view.takeFragments();
      expect(fragments.single, isA<ForumBodyPreparedInlineFragment>());
      final handles = fragments.single.nativeLeases.toList();
      expect(handles, hasLength(3));
      expect(handles.every((handle) => handle.isActive), isTrue);
      expect(view.takeFragments, throwsStateError);
      view.close();
      fixture.parent.cancel();
      expect(handles.every((handle) => handle.isActive), isTrue);
      final builds = fixture.cache.layoutBuildCount;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: ForumBodyTextPageSurface.prepared(
              snapshot: view.snapshot,
              pageIndex: 0,
              layoutId: view.snapshot.layoutId,
              fragments: fragments,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(fixture.cache.layoutBuildCount, builds);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(handles.every((handle) => !handle.isActive), isTrue);
      expect(fixture.cache.activeLeases, 0);
      expect(fixture.session.reservedViewLeases, 0);
    },
  );

  test('mixed coverage failure rolls back every issued child and can retry the same source page', () async {
    final fixture = NativeReaderTestFixture(
      '<p>X<ruby>AB<rt>xy</rt></ruby>Y</p>',
    );
    final frames = _Frames();
    final job = _job(
      fixture,
      frames,
      limits: const NovelReaderNativeViewJobLimits(
        coverage: NovelReaderNativeCoverageLimits(maxPoints: 1),
      ),
    );
    final running = job.run();
    final failed = expectLater(
      running,
      throwsA(isA<NovelReaderNativeCoverageException>()),
    );
    await frames.until(() => job.state == NovelReaderNativeViewJobState.failed);
    await failed;
    expect(fixture.cache.activeLeases, 0);
    expect(fixture.session.reservedViewLeases, 0);
    expect(fixture.session.snapshot, hasLength(1));
    final retry = _job(fixture, frames);
    final retried = retry.run();
    await frames.until(
      () => retry.state == NovelReaderNativeViewJobState.complete,
    );
    final view = await retried;
    final fragments = view.takeFragments();
    expect(fragments.single, isA<ForumBodyPreparedInlineFragment>());
    fragments.single.close();
    expect(fixture.cache.activeLeases, 0);
  });

  test('cancelling a budget wait detaches only that task and allows a fresh request', () async {
    final fixture = NativeReaderTestFixture(
      '<p>a</p><p>b</p>',
      cacheEntries: 2,
    );
    fixture.cache.clearUnpinned();
    final foreign = fixture.pinForeign();
    final frames = _Frames();
    final job = _job(fixture, frames);
    final running = job.run();
    await frames.until(
      () => job.state == NovelReaderNativeViewJobState.waitingForBudget,
    );
    job.close();
    await expectLater(running, _cancelled);
    expect(foreign.isActive, isTrue);
    expect(fixture.parent.isCancelled, isFalse);
    expect(fixture.session.reservedViewLeases, 0);
    expect(fixture.cache.activeLeases, 1);
    final frameCount = frames.calls;
    foreign.release();
    await Future<void>.delayed(Duration.zero);
    expect(frames.calls, frameCount);
    final retry = _job(fixture, frames);
    final retried = retry.run();
    await frames.until(
      () => retry.state == NovelReaderNativeViewJobState.complete,
    );
    (await retried).close();
  });

  test('a failed frame scheduler returns the whole reservation without retiring its parent', () async {
    final fixture = NativeReaderTestFixture('<p>a</p>');
    fixture.cache.clearUnpinned();
    final job = NovelReaderNativePageViewJob(
      session: fixture.session,
      anchors: fixture.anchors,
      pageIndex: 0,
      parent: fixture.parent,
      scheduler: NovelReaderNativeWorkScheduler(
        nextFrame: () => throw StateError('synthetic frame failure'),
      ),
    );
    await expectLater(job.run(), throwsStateError);
    expect(job.state, NovelReaderNativeViewJobState.failed);
    expect(fixture.session.reservedViewLeases, 0);
    expect(fixture.cache.activeLeases, 0);
    expect(fixture.parent.isCancelled, isFalse);
  });

  test('ready views release unmounted native references on source or cache retirement', () async {
    for (final closeCache in [false, true]) {
      final fixture = NativeReaderTestFixture('<p>a</p>');
      final frames = _Frames();
      final job = _job(fixture, frames);
      final running = job.run();
      await frames.until(
        () => job.state == NovelReaderNativeViewJobState.complete,
      );
      final view = await running;
      if (closeCache) {
        fixture.cache.close();
      } else {
        fixture.session.close();
      }
      expect(view.isReady, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(view.state, NovelReaderNativePageViewState.closed);
      expect(view.takeLeases, throwsStateError);
      expect(fixture.cache.activeLeases, 0);
    }
  });

  testWidgets(
    'cold preparation, actual coverage and mounted painting share native layouts',
    (tester) async {
      final fixture = NativeReaderTestFixture('<p>a</p><p>b</p>');
      fixture.cache.clearUnpinned();
      final frames = _Frames();
      final job = _job(fixture, frames);
      final builds = fixture.cache.layoutBuildCount;
      final running = job.run();
      expect(job.run(), same(running));
      expect(fixture.cache.layoutBuildCount, builds);
      await tester.pump();
      while (job.state != NovelReaderNativeViewJobState.complete) {
        expect(frames.pending, isNotEmpty);
        frames.pending.removeFirst().complete();
        await tester.pump();
      }
      final view = await running;
      expect(fixture.cache.layoutBuildCount - builds, 2);
      expect(view.coverage.points, hasLength(4));
      expect(fixture.session.reservedViewLeases, 0);
      expect(view.isReady, isTrue);
      final leases = view.takeLeases();
      expect(view.takeLeases, throwsStateError);
      view.close();
      fixture.parent.cancel();
      expect(leases.every((lease) => lease.isActive), isTrue);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: ForumBodyTextPageSurface(
              snapshot: view.snapshot,
              pageIndex: 0,
              layoutId: view.snapshot.layoutId,
              leases: leases,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(fixture.cache.layoutBuildCount - builds, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'a cache-only multi-step path yields by work count without shaping',
    () async {
      final fixture = NativeReaderTestFixture('<p>a</p><p>b</p><p>c</p>');
      final frames = _Frames();
      final builds = fixture.cache.layoutBuildCount;
      final job = _job(
        fixture,
        frames,
        limits: const NovelReaderNativeViewJobLimits(
          preparationFragments: 1,
          coverageGraphemes: 1,
          coverageFragments: 1,
          maxStepsPerFrame: 1,
        ),
      );
      final running = job.run();
      await frames.until(
        () => job.state == NovelReaderNativeViewJobState.complete,
      );
      final view = await running;
      expect(frames.calls, greaterThan(3));
      expect(fixture.cache.layoutBuildCount, builds);
      view.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test('external native pressure waits for release events instead of requesting frames', () async {
    final fixture = NativeReaderTestFixture(
      '<p>a</p><p>b</p>',
      cacheEntries: 2,
    );
    fixture.cache.clearUnpinned();
    final foreign = fixture.pinForeign();
    final frames = _Frames();
    final job = _job(fixture, frames);
    final running = job.run();
    await frames.until(
      () => job.state == NovelReaderNativeViewJobState.waitingForBudget,
    );
    final frameCount = frames.calls;
    final builds = fixture.cache.layoutBuildCount;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(frames.calls, frameCount);
    expect(fixture.cache.layoutBuildCount, builds);
    foreign.release();
    await frames.until(
      () => job.state == NovelReaderNativeViewJobState.complete,
    );
    final view = await running;
    expect(view.isReady, isTrue);
    expect(fixture.cache.layoutBuildCount - builds, 1);
    view.close();
  });

  test('partial cancellation releases native references and reservations without cancelling the source', () async {
    final fixture = NativeReaderTestFixture('<p>a</p><p>b</p>');
    fixture.cache.clearUnpinned();
    final frames = _Frames();
    final job = _job(
      fixture,
      frames,
      limits: const NovelReaderNativeViewJobLimits(maxStepsPerFrame: 1),
    );
    final running = job.run();
    await frames.tick();
    expect(fixture.cache.activeLeases, 1);
    expect(fixture.session.reservedViewLeases, 2);
    job.close();
    await expectLater(running, _cancelled);
    expect(job.state, NovelReaderNativeViewJobState.closed);
    expect(fixture.parent.isCancelled, isFalse);
    expect(fixture.session.isClosed, isFalse);
    expect(fixture.session.reservedViewLeases, 0);
    expect(fixture.cache.activeLeases, 0);
    frames.pending.removeFirst().completeError(StateError('late frame'));
    await Future<void>.delayed(Duration.zero);
  });

  test('ready but unmounted views retire with their parent even after the job is complete', () async {
    final fixture = NativeReaderTestFixture('<p>a</p>');
    final frames = _Frames();
    final job = _job(fixture, frames);
    final running = job.run();
    await frames.until(
      () => job.state == NovelReaderNativeViewJobState.complete,
    );
    final view = await running;
    job.close();
    expect(view.isReady, isTrue);
    expect(fixture.cache.activeLeases, 1);
    fixture.parent.cancel();
    expect(view.state, NovelReaderNativePageViewState.closed);
    expect(view.takeLeases, throwsStateError);
    expect(fixture.cache.activeLeases, 0);
  });

  test('coverage failure rolls back issued leases and preserves retryable source pages', () async {
    final fixture = NativeReaderTestFixture('<p>abc</p>');
    final frames = _Frames();
    final job = _job(
      fixture,
      frames,
      limits: const NovelReaderNativeViewJobLimits(
        coverage: NovelReaderNativeCoverageLimits(maxPoints: 1),
      ),
    );
    final running = job.run();
    final error = expectLater(
      running,
      throwsA(isA<NovelReaderNativeCoverageException>()),
    );
    await frames.until(() => job.state == NovelReaderNativeViewJobState.failed);
    await error;
    expect(fixture.session.isComplete, isTrue);
    expect(fixture.cache.activeLeases, 0);
    expect(fixture.session.reservedViewLeases, 0);
    final retry = _job(fixture, frames);
    final retried = retry.run();
    await frames.until(
      () => retry.state == NovelReaderNativeViewJobState.complete,
    );
    (await retried).close();
  });

  test(
    'retired sources end frame waits while their borrowed cache remains open',
    () async {
      final fixture = NativeReaderTestFixture('<p>a</p>');
      final frames = _Frames();
      final job = _job(fixture, frames);
      final running = job.run();
      final error = expectLater(running, _cancelled);
      fixture.session.close();
      await error;
      expect(job.state, NovelReaderNativeViewJobState.closed);
      expect(fixture.cache.isClosed, isFalse);
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'parent retirement during input scaling cannot publish or revive a job',
    () async {
      var cancelDuringScale = false;
      late NativeReaderTestFixture fixture;
      fixture = NativeReaderTestFixture(
        '<p>a</p>',
        textScaler: _CallbackScaler((size) {
          if (cancelDuringScale) fixture.parent.cancel();
          return size;
        }),
      );
      fixture.cache.clearUnpinned();
      cancelDuringScale = true;
      final frames = _Frames();
      final job = _job(fixture, frames);
      final running = job.run();
      final error = expectLater(running, _cancelled);
      await error;
      expect(job.state, NovelReaderNativeViewJobState.closed);
      expect(fixture.cache.activeLeases, 0);
      expect(fixture.session.reservedViewLeases, 0);
    },
  );

  test(
    'pending cancellation and invalid limits do not retain preparation slots',
    () {
      final fixture = NativeReaderTestFixture('<p>a</p>');
      final frames = _Frames();
      expect(
        () => _job(
          fixture,
          frames,
          limits: const NovelReaderNativeViewJobLimits(maxStepsPerFrame: 0),
        ),
        throwsArgumentError,
      );
      expect(fixture.session.pendingPreparationCount, 0);
      final job = _job(fixture, frames);
      job.close();
      expect(fixture.session.pendingPreparationCount, 0);
      expect(job.run, throwsStateError);
      fixture.parent.cancel();
      expect(() => _job(fixture, frames), _cancelled);
      expect(fixture.session.pendingPreparationCount, 0);
    },
  );
}

final class _CallbackScaler extends TextScaler {
  const _CallbackScaler(this.callback);
  final double Function(double) callback;
  @override
  double scale(double fontSize) => callback(fontSize);
  @override
  double get textScaleFactor => 1;
}
