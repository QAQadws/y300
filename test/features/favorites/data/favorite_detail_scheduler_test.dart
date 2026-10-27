import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/services/favorite_detail_scheduler.dart';
import 'package:y300/features/favorites/data/services/favorite_execution_queue.dart';
import 'package:y300/features/favorites/domain/services/favorite_parse_service.dart';
import 'package:y300/features/favorites/domain/services/favorite_sync_request_governor.dart';

FavoriteDetailWork work(
  String tid, {
  bool foreground = false,
  bool forceSearch = false,
  Object owner = '123',
}) => FavoriteDetailWork(
  target: FavoriteParseTarget(tid: tid),
  owner: owner,
  context: const FavoriteSyncExecutionContext.automaticResume(),
  isCurrent: () async => true,
  foreground: foreground,
  forceRead: foreground,
  forceSearch: forceSearch,
);

void main() {
  test(
    'a waiting automatic target is promoted without duplicating its execution',
    () async {
      final queue = FavoriteExecutionQueue();
      final gate = Completer<void>(), started = Completer<void>();
      final blocker = queue.run(() async {
        started.complete();
        await gate.future;
      });
      await started.future;
      final order = <String>[];
      final scheduler = FavoriteDetailScheduler(queue, (
        task,
        readStarted,
      ) async {
        readStarted();
        order.add(task.target.tid);
        return true;
      });
      final a = scheduler.request(work('a'));
      final b = scheduler.request(work('b'));
      final promoted = scheduler.request(work('b', foreground: true));
      gate.complete();
      await blocker;
      await Future.wait([a, b, promoted]);
      expect(order, ['b', 'a']);
    },
  );

  test(
    'foreground FIFO yields after three units when automatic work is waiting',
    () async {
      final queue = FavoriteExecutionQueue();
      final gate = Completer<void>(), started = Completer<void>();
      final blocker = queue.run(() async {
        started.complete();
        await gate.future;
      });
      await started.future;
      final order = <String>[];
      final futures = <Future<void>>[];
      for (final id in ['f1', 'f2', 'f3', 'f4']) {
        futures.add(
          queue.run(() async {
            order.add(id);
          }, priority: FavoriteWorkPriority.foreground),
        );
      }
      futures.add(
        queue.run(() async {
          order.add('automatic');
        }),
      );
      gate.complete();
      await blocker;
      await Future.wait(futures);
      expect(order, ['f1', 'f2', 'f3', 'automatic', 'f4']);
    },
  );

  test('stronger in-flight comic requirements create only one non-concurrent successor', () async {
    final queue = FavoriteExecutionQueue();
    final gate = Completer<void>(), started = Completer<void>();
    final options = <bool>[];
    var active = 0, maxActive = 0;
    final scheduler = FavoriteDetailScheduler(queue, (task, readStarted) async {
      active++;
      if (active > maxActive) maxActive = active;
      options.add(task.forceSearch);
      readStarted();
      if (options.length == 1) {
        started.complete();
        await gate.future;
      }
      active--;
      return true;
    });
    final initial = scheduler.request(work('200'));
    await started.future;
    final joins = [
      for (var i = 0; i < 8; i++)
        scheduler.request(work('200', foreground: true, forceSearch: true)),
    ];
    gate.complete();
    await Future.wait([initial, ...joins]);
    expect(options, [false, true]);
    expect(maxActive, 1);
  });

  test(
    'an actual in-flight read covers a foreground reread with the same options',
    () async {
      final queue = FavoriteExecutionQueue();
      final gate = Completer<void>(), started = Completer<void>();
      var calls = 0;
      final scheduler = FavoriteDetailScheduler(queue, (
        task,
        readStarted,
      ) async {
        calls++;
        readStarted();
        started.complete();
        await gate.future;
        return true;
      });
      final automatic = scheduler.request(work('200', forceSearch: true));
      await started.future;
      final foreground = scheduler.request(
        work('200', foreground: true, forceSearch: true),
      );
      gate.complete();
      await Future.wait([automatic, foreground]);
      expect(calls, 1);
    },
  );

  test('a requirement arriving during coverage verification remains in the successor', () async {
    final queue = FavoriteExecutionQueue();
    final started = Completer<void>(), finishRead = Completer<void>();
    final checking = Completer<void>(), finishCheck = Completer<void>();
    final executed = <FavoriteDetailWork>[];
    final scheduler = FavoriteDetailScheduler(
      queue,
      (task, readStarted) async {
        executed.add(task);
        readStarted();
        if (executed.length == 1) {
          started.complete();
          await finishRead.future;
        }
        return true;
      },
      resultCovers: (current, requested, readStarted) async {
        checking.complete();
        await finishCheck.future;
        return true;
      },
    );
    final automatic = scheduler.request(work('200'));
    await started.future;
    final manual = scheduler.request(
      work('200', foreground: true, forceSearch: true),
    );
    finishRead.complete();
    await checking.future;
    final refavorite = scheduler.request(
      FavoriteDetailWork(
        target: const FavoriteParseTarget(
          tid: '200',
          confirmed: true,
          remoteFavoriteId: 'new-favorite',
        ),
        owner: '123',
        context: const FavoriteSyncExecutionContext.automaticResume(),
        isCurrent: () async => true,
        foreground: true,
        forceRead: true,
        forceSearch: true,
        membershipRevision: 2,
      ),
    );
    finishCheck.complete();
    await Future.wait([automatic, manual, refavorite]);
    expect(executed, hasLength(2));
    expect(executed.last.target.remoteFavoriteId, 'new-favorite');
    expect(executed.last.membershipRevision, 2);
  });

  test(
    'a cache-only automatic result cannot swallow an explicit reread',
    () async {
      final queue = FavoriteExecutionQueue();
      final gate = Completer<void>(), started = Completer<void>();
      var calls = 0;
      final scheduler = FavoriteDetailScheduler(queue, (
        task,
        readStarted,
      ) async {
        calls++;
        if (calls == 1) {
          started.complete();
          await gate.future;
        } else {
          readStarted();
        }
        return true;
      });
      final automatic = scheduler.request(work('200', forceSearch: true));
      await started.future;
      final foreground = scheduler.request(
        work('200', foreground: true, forceSearch: true),
      );
      gate.complete();
      await Future.wait([automatic, foreground]);
      expect(calls, 2);
    },
  );

  test('a retired requester does not invalidate another subscriber to the running task', () async {
    final queue = FavoriteExecutionQueue();
    final started = Completer<void>(), gate = Completer<void>();
    var valid = true;
    final scheduler = FavoriteDetailScheduler(queue, (task, readStarted) async {
      readStarted();
      started.complete();
      await gate.future;
      return task.isCurrent();
    });
    final first = scheduler.request(
      FavoriteDetailWork(
        target: const FavoriteParseTarget(tid: '200'),
        owner: '123',
        context: const FavoriteSyncExecutionContext.automaticResume(),
        isCurrent: () async => valid,
        forceRead: true,
      ),
    );
    await started.future;
    valid = false;
    final joined = scheduler.request(work('200'));
    gate.complete();
    expect(await first, isTrue);
    expect(await joined, isTrue);
  });

  test('a failed task does not block another owner or a later task', () async {
    final queue = FavoriteExecutionQueue();
    final owners = <Object?>[];
    final scheduler = FavoriteDetailScheduler(queue, (task, readStarted) async {
      owners.add(task.owner);
      if (task.owner == 'old') throw StateError('retired');
      return true;
    });
    final failed = expectLater(
      scheduler.request(work('200', owner: 'old')),
      throwsStateError,
    );
    final next = scheduler.request(work('200', owner: 'new'));
    await failed;
    expect(await next, isTrue);
    expect(owners, ['old', 'new']);
  });
}
