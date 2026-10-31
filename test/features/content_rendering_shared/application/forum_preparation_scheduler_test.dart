import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

Future<void> drain() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'scope retirement preserves another consumer and the real running slot',
    () async {
      final scheduler = ForumPreparationScheduler(
        maxQueued: 1,
        maxQueuedCodeUnits: 8,
      );
      addTearDown(scheduler.dispose);
      final a = scheduler.createScope();
      final b = scheduler.createScope();
      final runningResult = Completer<String>();
      final running = a.tryAcquire(
        identity: 'running',
        codeUnits: 100,
        work: () => runningResult.future,
      )!;
      var starts = 0;
      Future<int> work() async {
        starts++;
        return 42;
      }

      final first = a.tryAcquire(identity: 'shared', codeUnits: 6, work: work)!;
      final second = b.tryAcquire(
        identity: 'shared',
        codeUnits: 6,
        work: work,
      )!;
      expect(first.future, same(second.future));
      expect(scheduler.queuedCodeUnits, 6);
      a.close();
      first.release();
      running.release();
      expect(scheduler.activeCount, 1);
      expect(scheduler.queuedCount, 1);
      expect(starts, 0);
      expect(
        b.tryAcquire(identity: 'excess', codeUnits: 1, work: work),
        isNull,
      );
      runningResult.complete('done');
      expect(await running.future, 'done');
      expect(await second.future, 42);
      await drain();
      expect(starts, 1);
      expect(scheduler.activeCount, 0);
      second.release();
      b.close();
      expect(
        () => a.tryAcquire(identity: 'new', codeUnits: 1, work: work),
        throwsStateError,
      );
    },
  );

  test(
    'closing the last queued owner returns null and frees UTF-16 admission',
    () async {
      final scheduler = ForumPreparationScheduler(
        maxQueued: 2,
        maxQueuedCodeUnits: 8,
      );
      addTearDown(scheduler.dispose);
      final a = scheduler.createScope();
      final b = scheduler.createScope();
      final result = Completer<int>();
      final running = a.tryAcquire(
        identity: 'running',
        codeUnits: 1,
        work: () => result.future,
      )!;
      final queued = b.tryAcquire(
        identity: 'queued',
        codeUnits: 6,
        work: () async => 2,
      )!;
      expect(scheduler.queuedCodeUnits, 6);
      b.close();
      expect(await queued.future, isNull);
      expect(scheduler.queuedCodeUnits, 0);
      queued.release();
      final replacement = a.tryAcquire(
        identity: 'replacement',
        codeUnits: 8,
        work: () async => 3,
      )!;
      result.complete(1);
      await running.future;
      expect(await replacement.future, 3);
      running.release();
      replacement.release();
      a.close();
    },
  );

  test('result type is part of single-flight identity and completed values are not cached', () async {
    final scheduler = ForumPreparationScheduler();
    addTearDown(scheduler.dispose);
    final scope = scheduler.createScope();
    final result = Completer<String>();
    final text = scope.tryAcquire(
      identity: 'same',
      codeUnits: 1,
      work: () => result.future,
    )!;
    var starts = 0;
    Future<int> work() async => ++starts;
    final number = scope.tryAcquire(
      identity: 'same',
      codeUnits: 1,
      work: work,
    )!;
    expect(scheduler.queuedCount, 1);
    result.complete('text');
    expect(await text.future, 'text');
    expect(await number.future, 1);
    await drain();
    final fresh = scope.tryAcquire(identity: 'same', codeUnits: 1, work: work)!;
    expect(await fresh.future, 2);
    text.release();
    number.release();
    fresh.release();
    scope.close();
  });

  test(
    'failure releases capacity and scheduler close retires pending work',
    () async {
      final scheduler = ForumPreparationScheduler();
      final scope = scheduler.createScope();
      final result = Completer<int>();
      final first = scope.tryAcquire(
        identity: 'first',
        codeUnits: 1,
        work: () => result.future,
      )!;
      final failed = expectLater(first.future, throwsStateError);
      result.completeError(StateError('worker failed'));
      await failed;
      await drain();
      expect(scheduler.activeCount, 0);
      final activeResult = Completer<int>();
      final active = scope.tryAcquire(
        identity: 'active',
        codeUnits: 1,
        work: () => activeResult.future,
      )!;
      final queued = scope.tryAcquire(
        identity: 'queued',
        codeUnits: 1,
        work: () async => 3,
      )!;
      scheduler.dispose();
      expect(await queued.future, isNull);
      expect(scheduler.activeCount, 1);
      activeResult.complete(2);
      expect(await active.future, 2);
      await drain();
      expect(scheduler.activeCount, 0);
      first.release();
      active.release();
      queued.release();
      scope.close();
    },
  );
}
