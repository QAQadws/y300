import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyEmphasisTextInput _input({String text = 'AB'}) {
  final document = const ForumBodyParser().parse(
    html: '<p style="text-emphasis:\'X\' red">$text</p>',
    sourceId: 'emphasis-page-budget',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  final content = const ForumBodyParagraphContentBuilder().build(
    document: document,
    styles: styles,
    path: '0',
    layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
  );
  final job = ForumBodyEmphasisTextPreparation(content: content);
  while (!job.isReady) {
    job.advance(maxParts: 1);
  }
  return job.takeInput();
}

ForumBodyParagraphCache _cache(int entries) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 24,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyTextLease _prefix(ForumBodyParagraphCache cache) {
  final lease = cache.acquire(
    content: _input(text: 'prefix').glyphInput.glyphs,
    width: 100,
  );
  addTearDown(lease.release);
  return lease;
}

ForumBodyEmphasisLineLayout _finish(ForumBodyEmphasisLinePreparation job) {
  for (var i = 0; !job.isReady && i < 10000; i++) {
    final step = job.advance(maxParts: 1);
    expect(step.partsPrepared, lessThanOrEqualTo(1));
    expect(
      step.nativeLayoutsBuilt + step.picturesRecorded,
      lessThanOrEqualTo(1),
    );
    expect(step.waitingForLayoutBudget, isFalse);
  }
  expect(job.isReady, isTrue);
  return job.takeLayout();
}

ForumBodyEmphasisLineMetrics _measure(
  ForumBodyEmphasisLineMetricsPreparation job,
) {
  for (var i = 0; !job.isReady && i < 10000; i++) {
    final step = job.advance(maxParts: 1);
    expect(step.waitingForLayoutBudget, isFalse);
    expect(step.picturesRecorded, 0);
  }
  expect(job.isReady, isTrue);
  return job.takeMetrics();
}

final _contentFailure = throwsA(
  isA<ForumBodyParagraphBudgetException>().having(
    (e) => e.failure,
    'failure',
    ForumBodyParagraphBudgetFailure.content,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('numeric footprint includes own prefix before any new shaping', () {
    final input = _input(), cache = _cache(2), prefix = _prefix(cache);
    // A genuine outside pin cannot turn the impossible owned footprint into a wait.
    final external = cache.acquire(
      content: _input(text: 'external').glyphInput.glyphs,
      width: 100,
    );
    addTearDown(external.release);
    final builds = cache.layoutBuildCount;
    final job = ForumBodyEmphasisLineMetricsPreparation(
      input: input,
      cache: cache,
      ensureOwner: () {},
      additionalOwnedLeases: () => [prefix],
    );
    expect(() => _measure(job), _contentFailure);
    expect(cache.layoutBuildCount, builds);
    expect(cache.pictureBuildCount, 0);
    expect(cache.activeLeases, 2);
    expect(prefix.isActive && external.isActive, isTrue);
  });

  test(
    'visible scene counts own prefix instead of waiting for its release',
    () {
      final input = _input(), cache = _cache(3), prefix = _prefix(cache);
      final job = ForumBodyEmphasisLinePreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
        additionalOwnedLeases: () => [prefix],
      );
      expect(() => _finish(job), _contentFailure);
      expect(cache.pictureBuildCount, 0);
      expect(cache.activeLeases, 1);
      expect(prefix.isActive, isTrue);
      expect(job.nativeLeases, isEmpty);
    },
  );

  test('rebound scene footprint is rejected before reacquiring any font', () {
    final input = _input(), planningCache = _cache(8);
    final metrics = _measure(
      ForumBodyEmphasisLineMetricsPreparation(
        input: input,
        cache: planningCache,
        ensureOwner: () {},
      ),
    );
    planningCache.close();
    final cache = _cache(3), prefix = _prefix(cache);
    final builds = cache.layoutBuildCount;
    final job = ForumBodyEmphasisLinePreparation.fromMetrics(
      input: input,
      metrics: metrics,
      cache: cache,
      ensureOwner: () {},
      width: metrics.requestWidth,
      expectedTextScaler: TextScaler.noScaling,
      additionalOwnedLeases: () => [prefix],
    );
    expect(() => _finish(job), _contentFailure);
    expect(cache.layoutBuildCount, builds);
    expect(cache.pictureBuildCount, 0);
    expect(cache.activeLeases, 1);
    expect(prefix.isActive, isTrue);
  });

  test('actual shared base aliases deduplicate with the page prefix', () {
    final input = _input(), cache = _cache(3);
    final prefix = cache.acquire(
      content: input.glyphInput.glyphs,
      width: 16384,
    );
    addTearDown(prefix.release);
    final line = _finish(
      ForumBodyEmphasisLinePreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
        additionalOwnedLeases: () => [prefix, prefix],
      ),
    );
    expect(cache.layoutBuildCount, 2);
    expect(cache.pictureBuildCount, 1);
    expect(cache.activeLeases, 3);
    line.close();
    expect(cache.activeLeases, 1);
    expect(prefix.isActive, isTrue);
  });

  test(
    'outside pressure waits and resumes without discarding the page prefix',
    () {
      final input = _input(), cache = _cache(4), prefix = _prefix(cache);
      final external = cache.acquire(
        content: _input(text: 'external').glyphInput.glyphs,
        width: 100,
      );
      addTearDown(external.release);
      final job = ForumBodyEmphasisLinePreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
        additionalOwnedLeases: () => [prefix],
      );
      var waiting = false;
      for (var i = 0; !waiting && i < 1000; i++) {
        waiting = job.advance(maxParts: 1).waitingForLayoutBudget;
      }
      expect(waiting, isTrue);
      final builds = cache.layoutBuildCount;
      final base = job.nativeLeases.whereType<ForumBodyTextLease>().first;
      expect(cache.pictureBuildCount, 0);
      expect(job.advance().waitingForLayoutBudget, isTrue);
      expect(cache.layoutBuildCount, builds);
      external.release();
      final line = _finish(job);
      expect(line.nativeLeases.first, same(base));
      expect(cache.layoutBuildCount, builds);
      expect(prefix.isActive, isTrue);
      line.close();
      expect(cache.activeLeases, 1);
    },
  );

  for (final lazy in [false, true]) {
    test('prefix retirement cancels line preparation (lazy=$lazy)', () {
      final input = _input(), cache = _cache(8), prefix = _prefix(cache);
      late ForumBodyEmphasisLinePreparation job;
      Iterable<ForumBodyNativeParagraphLease> lazyPrefix() sync* {
        job.close();
        yield prefix;
      }

      job = ForumBodyEmphasisLinePreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
        additionalOwnedLeases: () {
          if (lazy) return lazyPrefix();
          job.close();
          return [prefix];
        },
      );
      expect(() => _finish(job), throwsStateError);
      expect(cache.layoutBuildCount, 1);
      expect(cache.pictureBuildCount, 0);
      expect(cache.activeLeases, 1);
    });
  }

  test(
    'numeric prefix walk is bounded and cancellation preserves the prefix',
    () {
      final input = _input(), cache = _cache(8), prefix = _prefix(cache);
      var inspected = 0;
      Iterable<ForumBodyNativeParagraphLease> leases() sync* {
        for (var i = 0; i < 100; i++) {
          inspected++;
          yield prefix;
        }
      }

      final job = ForumBodyEmphasisLineMetricsPreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
        additionalOwnedLeases: leases,
      );
      for (var i = 0; inspected < 3 && i < 100; i++) {
        final before = inspected;
        job.advance(maxParts: 1);
        expect(inspected - before, lessThanOrEqualTo(1));
        expect(cache.layoutBuildCount, 1);
      }
      expect(inspected, 3);
      job.close();
      expect(cache.activeLeases, 1);
      expect(prefix.isActive, isTrue);
    },
  );
}
