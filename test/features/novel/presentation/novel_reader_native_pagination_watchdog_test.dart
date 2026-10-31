import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_pagination_watchdog.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_source_run.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_view_window.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_work_scheduler.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_demand.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';

import '../test_support/native_reader_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cancelling an unreadable target creates no background timer and cannot retire a newer ticket', () {
    fakeAsync((clock) {
      final failures = <String?>[];
      final watch = NovelReaderNativePaginationWatchdog(
        parent: NovelReaderPaginationCancellationToken(),
        elapsed: () => clock.elapsed,
        onExpired: (error, _) => failures.add(error.code),
      );
      final old = watch.startTarget();
      clock.elapse(const Duration(seconds: 4));
      expect(watch.cancelTarget(old), isTrue);
      expect(clock.nonPeriodicTimerCount, 0);
      clock.elapse(const Duration(minutes: 10));
      expect(failures, isEmpty);
      watch.startTarget();
      expect(watch.cancelTarget(old), isFalse);
      clock.elapse(const Duration(seconds: 5));
      expect(failures, ['targetPageWaitExceeded']);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });

  test('cancelling a seek preserves the actual readable source active stall allowance', () {
    fakeAsync((clock) {
      final failures = <String?>[];
      final watch = NovelReaderNativePaginationWatchdog(
        parent: NovelReaderPaginationCancellationToken(),
        elapsed: () => clock.elapsed,
        onExpired: (error, _) => failures.add(error.code),
      );
      watch.publication(pageCount: 10, isComplete: false);
      watch.markReadable(watch.startTarget());
      clock.elapse(const Duration(milliseconds: 1500));
      final seek = watch.startTarget();
      clock.elapse(const Duration(seconds: 4));
      expect(watch.cancelTarget(seek), isTrue);
      clock.elapse(const Duration(milliseconds: 499));
      expect(failures, isEmpty);
      clock.elapse(const Duration(milliseconds: 1));
      expect(failures, ['backgroundPaginationIdle']);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });

  test('suspension retires the target and owns no timer until visible', () {
    fakeAsync((clock) {
      final failures = <String?>[];
      final watch = NovelReaderNativePaginationWatchdog(
        parent: NovelReaderPaginationCancellationToken(),
        elapsed: () => clock.elapsed,
        onExpired: (error, _) => failures.add(error.code),
      );
      final old = watch.startTarget();
      clock.elapse(const Duration(seconds: 4));
      watch.setSuspended(true);
      expect(watch.markReadable(old), isFalse);
      expect(clock.nonPeriodicTimerCount, 0);
      expect(() => watch.startTarget(), throwsStateError);
      watch.setDeferring(false);
      clock.elapse(const Duration(hours: 1));
      expect(failures, isEmpty);
      watch.setSuspended(false);
      watch.startTarget();
      clock.elapse(const Duration(seconds: 4));
      expect(failures, isEmpty);
      clock.elapse(const Duration(seconds: 1));
      expect(failures, ['targetPageWaitExceeded']);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });

  test('repeated suspension preserves the remaining active background stall allowance', () {
    fakeAsync((clock) {
      final failures = <String?>[];
      final watch = NovelReaderNativePaginationWatchdog(
        parent: NovelReaderPaginationCancellationToken(),
        elapsed: () => clock.elapsed,
        onExpired: (error, _) => failures.add(error.code),
      );
      watch.publication(pageCount: 10, isComplete: false);
      watch.markReadable(watch.startTarget());
      clock.elapse(const Duration(milliseconds: 1000));
      watch.setSuspended(true);
      expect(clock.nonPeriodicTimerCount, 0);
      clock.elapse(const Duration(hours: 1));
      watch.setDeferring(true);
      watch.setDeferring(false);
      watch.setSuspended(false);
      watch.markReadable(watch.startTarget());
      clock.elapse(const Duration(milliseconds: 600));
      watch.setSuspended(true);
      clock.elapse(const Duration(hours: 1));
      watch.setSuspended(false);
      watch.markReadable(watch.startTarget());
      clock.elapse(const Duration(milliseconds: 399));
      expect(failures, isEmpty);
      clock.elapse(const Duration(milliseconds: 1));
      expect(failures, ['backgroundPaginationIdle']);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });

  test('reading another existing page cannot reset the outstanding background stall allowance', () {
    fakeAsync((clock) {
      final failures = <String?>[];
      final watch = NovelReaderNativePaginationWatchdog(
        parent: NovelReaderPaginationCancellationToken(),
        elapsed: () => clock.elapsed,
        onExpired: (error, _) => failures.add(error.code),
      );
      watch.publication(pageCount: 10, isComplete: false);
      watch.markReadable(watch.startTarget());
      clock.elapse(const Duration(milliseconds: 1500));
      final navigation = watch.startTarget();
      clock.elapse(const Duration(seconds: 1));
      expect(failures, isEmpty);
      watch.markReadable(navigation);
      clock.elapse(const Duration(milliseconds: 499));
      expect(failures, isEmpty);
      clock.elapse(const Duration(milliseconds: 1));
      expect(failures, ['backgroundPaginationIdle']);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });
  test('target deadline includes preparation and cannot be satisfied by publication or EOF', () {
    fakeAsync((clock) {
      final parent = NovelReaderPaginationCancellationToken();
      final failures = <String?>[];
      NovelReaderNativeTargetWait? expired;
      final watch = NovelReaderNativePaginationWatchdog(
        parent: parent,
        elapsed: () => clock.elapsed,
        onExpired: (error, ticket) {
          failures.add(error.code);
          expired = ticket;
        },
      );
      final target = watch.startTarget();
      clock.elapse(const Duration(seconds: 4));
      watch.publication(pageCount: 10, isComplete: true);
      clock.elapse(const Duration(seconds: 1));
      expect(failures, ['targetPageWaitExceeded']);
      expect(expired, same(target));
      expect(parent.isCancelled, isFalse);
      expect(watch.isClosed, isTrue);
      expect(watch.isExpired, isTrue);
      expect(clock.nonPeriodicTimerCount, 0);
      expect(watch.markReadable(target), isFalse);
    });
  });

  test('new target retires old ticket and readable EOF cancels every remaining timer', () {
    fakeAsync((clock) {
      final failures = <String?>[];
      final watch = NovelReaderNativePaginationWatchdog(
        parent: NovelReaderPaginationCancellationToken(),
        elapsed: () => clock.elapsed,
        onExpired: (error, _) => failures.add(error.code),
      );
      final old = watch.startTarget();
      clock.elapse(const Duration(seconds: 4));
      final current = watch.startTarget();
      expect(watch.markReadable(old), isFalse);
      clock.elapse(const Duration(seconds: 4));
      expect(failures, isEmpty);
      watch.publication(pageCount: 3, isComplete: true);
      expect(watch.markReadable(current), isTrue);
      expect(watch.isWaitingForTarget, isFalse);
      clock.elapse(const Duration(minutes: 1));
      expect(failures, isEmpty);
      expect(clock.nonPeriodicTimerCount, 0);
      watch.close();
    });
  });

  test('background time excludes idle while repeated idle transitions cannot reset an active stall', () {
    fakeAsync((clock) {
      final failures = <String?>[];
      final watch = NovelReaderNativePaginationWatchdog(
        parent: NovelReaderPaginationCancellationToken(),
        elapsed: () => clock.elapsed,
        onExpired: (error, ticket) {
          expect(ticket, isNull);
          failures.add(error.code);
        },
      );
      watch.markReadable(watch.startTarget());
      clock.elapse(const Duration(seconds: 1));
      watch.setDeferring(true);
      expect(clock.nonPeriodicTimerCount, 0);
      clock.elapse(const Duration(minutes: 1));
      expect(failures, isEmpty);
      watch.setDeferring(false);
      clock.elapse(const Duration(milliseconds: 600));
      watch.setDeferring(true);
      clock.elapse(const Duration(minutes: 1));
      watch.setDeferring(false);
      clock.elapse(const Duration(milliseconds: 399));
      expect(failures, isEmpty);
      clock.elapse(const Duration(milliseconds: 1));
      expect(failures, ['backgroundPaginationIdle']);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });

  test('only a new stable page resets background allowance, repeated snapshots do not', () {
    fakeAsync((clock) {
      final failures = <String?>[];
      final watch = NovelReaderNativePaginationWatchdog(
        parent: NovelReaderPaginationCancellationToken(),
        elapsed: () => clock.elapsed,
        onExpired: (error, _) => failures.add(error.code),
      );
      watch.publication(pageCount: 1, isComplete: false);
      watch.markReadable(watch.startTarget());
      clock.elapse(const Duration(milliseconds: 1500));
      watch.publication(pageCount: 2, isComplete: false);
      clock.elapse(const Duration(milliseconds: 1500));
      watch.publication(pageCount: 2, isComplete: false);
      expect(failures, isEmpty);
      clock.elapse(const Duration(milliseconds: 500));
      expect(failures, ['backgroundPaginationIdle']);
    });
  });

  test('parent retirement clears target/background timers without reporting failure or cancelling the parent itself', () {
    fakeAsync((clock) {
      for (final readable in [false, true]) {
        final parent = NovelReaderPaginationCancellationToken();
        var expired = 0;
        final watch = NovelReaderNativePaginationWatchdog(
          parent: parent,
          elapsed: () => clock.elapsed,
          onExpired: (_, _) {
            expired++;
          },
        );
        final target = watch.startTarget();
        if (readable) watch.markReadable(target);
        parent.cancel();
        expect(watch.isClosed, isTrue);
        expect(watch.isExpired, isFalse);
        watch.close();
        clock.elapse(const Duration(minutes: 1));
        expect(expired, 0);
        expect(clock.nonPeriodicTimerCount, 0);
      }
    });
  });

  test(
    'disabled deadline policy preserves intent state without scheduling timers',
    () {
      fakeAsync((clock) {
        var expired = 0;
        final watch = NovelReaderNativePaginationWatchdog(
          parent: NovelReaderPaginationCancellationToken(),
          elapsed: () => clock.elapsed,
          policy: const NovelReaderPaginationPerformancePolicy(
            enforceBudgets: false,
          ),
          onExpired: (_, _) {
            expired++;
          },
        );
        final target = watch.startTarget();
        expect(watch.isWaitingForTarget, isTrue);
        watch.setDeferring(true);
        clock.elapse(const Duration(hours: 1));
        expect(watch.markReadable(target), isTrue);
        watch.setDeferring(false);
        clock.elapse(const Duration(hours: 1));
        expect(clock.nonPeriodicTimerCount, 0);
        expect(expired, 0);
        watch.close();
      });
    },
  );

  test('invalid or regressing prefixes cannot extend a waiting budget', () {
    fakeAsync((clock) {
      final watch = NovelReaderNativePaginationWatchdog(
        parent: NovelReaderPaginationCancellationToken(),
        elapsed: () => clock.elapsed,
        onExpired: (_, _) {},
      );
      expect(
        () => watch.publication(pageCount: -1, isComplete: false),
        throwsStateError,
      );
      watch.publication(pageCount: 2, isComplete: true);
      expect(
        () => watch.publication(pageCount: 1, isComplete: true),
        throwsStateError,
      );
      expect(
        () => watch.publication(pageCount: 3, isComplete: true),
        throwsStateError,
      );
      expect(
        () => watch.publication(pageCount: 2, isComplete: false),
        throwsStateError,
      );
      watch.close();
      expect(watch.startTarget, throwsStateError);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });

  test('target timeout releases real pending preparation while retaining transferred leases', () async {
    final fixture = NativeReaderTestFixture(
      '<p>ab</p><p>cd</p><p>ef</p><p>gh</p>',
      cacheEntries: 2,
      width: 20,
      height: 10,
    );
    final window = NovelReaderNativeViewWindow(
      session: fixture.session,
      anchors: fixture.anchors,
      parent: fixture.parent,
      centerPageIndex: 0,
      limits: const NovelReaderNativeViewWindowLimits(radius: 0),
      scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
    );
    await window.prepareAvailable();
    final oldLeases = window.viewForPage(0)!.takeLeases();
    window.setCenter(1);
    final foreign = fixture.pinForeign();
    var pendingStopped = false;
    final pending = window.prepareAvailable().then((_) {
      pendingStopped = true;
    });
    for (var step = 0; step < 40; step++) {
      await Future<void>.value();
    }
    expect(fixture.session.reservedViewLeases, 1);
    expect(pendingStopped, isFalse);
    // Fake only deadline time. Stream subscription cancellation completes on
    // the real async lane, which the owning future is awaited on below.
    fakeAsync((clock) {
      final failures = <String?>[];
      final watch = NovelReaderNativePaginationWatchdog(
        parent: fixture.parent,
        elapsed: () => clock.elapsed,
        onExpired: (error, _) {
          failures.add(error.code);
          window.close();
        },
      );
      watch.startTarget();
      clock.flushMicrotasks();
      expect(fixture.session.reservedViewLeases, 1);
      expect(pendingStopped, isFalse);
      clock.elapse(const Duration(seconds: 5));
      clock.flushMicrotasks();
      expect(failures, ['targetPageWaitExceeded']);
      expect(fixture.session.reservedViewLeases, 0);
      expect(oldLeases.single.isActive, isTrue);
      expect(foreign.isActive, isTrue);
      expect(fixture.parent.isCancelled, isFalse);
      expect(fixture.session.isClosed, isFalse);
      expect(clock.nonPeriodicTimerCount, 0);
    });
    await pending;
    expect(pendingStopped, isTrue);
    oldLeases.single.release();
    foreign.release();
  });

  test('real source idle deferral pauses a smaller active-time stall budget through EOF', () {
    fakeAsync((clock) {
      final fixture = NativeReaderTestFixture(
        '<p>ab</p><p>cd</p><p>ef</p><p>gh</p>',
        width: 20,
        height: 10,
        complete: false,
      );
      final demand = NovelReaderPaginationDemand(
        lookAhead: 0,
        idleScheduler: () => Completer<void>().future,
      );
      final failures = <String?>[];
      final watch = NovelReaderNativePaginationWatchdog(
        parent: fixture.parent,
        elapsed: () => clock.elapsed,
        policy: const NovelReaderPaginationPerformancePolicy(
          backgroundIdle: Duration(milliseconds: 10),
        ),
        onExpired: (error, _) => failures.add(error.code),
      );
      final target = watch.startTarget();
      void syncIdle() {
        if (!watch.isClosed) watch.setDeferring(demand.isDeferring);
      }

      demand.addListener(syncIdle);
      final window = NovelReaderNativeViewWindow(
        session: fixture.session,
        anchors: fixture.anchors,
        parent: fixture.parent,
        centerPageIndex: 0,
        limits: const NovelReaderNativeViewWindowLimits(radius: 0),
        scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
      );
      final run = NovelReaderNativeSourceRun(
        session: fixture.session,
        demand: demand,
        parent: fixture.parent,
        scheduler: NovelReaderNativeWorkScheduler(nextFrame: () async {}),
        onPublication: (snapshot, _) async {
          watch.publication(
            pageCount: snapshot.length,
            isComplete: snapshot.isComplete,
          );
          await window.prepareAvailable();
          if (window.viewForPage(0) != null) watch.markReadable(target);
          demand.update(targetPending: false, pageIndex: 0);
        },
      );
      var complete = false;
      run.run().then((_) {
        complete = true;
      });
      clock.flushMicrotasks();
      expect(demand.isDeferring, isTrue);
      clock.elapse(const Duration(milliseconds: 99));
      expect(failures, isEmpty);
      expect(complete, isFalse);
      clock.elapse(const Duration(seconds: 1));
      expect(failures, isEmpty);
      expect(complete, isTrue);
      expect(fixture.session.isComplete, isTrue);
      expect(clock.nonPeriodicTimerCount, 0);
      demand.removeListener(syncIdle);
      watch.close();
      run.close();
      window.close();
      demand.dispose();
      clock.flushMicrotasks();
    });
  });
}
