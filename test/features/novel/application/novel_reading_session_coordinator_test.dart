import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/application/novel_reading_session_coordinator.dart';
import 'package:y300/features/novel/domain/models/novel_reading_session.dart';

void main() {
  group('producer leases', () {
    test('unready and hidden producers cannot create position records', () {
      final coordinator = NovelReadingSessionCoordinator();
      final token = _begin(coordinator);
      expect(coordinator.positionLease(token), isNull);
      _ready(coordinator, token);
      expect(coordinator.positionLease(token), isNull);
      _foreground(coordinator);
      expect(coordinator.positionLease(token)?.isValid, isTrue);
    });

    test(
      'same chapter reopen and forged identity never revive old authority',
      () {
        final coordinator = NovelReadingSessionCoordinator();
        final first = _readable(coordinator);
        final oldLease = coordinator.positionLease(first)!;
        final next = _readable(coordinator);
        final forged = NovelReadingSessionToken(
          novelId: next.novelId,
          episodeId: next.episodeId,
          generation: next.generation,
          entry: next.entry,
        );
        expect(next.generation, greaterThan(first.generation));
        expect(oldLease.isValid, isFalse);
        expect(coordinator.isCurrent(forged), isFalse);
        expect(coordinator.positionLease(next)?.isValid, isTrue);
        coordinator.updateReadiness(
          first,
          bodyReady: false,
          restoreSettled: false,
        );
        expect(coordinator.positionLease(next)?.isValid, isTrue);
      },
    );

    for (final hiddenByApp in <bool>[false, true]) {
      test(
        'visibility revokes queued writes permanently: app=$hiddenByApp',
        () {
          final coordinator = NovelReadingSessionCoordinator();
          final token = _readable(coordinator);
          final queued = coordinator.positionLease(token)!;
          coordinator.updateVisibility(
            frontmost: hiddenByApp,
            resumed: !hiddenByApp,
          );
          expect(queued.isCurrent(), isFalse);
          expect(coordinator.positionLease(token), isNull);
          _foreground(coordinator);
          expect(queued.isCurrent(), isFalse);
          expect(coordinator.positionLease(token)?.isValid, isTrue);
        },
      );
    }

    test(
      'loss of readiness invalidates old leases after readiness returns',
      () {
        final coordinator = NovelReadingSessionCoordinator();
        final token = _readable(coordinator);
        final queued = coordinator.positionLease(token)!;
        coordinator.updateReadiness(
          token,
          bodyReady: false,
          restoreSettled: false,
        );
        expect(queued.isValid, isFalse);
        expect(coordinator.confirmNavigation(token), isFalse);
        _ready(coordinator, token);
        expect(queued.isValid, isFalse);
        expect(coordinator.positionLease(token)?.isValid, isTrue);
      },
    );

    test(
      'new position supersedes queued old position; same position is stable',
      () {
        final coordinator = NovelReadingSessionCoordinator();
        final token = _readable(coordinator);
        final first = coordinator.positionLease(
          token,
          positionIdentity: (1, 42),
        )!;
        final same = coordinator.positionLease(
          token,
          positionIdentity: (1, 42),
        )!;
        expect(first.revision, same.revision);
        expect(first.isValid, isTrue);
        final next = coordinator.positionLease(
          token,
          positionIdentity: (1, 43),
        )!;
        expect(first.isValid, isFalse);
        expect(next.revision, greaterThan(first.revision));
        expect(next.isValid, isTrue);
      },
    );

    test('completion observations do not revoke each new position report', () {
      final coordinator = NovelReadingSessionCoordinator();
      final token = _readable(coordinator);
      final first = coordinator.positionLease(token, positionIdentity: 1)!;
      _report(coordinator, token, (_) {}, atBodyEnd: false);
      expect(first.isValid, isTrue);
      final next = coordinator.positionLease(token, positionIdentity: 2)!;
      _report(coordinator, token, (_) {}, atBodyEnd: false);
      expect(next.isValid, isTrue);
      _report(
        coordinator,
        token,
        (_) {},
        atBodyEnd: false,
        geometryIdentity: (2, 100),
      );
      expect(next.isValid, isTrue);
    });

    test('layout rebinding preserves position and retires old end proof', () {
      fakeAsync((clock) {
        final coordinator = NovelReadingSessionCoordinator();
        final token = _readable(coordinator);
        coordinator.updateGeometry(token, (1, 100));
        final position = coordinator.positionLease(token, positionIdentity: 0)!;
        final completed = <NovelReadingCommitLease>[];
        _report(coordinator, token, completed.add);
        clock.elapse(const Duration(milliseconds: 250));
        final oldCompletion = completed.single;
        expect(oldCompletion.isValid, isTrue);
        coordinator.updateGeometry(token, (2, 100));
        expect(position.isValid, isTrue);
        expect(oldCompletion.isValid, isFalse);
        _report(coordinator, token, completed.add);
        expect(oldCompletion.isValid, isFalse);
        coordinator.dispose();
      });
    });

    test('compatibility protection stays latched until actual navigation', () {
      final coordinator = NovelReadingSessionCoordinator();
      final token = _readable(
        coordinator,
        entry: NovelReadingSessionEntry.resume,
      );
      coordinator.updateReadiness(
        token,
        bodyReady: true,
        restoreSettled: true,
        readOnlyCompatibilityRestore: true,
      );
      expect(coordinator.positionLease(token), isNull);
      _ready(coordinator, token);
      expect(coordinator.positionLease(token), isNull);
      expect(coordinator.confirmNavigation(token), isTrue);
      expect(coordinator.positionLease(token)?.isValid, isTrue);
    });

    for (final entry in <NovelReadingSessionEntry>[
      NovelReadingSessionEntry.readOnlyRestore,
      NovelReadingSessionEntry.bodyEnd,
    ]) {
      test('$entry preserves the saved position without actual navigation', () {
        final coordinator = NovelReadingSessionCoordinator();
        final token = _readable(coordinator, entry: entry);
        expect(coordinator.positionLease(token), isNull);
        expect(coordinator.confirmNavigation(token), isTrue);
        expect(coordinator.positionLease(token)?.isValid, isTrue);
      });
    }
  });

  group('waiting for an existing completion', () {
    test('joins one timer and delivers its lease after the callback', () {
      fakeAsync((clock) {
        final coordinator = NovelReadingSessionCoordinator();
        final token = _readable(coordinator);
        final events = <String>[];
        NovelReadingCommitLease? emitted;
        _report(coordinator, token, (lease) {
          emitted = lease;
          events.add('callback');
        });
        final first = coordinator.waitForPendingCompletion(token);
        final second = coordinator.waitForPendingCompletion(token);
        expect(second, same(first));
        first.then((lease) {
          expect(lease, same(emitted));
          events.add('first');
        });
        second.then((lease) {
          expect(lease, same(emitted));
          events.add('second');
        });
        clock.elapse(const Duration(milliseconds: 249));
        clock.flushMicrotasks();
        expect(events, isEmpty);
        // Joining late never starts a new stability interval.
        expect(coordinator.waitForPendingCompletion(token), same(first));
        clock.elapse(const Duration(milliseconds: 1));
        clock.flushMicrotasks();
        expect(events, ['callback', 'first', 'second']);
        expect(emitted!.isValid, true);
        expect(clock.nonPeriodicTimerCount, 0);
        NovelReadingCommitLease? alreadyEmitted;
        coordinator.waitForPendingCompletion(token).then((lease) {
          alreadyEmitted = lease;
        });
        clock.flushMicrotasks();
        expect(alreadyEmitted, same(emitted));
        coordinator.dispose();
      });
    });

    test('no task or passive restore resolves null without creating work', () {
      fakeAsync((clock) {
        final coordinator = NovelReadingSessionCoordinator();
        final token = _readable(
          coordinator,
          entry: NovelReadingSessionEntry.resume,
        );
        final results = <NovelReadingCommitLease?>[];
        coordinator.waitForPendingCompletion(token).then(results.add);
        _report(coordinator, token, (_) => fail('Passive restore completed'));
        coordinator.waitForPendingCompletion(token).then(results.add);
        clock.flushMicrotasks();
        expect(results, [null, null]);
        expect(clock.nonPeriodicTimerCount, 0);
        coordinator.dispose();
      });
    });

    for (final change in [
      'cancel',
      'bodyReady',
      'restoreSettled',
      'compatibility',
      'covered',
      'background',
      'geometry',
      'navigation',
      'position',
      'observation',
      'retire',
      'dispose',
    ]) {
      test('$change promptly releases all waiters with null', () {
        fakeAsync((clock) {
          final coordinator = NovelReadingSessionCoordinator();
          final token = _readable(coordinator);
          final completed = <NovelReadingCommitLease>[];
          final results = <NovelReadingCommitLease?>[];
          _report(coordinator, token, completed.add);
          coordinator.waitForPendingCompletion(token).then(results.add);
          coordinator.waitForPendingCompletion(token).then(results.add);
          clock.elapse(const Duration(milliseconds: 100));
          switch (change) {
            case 'cancel':
              coordinator.cancelPendingCompletion(token);
            case 'bodyReady':
              coordinator.updateReadiness(
                token,
                bodyReady: false,
                restoreSettled: true,
              );
            case 'restoreSettled':
              coordinator.updateReadiness(
                token,
                bodyReady: true,
                restoreSettled: false,
              );
            case 'compatibility':
              coordinator.updateReadiness(
                token,
                bodyReady: true,
                restoreSettled: true,
                readOnlyCompatibilityRestore: true,
              );
            case 'covered':
              coordinator.updateVisibility(frontmost: false, resumed: true);
            case 'background':
              coordinator.updateVisibility(frontmost: true, resumed: false);
            case 'geometry':
              coordinator.updateGeometry(token, (2, 100));
            case 'navigation':
              coordinator.confirmNavigation(token);
            case 'position':
              coordinator.positionLease(token, positionIdentity: 'new');
            case 'observation':
              _report(coordinator, token, completed.add, idle: false);
            case 'retire':
              coordinator.retire();
            case 'dispose':
              coordinator.dispose();
          }
          clock.flushMicrotasks();
          expect(results, [null, null]);
          expect(completed, isEmpty);
          expect(clock.nonPeriodicTimerCount, 0);
          clock.elapse(const Duration(seconds: 1));
          expect(completed, isEmpty);
          coordinator.dispose();
        });
      });
    }

    test('callback reentry cannot deliver old completion to a new owner', () {
      fakeAsync((clock) {
        final coordinator = NovelReadingSessionCoordinator();
        final old = _readable(coordinator);
        final oldResults = <NovelReadingCommitLease?>[];
        final newResults = <NovelReadingCommitLease?>[];
        NovelReadingSessionToken? next;
        _report(coordinator, old, (_) {
          next = _readable(coordinator);
          _report(coordinator, next!, (_) {});
          coordinator.waitForPendingCompletion(next!).then(newResults.add);
        });
        coordinator.waitForPendingCompletion(old).then(oldResults.add);
        clock.elapse(const Duration(milliseconds: 250));
        clock.flushMicrotasks();
        expect(oldResults, [null]);
        expect(newResults, isEmpty);
        coordinator.waitForPendingCompletion(old).then(oldResults.add);
        clock.flushMicrotasks();
        expect(oldResults, [null, null]);
        clock.elapse(const Duration(milliseconds: 250));
        clock.flushMicrotasks();
        expect(newResults.single!.token, same(next));
        expect(newResults.single!.isValid, true);
        coordinator.dispose();
      });
    });

    test('cancelled emitted completion is not returned to a late waiter', () {
      fakeAsync((clock) {
        final coordinator = NovelReadingSessionCoordinator();
        final token = _readable(coordinator);
        _report(coordinator, token, (_) {});
        clock.elapse(const Duration(milliseconds: 250));
        coordinator.cancelPendingCompletion(token);
        final results = <NovelReadingCommitLease?>[];
        coordinator.waitForPendingCompletion(token).then(results.add);
        clock.flushMicrotasks();
        expect(results, [null]);
        expect(clock.nonPeriodicTimerCount, 0);
        coordinator.dispose();
      });
    });
  });

  group('bounded completion confirmation', () {
    for (final entry in <NovelReadingSessionEntry>[
      NovelReadingSessionEntry.firstStart,
      NovelReadingSessionEntry.explicitStart,
    ]) {
      test('short $entry confirms once after 250 ms of stable final body', () {
        fakeAsync((clock) {
          final coordinator = NovelReadingSessionCoordinator();
          final token = _readable(coordinator, entry: entry);
          final completed = <NovelReadingCommitLease>[];
          _report(coordinator, token, completed.add);
          clock.elapse(const Duration(milliseconds: 249));
          expect(completed, isEmpty);
          // Rebuilding the same visible body does not restart the timer.
          _report(coordinator, token, completed.add);
          clock.elapse(const Duration(milliseconds: 1));
          expect(completed, hasLength(1));
          expect(completed.single.isValid, isTrue);
          _report(coordinator, token, completed.add);
          clock.elapse(const Duration(seconds: 1));
          expect(completed, hasLength(1));
          expect(clock.nonPeriodicTimerCount, 0);
        });
      });
    }

    test('ordinary body must be navigated even when its end appears', () {
      fakeAsync((clock) {
        final coordinator = NovelReadingSessionCoordinator();
        final token = _readable(coordinator);
        final completed = <NovelReadingCommitLease>[];
        _report(coordinator, token, completed.add, wholeBodyVisible: false);
        clock.elapse(const Duration(seconds: 1));
        expect(completed, isEmpty);
        coordinator.confirmNavigation(token);
        _report(coordinator, token, completed.add, wholeBodyVisible: false);
        clock.elapse(const Duration(milliseconds: 250));
        expect(completed, hasLength(1));
      });
    });

    for (final entry in <NovelReadingSessionEntry>[
      NovelReadingSessionEntry.resume,
      NovelReadingSessionEntry.readOnlyRestore,
      NovelReadingSessionEntry.bodyEnd,
    ]) {
      test('short $entry cannot complete through automatic positioning', () {
        fakeAsync((clock) {
          final coordinator = NovelReadingSessionCoordinator();
          final token = _readable(coordinator, entry: entry);
          final completed = <NovelReadingCommitLease>[];
          _report(coordinator, token, completed.add);
          clock.elapse(const Duration(seconds: 1));
          expect(completed, isEmpty);
          coordinator.confirmNavigation(token);
          _report(coordinator, token, completed.add);
          clock.elapse(const Duration(milliseconds: 250));
          expect(completed, hasLength(1));
        });
      });
    }

    test('temporary partial last page is not the final boundary', () {
      fakeAsync((clock) {
        final coordinator = NovelReadingSessionCoordinator();
        final token = _readable(coordinator);
        coordinator.confirmNavigation(token);
        final completed = <NovelReadingCommitLease>[];
        _report(coordinator, token, completed.add, finalBoundaryKnown: false);
        clock.elapse(const Duration(seconds: 1));
        expect(completed, isEmpty);
        _report(coordinator, token, completed.add);
        clock.elapse(const Duration(milliseconds: 250));
        expect(completed, hasLength(1));
      });
    });

    for (final property in <String>[
      'bodyReady',
      'restoreSettled',
      'idle',
      'atBodyEnd',
      'geometryIdentity',
    ]) {
      test('changing $property cancels an in-progress confirmation', () {
        fakeAsync((clock) {
          final coordinator = NovelReadingSessionCoordinator();
          final token = _readable(coordinator);
          final completed = <NovelReadingCommitLease>[];
          _report(coordinator, token, completed.add);
          clock.elapse(const Duration(milliseconds: 200));
          _report(
            coordinator,
            token,
            completed.add,
            bodyReady: property != 'bodyReady',
            restoreSettled: property != 'restoreSettled',
            idle: property != 'idle',
            atBodyEnd: property != 'atBodyEnd',
            geometryIdentity: property == 'geometryIdentity'
                ? (2, 100)
                : (1, 100),
          );
          clock.elapse(const Duration(milliseconds: 50));
          expect(completed, isEmpty);
          // Restoring the facts must start a fresh, nonaccumulated interval.
          _report(coordinator, token, completed.add);
          clock.elapse(const Duration(milliseconds: 249));
          expect(completed, isEmpty);
          clock.elapse(const Duration(milliseconds: 1));
          expect(completed, hasLength(1));
        });
      });
    }

    test(
      'unknown geometry cannot confirm completion from placeholder layout',
      () {
        fakeAsync((clock) {
          final coordinator = NovelReadingSessionCoordinator();
          final token = _readable(coordinator);
          final completed = <NovelReadingCommitLease>[];
          _report(coordinator, token, completed.add, geometryIdentity: null);
          clock.elapse(const Duration(seconds: 1));
          expect(completed, isEmpty);
          expect(clock.nonPeriodicTimerCount, 0);
        });
      },
    );

    test(
      'coverage and app background cancel timers and revoke emitted leases',
      () {
        fakeAsync((clock) {
          final coordinator = NovelReadingSessionCoordinator();
          final token = _readable(coordinator);
          final completed = <NovelReadingCommitLease>[];
          _report(coordinator, token, completed.add);
          clock.elapse(const Duration(milliseconds: 200));
          coordinator.updateVisibility(frontmost: false, resumed: true);
          clock.elapse(const Duration(seconds: 1));
          expect(completed, isEmpty);
          _foreground(coordinator);
          _report(coordinator, token, completed.add);
          clock.elapse(const Duration(milliseconds: 250));
          expect(completed, hasLength(1));
          coordinator.updateVisibility(frontmost: true, resumed: false);
          expect(completed.single.isCurrent(), isFalse);
          _foreground(coordinator);
          expect(completed.single.isCurrent(), isFalse);
        });
      },
    );

    test('late completion write is rejected after leaving the final body', () {
      fakeAsync((clock) {
        final coordinator = NovelReadingSessionCoordinator();
        final token = _readable(coordinator);
        final completed = <NovelReadingCommitLease>[];
        _report(coordinator, token, completed.add);
        clock.elapse(const Duration(milliseconds: 250));
        expect(completed.single.isCurrent(), isTrue);
        _report(coordinator, token, completed.add, atBodyEnd: false);
        expect(completed.single.isCurrent(), isFalse);
      });
    });

    test('retired timer cannot complete a reopened or reset chapter', () {
      fakeAsync((clock) {
        final coordinator = NovelReadingSessionCoordinator();
        final old = _readable(coordinator);
        final completed = <NovelReadingCommitLease>[];
        _report(coordinator, old, completed.add);
        clock.elapse(const Duration(milliseconds: 200));
        final reset = _readable(
          coordinator,
          entry: NovelReadingSessionEntry.resume,
        );
        _report(coordinator, old, completed.add);
        _report(coordinator, reset, completed.add);
        clock.elapse(const Duration(seconds: 1));
        expect(completed, isEmpty);
        coordinator.confirmNavigation(reset);
        _report(coordinator, reset, completed.add);
        clock.elapse(const Duration(milliseconds: 250));
        expect(completed.single.token, same(reset));
      });
    });

    test(
      'failed completion waits for a fresh observation rather than looping',
      () {
        fakeAsync((clock) {
          final coordinator = NovelReadingSessionCoordinator();
          final token = _readable(coordinator);
          final completed = <NovelReadingCommitLease>[];
          _report(coordinator, token, completed.add);
          clock.elapse(const Duration(milliseconds: 250));
          final rejected = completed.single;
          coordinator.rejectCompletion(rejected);
          expect(rejected.isValid, isFalse);
          clock.elapse(const Duration(seconds: 1));
          expect(completed, hasLength(1));
          _report(coordinator, token, completed.add);
          clock.elapse(const Duration(milliseconds: 250));
          expect(completed, hasLength(2));
          final current = completed.last;
          coordinator.rejectCompletion(rejected);
          expect(current.isValid, isTrue);
          _report(coordinator, token, completed.add);
          clock.elapse(const Duration(seconds: 1));
          expect(completed, hasLength(2));
        });
      },
    );

    test('old completion rejection cannot unlock a new chapter', () {
      fakeAsync((clock) {
        final coordinator = NovelReadingSessionCoordinator();
        final old = _readable(coordinator);
        final completed = <NovelReadingCommitLease>[];
        _report(coordinator, old, completed.add);
        clock.elapse(const Duration(milliseconds: 250));
        final rejected = completed.single;
        final current = _readable(coordinator);
        _report(coordinator, current, completed.add);
        clock.elapse(const Duration(milliseconds: 250));
        coordinator.rejectCompletion(rejected);
        _report(coordinator, current, completed.add);
        clock.elapse(const Duration(seconds: 1));
        expect(completed, hasLength(2));
        expect(completed.last.token, same(current));
      });
    });

    test('disposing releases the timer and all producer authority', () {
      fakeAsync((clock) {
        final coordinator = NovelReadingSessionCoordinator();
        final token = _readable(coordinator);
        final lease = coordinator.positionLease(token)!;
        final completed = <NovelReadingCommitLease>[];
        _report(coordinator, token, completed.add);
        coordinator.dispose();
        clock.elapse(const Duration(seconds: 1));
        expect(completed, isEmpty);
        expect(clock.nonPeriodicTimerCount, 0);
        expect(lease.isValid, isFalse);
        expect(coordinator.confirmNavigation(token), isFalse);
      });
    });
  });
}

