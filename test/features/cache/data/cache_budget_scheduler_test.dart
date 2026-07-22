import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/services/cache_budget_scheduler.dart';
import 'package:y300/features/cache/data/services/cache_mutation_bus.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

void main() {
  test('startup runs immediately and burst mutations are debounced', () async {
    final bus = CacheMutationBus();
    addTearDown(bus.dispose);
    var enforceCalls = 0;
    final scheduler = CacheBudgetScheduler(
      source: bus,
      debounce: const Duration(milliseconds: 5),
      enforce: () async {
        enforceCalls += 1;
      },
    );
    addTearDown(scheduler.dispose);

    await scheduler.start();
    bus.reportMutation(CacheNamespace.image);
    bus.reportMutation(CacheNamespace.document);
    bus.reportMutation(CacheNamespace.snapshot);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(enforceCalls, 2);
  });

  test('mutation during an active run requests exactly one rerun', () async {
    final bus = CacheMutationBus();
    addTearDown(bus.dispose);
    final firstRun = Completer<void>();
    var enforceCalls = 0;
    final scheduler = CacheBudgetScheduler(
      source: bus,
      debounce: Duration.zero,
      enforce: () async {
        enforceCalls += 1;
        if (enforceCalls == 1) {
          await firstRun.future;
        }
      },
    );
    addTearDown(scheduler.dispose);

    final startup = scheduler.start();
    bus.reportMutation(CacheNamespace.image);
    bus.reportMutation(CacheNamespace.document);
    await Future<void>.delayed(Duration.zero);
    firstRun.complete();
    await startup;
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(enforceCalls, 2);
  });
}
