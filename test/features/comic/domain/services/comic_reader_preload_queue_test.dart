import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_reader_preload_queue.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';

void main() {
  group('ComicReaderPreloadQueue', () {
    test('runs higher priority tasks first', () async {
      final started = <int>[];
      final queue = ComicReaderPreloadQueue(
        maxConcurrent: 1,
        runner: (task) async {
          started.add(task.imageIndex);
          return ComicImageCacheResult(
            success: true,
            cacheKey: task.cacheKey,
          );
        },
      );
      addTearDown(queue.dispose);

      queue.enqueueAll(<ComicReaderPreloadTask>[
        _task(3, ComicReaderPreloadPriority.adjacentForward),
        _task(1, ComicReaderPreloadPriority.retry),
        _task(2, ComicReaderPreloadPriority.visible),
      ]);
      await _drainQueue();

      expect(started, <int>[1, 2, 3]);
    });

    test('dedupes episode and image index while allowing priority upgrade', () async {
      final started = <ComicReaderPreloadTask>[];
      final queue = ComicReaderPreloadQueue(
        maxConcurrent: 1,
        runner: (task) async {
          started.add(task);
          return ComicImageCacheResult(
            success: true,
            cacheKey: task.cacheKey,
          );
        },
      );
      addTearDown(queue.dispose);

      queue.enqueueAll(<ComicReaderPreloadTask>[
        _task(4, ComicReaderPreloadPriority.adjacentBackward),
        _task(4, ComicReaderPreloadPriority.visible),
        _task(4, ComicReaderPreloadPriority.nextChapter),
      ]);
      await _drainQueue();

      expect(started, hasLength(1));
      expect(started.single.priority, ComicReaderPreloadPriority.visible);
    });

    test('respects max concurrency', () async {
      final started = <int>[];
      var running = 0;
      var maxRunning = 0;
      final completers = <int, Completer<ComicImageCacheResult>>{};
      final queue = ComicReaderPreloadQueue(
        maxConcurrent: 2,
        runner: (task) {
          started.add(task.imageIndex);
          running++;
          if (running > maxRunning) {
            maxRunning = running;
          }
          final completer = Completer<ComicImageCacheResult>();
          completers[task.imageIndex] = completer;
          return completer.future.whenComplete(() {
            running--;
          });
        },
      );
      addTearDown(queue.dispose);

      queue.enqueueAll(<ComicReaderPreloadTask>[
        _task(0, ComicReaderPreloadPriority.visible),
        _task(1, ComicReaderPreloadPriority.adjacentForward),
        _task(2, ComicReaderPreloadPriority.adjacentForward),
      ]);
      await _drainQueue(iterations: 2);

      expect(started, <int>[0, 1]);
      expect(queue.snapshot.pendingCount, 1);
      completers[0]!.complete(_success(0));
      await _drainQueue(iterations: 2);

      expect(started, <int>[0, 1, 2]);
      completers[1]!.complete(_success(1));
      completers[2]!.complete(_success(2));
      await _drainQueue();

      expect(maxRunning, lessThanOrEqualTo(2));
      expect(queue.snapshot.successCount, 3);
    });

    test('cancelExcept ignores stale running result and keeps target window', () async {
      final started = <int>[];
      final results = <int>[];
      final completers = <int, Completer<ComicImageCacheResult>>{};
      final keptTask = _task(1, ComicReaderPreloadPriority.adjacentForward);
      final queue = ComicReaderPreloadQueue(
        maxConcurrent: 1,
        runner: (task) {
          started.add(task.imageIndex);
          final completer = Completer<ComicImageCacheResult>();
          completers[task.imageIndex] = completer;
          return completer.future;
        },
        onResult: (result) async {
          results.add(result.task.imageIndex);
        },
      );
      addTearDown(queue.dispose);

      queue.enqueueAll(<ComicReaderPreloadTask>[
        _task(0, ComicReaderPreloadPriority.visible),
        keptTask,
      ]);
      await _drainQueue(iterations: 2);

      expect(started, <int>[0]);
      queue.cancelExcept(<String>{keptTask.dedupeKey});
      completers[0]!.complete(_success(0));
      await _drainQueue(iterations: 2);

      expect(results, isEmpty);
      expect(started, <int>[0, 1]);
      completers[1]!.complete(_success(1));
      await _drainQueue();

      expect(results, <int>[1]);
      expect(queue.snapshot.cancelledCount, greaterThanOrEqualTo(1));
    });

    test('cancelled running tasks no longer occupy active concurrency', () async {
      final started = <int>[];
      final completers = <int, Completer<ComicImageCacheResult>>{};
      final targetTask = _task(2, ComicReaderPreloadPriority.jumpTarget);
      final queue = ComicReaderPreloadQueue(
        maxConcurrent: 1,
        runner: (task) {
          started.add(task.imageIndex);
          final completer = Completer<ComicImageCacheResult>();
          completers[task.imageIndex] = completer;
          return completer.future;
        },
      );
      addTearDown(queue.dispose);

      queue.enqueue(_task(0, ComicReaderPreloadPriority.visible));
      await _drainQueue(iterations: 2);

      queue.enqueue(targetTask, schedule: false);
      queue.cancelExcept(<String>{targetTask.dedupeKey});
      await _drainQueue(iterations: 2);

      expect(started, <int>[0, 2]);
      expect(queue.snapshot.runningCount, 1);
      completers[0]!.complete(_success(0));
      completers[2]!.complete(_success(2));
      await _drainQueue();
    });
  });
}

ComicReaderPreloadTask _task(
  int imageIndex,
  ComicReaderPreloadPriority priority,
) {
  return ComicReaderPreloadTask(
    episodeId: 'episode-a',
    imageUrl: 'https://img.test/$imageIndex.jpg',
    imageIndex: imageIndex,
    cacheKey: 'comic:episode-a:$imageIndex',
    priority: priority,
  );
}

ComicImageCacheResult _success(int imageIndex) {
  return ComicImageCacheResult(
    success: true,
    localPath: '/cache/$imageIndex.jpg',
    cacheKey: 'comic:episode-a:$imageIndex',
  );
}

Future<void> _drainQueue({int iterations = 8}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
