import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/image_loading/domain/image_prefetcher.dart';

void main() {
  group('DefaultImagePrefetcher', () {
    test('runs higher-priority (smaller value) requests first', () async {
      final order = <String>[];
      final prefetcher = DefaultImagePrefetcher(
        maxConcurrent: 1,
        runner: (request) async {
          order.add(request.dedupeKey);
          return true;
        },
      );

      prefetcher.submit(<ImagePrefetchRequest>[
        const ImagePrefetchRequest(dedupeKey: 'c', priority: 3),
        const ImagePrefetchRequest(dedupeKey: 'a', priority: 0),
        const ImagePrefetchRequest(dedupeKey: 'b', priority: 1),
      ]);
      await _drain();

      expect(order, <String>['a', 'b', 'c']);
      prefetcher.dispose();
    });

    test('dedupes by key and never runs the same key twice', () async {
      final runs = <String>[];
      final prefetcher = DefaultImagePrefetcher(
        maxConcurrent: 2,
        runner: (request) async {
          runs.add(request.dedupeKey);
          return true;
        },
      );

      prefetcher.submit(<ImagePrefetchRequest>[
        const ImagePrefetchRequest(dedupeKey: 'a', priority: 1),
        const ImagePrefetchRequest(dedupeKey: 'a', priority: 0),
      ]);
      await _drain();
      // 重新提交同一已完成 key 不应再次执行。
      prefetcher.submit(<ImagePrefetchRequest>[
        const ImagePrefetchRequest(dedupeKey: 'a', priority: 0),
      ]);
      await _drain();

      expect(runs, <String>['a']);
      prefetcher.dispose();
    });

    test(
      're-submitting upgrades pending priority without cancelling',
      () async {
        final started = <String>[];
        // 用一个永不完成的运行槽占住并发，制造“待执行队列”观察重排。
        final gate = Completer<void>();
        final prefetcher = DefaultImagePrefetcher(
          maxConcurrent: 1,
          runner: (request) async {
            started.add(request.dedupeKey);
            if (request.dedupeKey == 'blocker') {
              await gate.future;
            }
            return true;
          },
        );

        prefetcher.submit(<ImagePrefetchRequest>[
          const ImagePrefetchRequest(dedupeKey: 'blocker', priority: 0),
          const ImagePrefetchRequest(dedupeKey: 'x', priority: 5),
          const ImagePrefetchRequest(dedupeKey: 'y', priority: 6),
        ]);
        await _drain();
        // blocker 占住唯一并发；x/y 在排队。把 y 升到最急。
        prefetcher.submit(<ImagePrefetchRequest>[
          const ImagePrefetchRequest(dedupeKey: 'y', priority: 1),
        ]);
        gate.complete();
        await _drain();

        // blocker 先跑（未被取消），随后 y（已升优先级）早于 x。
        expect(started, <String>['blocker', 'y', 'x']);
        prefetcher.dispose();
      },
    );

    test('emits idle snapshot after all work completes', () async {
      final snapshots = <ImagePrefetcherSnapshot>[];
      final prefetcher = DefaultImagePrefetcher(
        maxConcurrent: 2,
        onSnapshot: snapshots.add,
        runner: (request) async => true,
      );

      prefetcher.submit(<ImagePrefetchRequest>[
        const ImagePrefetchRequest(dedupeKey: 'a', priority: 0),
        const ImagePrefetchRequest(dedupeKey: 'b', priority: 1),
      ]);
      await _drain();

      expect(snapshots.isNotEmpty, isTrue);
      expect(snapshots.last.isIdle, isTrue);
      prefetcher.dispose();
    });
  });
}

/// 等待若干微任务轮次，让预取器的 scheduleMicrotask 泵跑完。
Future<void> _drain() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
