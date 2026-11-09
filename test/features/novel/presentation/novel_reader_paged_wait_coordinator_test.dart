import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_paged_wait_coordinator.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_pagination_performance_policy.dart';

const _budget = Duration(milliseconds: 50);
const _policy = NovelReaderPaginationPerformancePolicy(
  targetPageWait: _budget,
  backgroundIdle: _budget,
);

void main() {
  test('target budget includes preparation and is not renewed by partial publications', () {
    _run((clock, f) {
      f.wait.startTargetWait();
      clock.elapse(const Duration(milliseconds: 30));
      f.wait.startPlan();
      f.wait.recordPublication(1, isComplete: false);
      f.wait.acceptProgress(1, isComplete: false);
      f.wait.resolveRestoreTarget(
        pending: true,
        resolvedPage: null,
        pageCount: 1,
        isComplete: false,
      );
      clock.elapse(const Duration(milliseconds: 21));
      expect(f.failures, [NovelReaderPagedWaitFailure.targetPage]);
      expect(f.wait.hasReadablePage, isFalse);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });

  test(
    'background idle renews only for a newly sealed page in this attempt',
    () {
      _run((clock, f) {
        f.readable(pageCount: 1);
        clock.elapse(const Duration(milliseconds: 30));
        f.wait.recordPublication(2, isComplete: false);
        f.wait.acceptProgress(2, isComplete: false);
        clock.elapse(const Duration(milliseconds: 30));
        f.wait.recordPublication(2, isComplete: false);
        expect(f.failures, isEmpty);
        clock.elapse(const Duration(milliseconds: 21));
        expect(f.failures, [NovelReaderPagedWaitFailure.backgroundIdle]);
        expect(f.wait.hasReadablePage, isTrue);
      });
    },
  );

  test('deliberate idle deferral suspends the background budget, then starts a fresh budget', () {
    _run((clock, f) {
      f.readable();
      clock.elapse(const Duration(milliseconds: 30));
      f.wait.setDeferring(true);
      clock.elapse(const Duration(seconds: 2));
      expect(f.failures, isEmpty);
      f.wait.setDeferring(false);
      clock.elapse(const Duration(milliseconds: 49));
      expect(f.failures, isEmpty);
      clock.elapse(const Duration(milliseconds: 1));
      expect(f.failures, [NovelReaderPagedWaitFailure.backgroundIdle]);
    });
  });

  test('deferral cannot hide an unresolved target deadline', () {
    _run((clock, f) {
      f.wait.startTargetWait();
      f.wait.setDeferring(true);
      clock.elapse(_budget);
      expect(f.failures, [NovelReaderPagedWaitFailure.targetPage]);
    });
  });

  test('missing page has one explicit intent and can only be consumed after coverage', () {
    _run((clock, f) {
      f.readable();
      f.wait.setVisiblePage(1);
      expect(f.wait.requestForwardPage(2), isTrue);
      final request = f.wait.pendingForwardRequest!;
      expect(f.wait.requestForwardPage(2), isFalse);
      expect(f.wait.requestForwardPage(3), isFalse);
      expect(f.wait.targetPending, isTrue);
      expect(f.wait.consumeForwardPage(request, visiblePageIndex: 1), isFalse);
      f.wait.acceptProgress(3, isComplete: false);
      expect(f.wait.consumeForwardPage(request, visiblePageIndex: 1), isTrue);
      expect(f.wait.consumeForwardPage(request), isFalse);
      expect(f.wait.pendingForwardRequest, isNull);
      // Claiming a request leaves the visible index untouched until real arrival.
      expect(f.wait.demandPageIndex, 1);
      expect(f.wait.targetReady, isTrue);
      expect(f.failures, isEmpty);
    });
  });

  test('cancel and repeat at the same index cannot revive the old intent', () {
    _run((clock, f) {
      f.readable();
      f.wait.requestForwardPage(2);
      final old = f.wait.pendingForwardRequest!;
      f.wait.cancelForwardPage(visiblePageIndex: 1);
      f.wait.requestForwardPage(2);
      final current = f.wait.pendingForwardRequest!;
      expect(current, isNot(same(old)));
      f.wait.acceptProgress(3, isComplete: false);
      expect(f.wait.consumeForwardPage(old), isFalse);
      expect(f.wait.pendingForwardRequest, same(current));
      expect(f.wait.consumeForwardPage(current, visiblePageIndex: 1), isTrue);
    });
  });

  test('complete coverage without the requested page retires the intent', () {
    _run((clock, f) {
      f.readable();
      f.wait.requestForwardPage(2);
      final old = f.wait.pendingForwardRequest!;
      f.wait.acceptProgress(2, isComplete: true);
      f.wait.resolveRestoreTarget(
        pending: false,
        resolvedPage: 0,
        pageCount: 2,
        isComplete: true,
      );
      expect(f.wait.pendingForwardRequest, isNull);
      expect(f.wait.targetPending, isFalse);
      expect(f.wait.consumeForwardPage(old), isFalse);
      expect(f.wait.requestForwardPage(2), isFalse);
      expect(clock.nonPeriodicTimerCount, 0);
      expect(f.failures, isEmpty);
    });
  });

  test(
    'new navigation gets its own target budget and preserves readable content',
    () {
      _run((clock, f) {
        f.readable();
        f.wait.requestForwardPage(2);
        final old = f.wait.pendingForwardRequest!;
        clock.elapse(const Duration(milliseconds: 30));
        f.wait.beginNavigation();
        f.wait.startTargetWait();
        clock.elapse(const Duration(milliseconds: 30));
        expect(f.failures, isEmpty);
        expect(f.wait.hasReadablePage, isTrue);
        expect(f.wait.restoreTargetPending, isTrue);
        expect(f.wait.consumeForwardPage(old), isFalse);
        clock.elapse(const Duration(milliseconds: 21));
        expect(f.failures, [NovelReaderPagedWaitFailure.targetPage]);
      });
    },
  );

  test('restore demand moves only for a newly resolved restore or actual visibility', () {
    _run((clock, f) {
      f.wait.resolveRestoreTarget(
        pending: false,
        resolvedPage: 2,
        pageCount: 4,
        isComplete: false,
      );
      f.wait.markTargetReadable();
      expect(f.wait.demandPageIndex, 2);
      f.wait.setVisiblePage(3);
      f.wait.resolveRestoreTarget(
        pending: false,
        resolvedPage: 2,
        pageCount: 5,
        isComplete: false,
      );
      expect(f.wait.demandPageIndex, 3);
      f.wait.beginNavigation();
      f.wait.resolveRestoreTarget(
        pending: false,
        resolvedPage: 1,
        pageCount: 5,
        isComplete: false,
      );
      expect(f.wait.demandPageIndex, 1);
    });
  });

  test('retry retains readable state but releases old intent and waits for a live plan', () {
    _run((clock, f) {
      f.readable(pageCount: 3);
      f.wait.setVisiblePage(1);
      f.wait.requestForwardPage(3);
      final old = f.wait.pendingForwardRequest!;
      f.wait.pause();
      f.wait.resetRequest(retainReadable: true);
      expect(f.wait.hasReadablePage, isTrue);
      expect(f.wait.demandPageIndex, 1);
      expect(f.wait.pendingForwardRequest, isNull);
      f.wait.ensureBackgroundWait();
      expect(clock.nonPeriodicTimerCount, 0);
      expect(f.wait.consumeForwardPage(old), isFalse);
    });
  });

  test(
    'replay can renew idle while still catching up with the retained prefix',
    () {
      _run((clock, f) {
        f.readable(pageCount: 3);
        f.wait.pause();
        f.wait.resetRequest(retainReadable: true);
        f.wait.startPlan();
        f.wait.ensureBackgroundWait();
        for (var pageCount = 1; pageCount <= 3; pageCount++) {
          clock.elapse(const Duration(milliseconds: 30));
          f.wait.recordPublication(pageCount, isComplete: false);
          expect(f.failures, isEmpty);
        }
        f.wait.acceptProgress(4, isComplete: true);
        clock.elapse(const Duration(seconds: 1));
        expect(f.failures, isEmpty);
        expect(clock.nonPeriodicTimerCount, 0);
      });
    },
  );

  for (final action in ['pause', 'reset', 'complete', 'close']) {
    test('$action releases both deadline kinds and retires old requests', () {
      _run((clock, f) {
        f.readable();
        f.wait.requestForwardPage(2);
        final old = f.wait.pendingForwardRequest!;
        switch (action) {
          case 'pause':
            f.wait.pause();
          case 'reset':
            f.wait.resetRequest(retainReadable: false);
          case 'complete':
            f.wait.acceptProgress(3, isComplete: true);
            f.wait.consumeForwardPage(old);
          case 'close':
            f.wait.close();
        }
        clock.elapse(const Duration(seconds: 1));
        expect(f.failures, isEmpty);
        expect(clock.nonPeriodicTimerCount, 0);
        expect(f.wait.consumeForwardPage(old), isFalse);
      });
    });
  }

  test('disabled budgets preserve waiting state without scheduling timers', () {
    _run((clock, f) {
      f.wait.updatePolicy(
        const NovelReaderPaginationPerformancePolicy(enforceBudgets: false),
      );
      f.wait.startTargetWait();
      f.readable();
      expect(f.wait.requestForwardPage(2), isTrue);
      clock.elapse(const Duration(hours: 1));
      expect(f.wait.targetPending, isTrue);
      expect(f.failures, isEmpty);
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });

  test(
    'policy replacement cancels the previous deadline before arming a new one',
    () {
      _run((clock, f) {
        f.wait.startTargetWait();
        clock.elapse(const Duration(milliseconds: 30));
        f.wait.updatePolicy(
          const NovelReaderPaginationPerformancePolicy(
            targetPageWait: Duration(milliseconds: 100),
          ),
        );
        f.wait.startTargetWait();
        clock.elapse(const Duration(milliseconds: 99));
        expect(f.failures, isEmpty);
        clock.elapse(const Duration(milliseconds: 1));
        expect(f.failures, [NovelReaderPagedWaitFailure.targetPage]);
      });
    },
  );

  test(
    'a timeout callback can retry without old cleanup erasing the new deadline',
    () {
      fakeAsync((clock) {
        final failures = <NovelReaderPagedWaitFailure>[];
        late final NovelReaderPagedWaitCoordinator wait;
        wait = NovelReaderPagedWaitCoordinator(
          policy: _policy,
          onTimeout: (failure) {
            failures.add(failure);
            wait.resetRequest(retainReadable: false);
            wait.startTargetWait();
          },
        );
        wait.startTargetWait();
        clock.elapse(_budget);
        expect(failures, hasLength(1));
        clock.elapse(const Duration(milliseconds: 49));
        expect(failures, hasLength(1));
        clock.elapse(const Duration(milliseconds: 1));
        expect(failures, hasLength(2));
        wait.close();
        expect(clock.nonPeriodicTimerCount, 0);
      });
    },
  );

  test(
    'closed ownership is permanent even if later work tries to reactivate it',
    () {
      _run((clock, f) {
        f.wait.close();
        f.wait.close();
        f.wait.resetRequest(retainReadable: false);
        f.wait.beginNavigation();
        f.wait.startPlan();
        f.wait.markTargetReadable();
        f.wait.startTargetWait();
        f.wait.ensureBackgroundWait();
        expect(f.wait.requestForwardPage(0), isFalse);
        clock.elapse(const Duration(seconds: 1));
        expect(f.failures, isEmpty);
        expect(clock.nonPeriodicTimerCount, 0);
      });
    },
  );
}

void _run(void Function(FakeAsync, _Fixture) body) => fakeAsync((clock) {
  final fixture = _Fixture();
  try {
    body(clock, fixture);
  } finally {
    fixture.wait.close();
  }
  expect(clock.nonPeriodicTimerCount, 0);
});

final class _Fixture {
  _Fixture() {
    wait = NovelReaderPagedWaitCoordinator(
      policy: _policy,
      onTimeout: failures.add,
    );
  }
  late final NovelReaderPagedWaitCoordinator wait;
  final failures = <NovelReaderPagedWaitFailure>[];

  void readable({int pageCount = 2}) {
    wait.startPlan();
    wait.recordPublication(pageCount, isComplete: false);
    wait.acceptProgress(pageCount, isComplete: false);
    wait.resolveRestoreTarget(
      pending: false,
      resolvedPage: 0,
      pageCount: pageCount,
      isComplete: false,
    );
    wait.markTargetReadable();
    wait.ensureBackgroundWait();
  }
}
