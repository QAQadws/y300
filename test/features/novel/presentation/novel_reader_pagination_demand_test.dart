import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_cancellation.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_demand.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_measure_adapter.dart';

void main() {
  test(
    'target, complete and adjacent-page demand proceed without idle waits',
    () {
      fakeAsync((clock) {
        final idle = _ControlledIdle();
        final demand = NovelReaderPaginationDemand(
          idleScheduler: idle.schedule,
        );
        final lease = demand.start(NovelReaderPaginationCancellationToken());
        final target = _observe(lease.afterPublication(20));
        demand.update(
          targetPending: false,
          pageIndex: 0,
          requireComplete: true,
        );
        final completeDemand = _observe(lease.afterPublication(20));
        demand.update(targetPending: false, pageIndex: 0);
        final adjacent = _observe(lease.afterPublication(2));
        final finishedPlan = _observe(
          lease.afterPublication(20, isComplete: true),
        );
        clock.flushMicrotasks();

        expect([
          target.done,
          completeDemand.done,
          adjacent.done,
          finishedPlan.done,
        ], everyElement(isTrue));
        expect(idle.gates, isEmpty);
        expect(demand.isDeferring, isFalse);
        demand.dispose();
      });
    },
  );

  test(
    'idle permission advances one publication and later work yields again',
    () {
      fakeAsync((clock) {
        final idle = _ControlledIdle();
        final demand = NovelReaderPaginationDemand(idleScheduler: idle.schedule)
          ..update(targetPending: false, pageIndex: 0);
        final changes = <bool>[];
        demand.addListener(() => changes.add(demand.isDeferring));
        final lease = demand.start(NovelReaderPaginationCancellationToken());
        final first = _observe(lease.afterPublication(3));
        clock.flushMicrotasks();
        expect(first.done, isFalse);
        expect(demand.isDeferring, isTrue);

        idle.gates.first.complete();
        clock.flushMicrotasks();
        expect(first.done, isTrue);
        expect(clock.nonPeriodicTimerCount, 0);
        final next = _observe(lease.afterPublication(5));
        clock.flushMicrotasks();
        expect(next.done, isFalse);
        expect(idle.gates, hasLength(2));
        idle.gates.last.complete();
        clock.flushMicrotasks();
        expect(next.done, isTrue);
        expect(changes, [true, false, true, false]);
        demand.dispose();
      });
    },
  );

  test(
    'starved idle work resumes at 100ms without resetting on quiet updates',
    () {
      fakeAsync((clock) {
        final idle = _ControlledIdle();
        final demand = NovelReaderPaginationDemand(idleScheduler: idle.schedule)
          ..update(targetPending: false, pageIndex: 0);
        final lease = demand.start(NovelReaderPaginationCancellationToken());
        final pending = _observe(lease.afterPublication(20));
        clock.elapse(const Duration(milliseconds: 99));
        demand.update(targetPending: false, pageIndex: 0);
        clock.flushMicrotasks();
        expect(pending.done, isFalse);
        clock.elapse(const Duration(milliseconds: 1));
        expect(pending.done, isTrue);
        expect(demand.isDeferring, isFalse);
        expect(clock.nonPeriodicTimerCount, 0);
        idle.gates.single.complete();
        clock.flushMicrotasks();
        expect(pending.error, isNull);
        demand.dispose();
      });
    },
  );

  for (final promotion in ['target', 'page', 'complete']) {
    test('$promotion promotion releases the same live lease immediately', () {
      fakeAsync((clock) {
        final idle = _ControlledIdle();
        final demand = NovelReaderPaginationDemand(idleScheduler: idle.schedule)
          ..update(targetPending: false, pageIndex: 0);
        final lease = demand.start(NovelReaderPaginationCancellationToken());
        final pending = _observe(lease.afterPublication(10));
        demand.update(
          targetPending: promotion == 'target',
          pageIndex: promotion == 'page' ? 8 : 0,
          requireComplete: promotion == 'complete',
        );
        clock.flushMicrotasks();
        expect(pending.done, isTrue);
        expect(demand.isDeferring, isFalse);
        expect(clock.nonPeriodicTimerCount, 0);

        demand.update(targetPending: false, pageIndex: 0);
        final resumed = _observe(lease.afterPublication(11));
        idle.gates.first.complete();
        clock.flushMicrotasks();
        expect(resumed.done, isFalse);
        idle.gates.last.complete();
        clock.flushMicrotasks();
        expect(resumed.done, isTrue);
        demand.dispose();
      });
    });
  }

  test('cancellation wakes the lease and observes a late idle error', () {
    fakeAsync((clock) {
      final idle = _ControlledIdle();
      final demand = NovelReaderPaginationDemand(idleScheduler: idle.schedule)
        ..update(targetPending: false, pageIndex: 0);
      final token = NovelReaderPaginationCancellationToken();
      final pending = _observe(demand.start(token).afterPublication(10));
      token.cancel();
      expect(demand.isDeferring, isFalse);
      clock.flushMicrotasks();
      expect(pending.error, _cancelled);
      expect(clock.nonPeriodicTimerCount, 0);
      idle.gates.single.completeError(StateError('late idle task'));
      clock.flushMicrotasks();
      expect(pending.error, _cancelled);
      demand.dispose();
    });
  });

  test('old permissions and close cannot release a replacement lease', () {
    fakeAsync((clock) {
      final idle = _ControlledIdle();
      final demand = NovelReaderPaginationDemand(idleScheduler: idle.schedule)
        ..update(targetPending: false, pageIndex: 0);
      final oldToken = NovelReaderPaginationCancellationToken();
      final oldLease = demand.start(oldToken);
      final old = _observe(oldLease.afterPublication(10));
      oldToken.cancel();
      final currentLease = demand.start(
        NovelReaderPaginationCancellationToken(),
      );
      final current = _observe(currentLease.afterPublication(10));
      idle.gates.first.complete();
      oldLease.close();
      clock.flushMicrotasks();
      expect(old.error, _cancelled);
      expect(current.done, isFalse);
      expect(demand.isDeferring, isTrue);
      expect(clock.nonPeriodicTimerCount, 1);
      idle.gates.last.complete();
      clock.flushMicrotasks();
      expect(current.done, isTrue);
      demand.dispose();
    });
  });

  test(
    'close releases only scheduling resources and dispose ignores late idle',
    () {
      fakeAsync((clock) {
        final idle = _ControlledIdle();
        final demand = NovelReaderPaginationDemand(
          idleBudget: const Duration(milliseconds: 20),
          idleScheduler: idle.schedule,
        )..update(targetPending: false, pageIndex: 0);
        final token = NovelReaderPaginationCancellationToken();
        final lease = demand.start(token);
        final pending = _observe(lease.afterPublication(10));
        lease.close();
        clock.flushMicrotasks();
        expect(pending.done, isTrue);
        expect(token.isCancelled, isFalse);
        expect(clock.nonPeriodicTimerCount, 0);
        demand.dispose();
        idle.gates.single.complete();
        clock.flushMicrotasks();
        demand.update(targetPending: true, pageIndex: 0);
        expect(demand.isDeferring, isFalse);
        expect(() => demand.start(token), throwsStateError);
      });
    },
  );

  test('synchronous demand promotion during notification leaves no timer', () {
    fakeAsync((clock) {
      final idle = _ControlledIdle();
      final demand = NovelReaderPaginationDemand(idleScheduler: idle.schedule)
        ..update(targetPending: false, pageIndex: 0);
      demand.addListener(() {
        if (demand.isDeferring) {
          demand.update(targetPending: true, pageIndex: 0);
        }
      });
      final pending = _observe(
        demand
            .start(NovelReaderPaginationCancellationToken())
            .afterPublication(10),
      );
      clock.flushMicrotasks();
      expect(pending.done, isTrue);
      expect(idle.gates, isEmpty);
      expect(clock.nonPeriodicTimerCount, 0);
      demand.dispose();
    });
  });
}

final _cancelled = isA<NovelReaderPaginationException>().having(
  (error) => error.code,
  'code',
  'paginationCancelled',
);

final class _ControlledIdle {
  final gates = <Completer<void>>[];

  Future<void> schedule() {
    final gate = Completer<void>();
    gates.add(gate);
    return gate.future;
  }
}

_WaitOutcome _observe(Future<void> future) {
  final outcome = _WaitOutcome();
  unawaited(
    future.then<void>(
      (_) => outcome.done = true,
      onError: (Object error, StackTrace stack) {
        outcome.error = error;
        outcome.done = true;
      },
    ),
  );
  return outcome;
}

final class _WaitOutcome {
  bool done = false;
  Object? error;
}
