import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_native_advance_meter.dart';

void main() {
  test(
    'many short advances keep cumulative work distinct from a slow call',
    () {
      final meter = NovelReaderNativeAdvanceMeter(
        budget: const Duration(milliseconds: 3),
      );
      for (var i = 0; i < 64; i++) {
        meter.record(1000);
      }
      final work = meter.snapshot;
      expect(work.steps, 64);
      expect(work.totalUs, 64000);
      expect(work.maxUs, 1000);
      expect(work.overBudgetSteps, 0);
      expect(work.budgetUs, 3000);
    },
  );

  test('single-call warnings use the actual budget and keep exact boundary semantics', () {
    final meter = NovelReaderNativeAdvanceMeter(
      budget: const Duration(microseconds: 750),
    );
    for (final duration in [0, 749, 750, 751, 900]) {
      meter.record(duration);
    }
    final work = meter.snapshot;
    expect(work.steps, 5);
    expect(work.totalUs, 3150);
    expect(work.maxUs, 900);
    expect(work.overBudgetSteps, 2);
    expect(work.budgetUs, 750);
  });

  test('published snapshots are immutable and preparation/coverage remain independent', () {
    final preparation = NovelReaderNativeAdvanceMeter(
      budget: const Duration(milliseconds: 3),
    );
    final coverage = NovelReaderNativeAdvanceMeter(
      budget: const Duration(milliseconds: 3),
    );
    final empty = preparation.snapshot;
    preparation.record(4000);
    final first = preparation.snapshot;
    preparation.record(1000);
    coverage.record(2000);
    expect(empty.steps, 0);
    expect(empty.maxUs, 0);
    expect(first.steps, 1);
    expect(first.totalUs, 4000);
    expect(first.overBudgetSteps, 1);
    expect(preparation.snapshot.totalUs, 5000);
    expect(coverage.snapshot.totalUs, 2000);
    expect(coverage.snapshot.overBudgetSteps, 0);
  });

  test('invalid timing data cannot corrupt successful accounting', () {
    expect(
      () => NovelReaderNativeAdvanceMeter(budget: Duration.zero),
      throwsArgumentError,
    );
    expect(
      () => NovelReaderNativeAdvanceMeter(
        budget: const Duration(microseconds: -1),
      ),
      throwsArgumentError,
    );
    final meter = NovelReaderNativeAdvanceMeter(
      budget: const Duration(milliseconds: 3),
    );
    meter.record(100);
    expect(() => meter.record(-1), throwsArgumentError);
    expect(meter.snapshot.steps, 1);
    expect(meter.snapshot.totalUs, 100);
    expect(meter.snapshot.maxUs, 100);
  });
}