NovelReadingSessionToken _begin(
  NovelReadingSessionCoordinator coordinator, {
  NovelReadingSessionEntry entry = NovelReadingSessionEntry.firstStart,
}) => coordinator.begin(novelId: 'work', episodeId: 'chapter', entry: entry);

void _foreground(NovelReadingSessionCoordinator coordinator) =>
    coordinator.updateVisibility(frontmost: true, resumed: true);

void _ready(
  NovelReadingSessionCoordinator coordinator,
  NovelReadingSessionToken token,
) => coordinator.updateReadiness(token, bodyReady: true, restoreSettled: true);

NovelReadingSessionToken _readable(
  NovelReadingSessionCoordinator coordinator, {
  NovelReadingSessionEntry entry = NovelReadingSessionEntry.firstStart,
}) {
  final token = _begin(coordinator, entry: entry);
  _foreground(coordinator);
  _ready(coordinator, token);
  return token;
}

void _report(
  NovelReadingSessionCoordinator coordinator,
  NovelReadingSessionToken token,
  void Function(NovelReadingCommitLease) onComplete, {
  bool bodyReady = true,
  bool finalBoundaryKnown = true,
  bool atBodyEnd = true,
  bool wholeBodyVisible = true,
  bool restoreSettled = true,
  bool idle = true,
  Object? geometryIdentity = const (1, 100),
}) => coordinator.reportCompletion(
  token,
  bodyReady: bodyReady,
  finalBoundaryKnown: finalBoundaryKnown,
  atBodyEnd: atBodyEnd,
  wholeBodyVisible: wholeBodyVisible,
  restoreSettled: restoreSettled,
  idle: idle,
  geometryIdentity: geometryIdentity,
  onComplete: onComplete,
);
