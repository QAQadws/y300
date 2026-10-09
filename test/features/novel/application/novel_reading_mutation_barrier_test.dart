import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/novel/application/novel_reading_mutation_barrier.dart';

void main() {
  test('chapter mutation retires only that chapter producer', () {
    final barrier = NovelReadingMutationBarrier();
    final a = barrier.capture('novel', 'a');
    final b = barrier.capture('novel', 'b');
    final other = barrier.capture('other', 'a');
    final work = barrier.captureWork('novel');

    barrier.invalidate('novel', 'a');

    expect(barrier.isCurrent('novel', 'a', a), isFalse);
    expect(barrier.isCurrent('novel', 'b', b), isTrue);
    expect(barrier.isCurrent('other', 'a', other), isTrue);
    expect(barrier.isWorkCurrent('novel', work), isFalse);
  });

  test(
    'work reset retires every old producer without enumerating chapters',
    () {
      final barrier = NovelReadingMutationBarrier();
      barrier.invalidate('novel', 'a');
      final a = barrier.capture('novel', 'a');
      final neverPersisted = barrier.capture('novel', 'pending-first-position');
      final other = barrier.capture('other', 'a');

      barrier.invalidateWork('novel');

      expect(barrier.isCurrent('novel', 'a', a), isFalse);
      expect(
        barrier.isCurrent('novel', 'pending-first-position', neverPersisted),
        isFalse,
      );
      expect(barrier.isCurrent('other', 'a', other), isTrue);
      final fresh = barrier.capture('novel', 'a');
      expect(barrier.isCurrent('novel', 'a', fresh), isTrue);
      barrier.invalidate('novel', 'b');
      expect(barrier.isCurrent('novel', 'a', fresh), isTrue);
    },
  );

  test('any newer same-work navigation retires a queued work reset', () {
    final barrier = NovelReadingMutationBarrier();
    barrier.invalidateWork('novel');
    final reset = barrier.captureWork('novel');
    final producer = barrier.capture('novel', 'a');
    barrier.invalidate('other', 'a');
    expect(barrier.isWorkCurrent('novel', reset), isTrue);

    barrier.invalidate('novel', 'newly-synced-chapter');

    expect(barrier.isWorkCurrent('novel', reset), isFalse);
    expect(barrier.isCurrent('novel', 'a', producer), isTrue);
  });

  test('successive resets never revalidate old chapter or work revisions', () {
    final barrier = NovelReadingMutationBarrier();
    final old = barrier.capture('novel', 'a');
    barrier.invalidateWork('novel');
    final firstReset = barrier.captureWork('novel');
    final firstProducer = barrier.capture('novel', 'a');
    barrier.invalidate('novel', 'a');
    barrier.invalidateWork('novel');

    expect(barrier.isCurrent('novel', 'a', old), isFalse);
    expect(barrier.isCurrent('novel', 'a', firstProducer), isFalse);
    expect(barrier.isWorkCurrent('novel', firstReset), isFalse);
  });
}
