import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_preparation.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

typedef _Result = ({
  ForumBodyInlinePageContent page,
  ForumBodyInlineParagraphLease parent,
});
ForumBodyParagraphCache _cache({int entries = 1}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(cache.close);
  return cache;
}

MixedEmphasisParentFixture _fixture(String child, {bool emphasis = false}) =>
    MixedEmphasisParentFixture(
      child,
      parentStyle:
          'text-emphasis:${emphasis ? 'circle' : 'none'};line-height:.8',
      prefix: 'P',
      suffix: 'Q',
    );
ForumBodyInlinePlanPreparation _open(
  MixedEmphasisParentFixture f,
  ForumBodyParagraphCache cache, {
  bool emphasis = false,
  void Function()? guard,
  Iterable<ForumBodyNativeParagraphLease> Function()? owned,
}) => emphasis
    ? ForumBodyInlinePlanPreparation.emphasisParent(
        input: f.input,
        glyphInput: f.text.glyphInput,
        cache: cache,
        textScaler: TextScaler.noScaling,
        ensureOwner: guard ?? () {},
        additionalOwnedLeases: owned,
      )
    : ForumBodyInlinePlanPreparation(
        input: f.input,
        cache: cache,
        textScaler: TextScaler.noScaling,
        ensureOwner: guard ?? () {},
        additionalOwnedLeases: owned,
      );
({int calls, _Result value}) _finish(
  ForumBodyInlinePlanPreparation job,
  ForumBodyParagraphCache cache, {
  bool emphasis = false,
}) {
  var calls = 0;
  try {
    while (!job.isReady) {
      expect(calls++, lessThan(50000));
      final before = (cache.layoutBuildCount, cache.pictureBuildCount),
          s = job.advance(maxParts: 1);
      expect(s.waitingForLayoutBudget, isFalse);
      expect(job.cacheMiss, isFalse);
      expect(s.partsPrepared, inInclusiveRange(0, 1));
      expect(cache.layoutBuildCount - before.$1, inInclusiveRange(0, 1));
      expect(cache.pictureBuildCount, before.$2);
    }
    if (emphasis) {
      final r = job.takeEmphasisParent();
      return (calls: calls, value: (page: r.plan, parent: r.lease));
    }
    final r = job.take();
    return (calls: calls, value: (page: r.content, parent: r.lease));
  } finally {
    job.close();
  }
}

ForumBodyParagraphLease _pin(
  ForumBodyParagraphCache cache, [
  String tag = 'pin',
]) {
  final doc = const ForumBodyParser().parse(
    html: '<p>$tag</p>',
    sourceId: 'plan-$tag',
    conversionIdentity: 'none',
  );
  final content = const ForumBodyParagraphContentBuilder().build(
    document: doc,
    styles: const ForumBodyStyleResolver().resolve(
      doc,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
        fontRevision: 'plan-pin',
        linkColor: const Color(0xff0000ff),
      ),
    ),
    path: '0',
  );
  final pin = cache.acquire(content: content, width: 300);
  addTearDown(pin.release);
  return pin;
}

bool _intrinsic(Object e) =>
    e is ForumBodyParagraphBudgetException &&
        e.failure == ForumBodyParagraphBudgetFailure.content ||
    e is ForumBodyRubyGroupPreparationException &&
        e.failure == ForumBodyRubyGroupPreparationFailure.intrinsicBudget;
void _expectOwnedFailure(ForumBodyInlinePlanPreparation job) {
  Object? error;
  try {
    for (var n = 0; !job.isReady; n++) {
      expect(n, lessThan(50000));
      final s = job.advance(maxParts: 1);
      expect(s.waitingForLayoutBudget, isFalse);
    }
  } catch (e) {
    error = e;
  } finally {
    job.close();
  }
  expect(error, isNotNull);
  expect(_intrinsic(error!), isTrue, reason: error.toString());
}

ForumBodyInlineFlowContent _flow() {
  final doc = const ForumBodyParser().parse(
    html: '<p>P<ruby>A<rt>x</rt></ruby>Q</p>',
    sourceId: 'owned-flow',
    conversionIdentity: 'none',
  );
  final cursor = ForumBodyTextFlowCursor(
    document: doc,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
      fontRevision: 'owned-flow',
      linkColor: const Color(0xff0000ff),
    ),
  );
  try {
    while (!cursor.isComplete) {
      cursor.advance(maxEvents: 1);
      if (cursor.current case ForumBodyTextFlowInline(:final content)) {
        return content;
      }
    }
    throw StateError('Missing mixed flow');
  } finally {
    cursor.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final emphasis in [false, true]) {
    for (final (index, child) in mixedEmphasisChildren.indexed) {
      test(
        'initial nested plan rejects owned prefix pressure $index/$emphasis',
        () {
          final cache = _cache(),
              f = _fixture(child, emphasis: emphasis),
              pin = _pin(cache);
          var prefixCalls = 0;
          final job = _open(
            f,
            cache,
            emphasis: emphasis,
            owned: () {
              prefixCalls++;
              return [pin];
            },
          );
          final before = (
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            cache.activeLeases,
          );
          _expectOwnedFailure(job);
          expect(prefixCalls, greaterThan(0));
          expect((
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            cache.activeLeases,
          ), before);
          expect(pin.isActive, isTrue);
          expect(job.nativeLeases, isEmpty);
        },
      );
      test(
        'external pin blocks without rescanning and resumes same plan $index/$emphasis',
        () {
          final cache = _cache(entries: 2),
              f = _fixture(child, emphasis: emphasis),
              pin = _pin(cache),
              second = _pin(cache, 'second');
          var prefixCalls = 0;
          final job = _open(
            f,
            cache,
            emphasis: emphasis,
            owned: () {
              prefixCalls++;
              return const [];
            },
          );
          addTearDown(job.close);
          for (var n = 0; ; n++) {
            expect(n, lessThan(50000));
            if (job.advance(maxParts: 1).waitingForLayoutBudget) break;
          }
          final before = (
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            prefixCalls,
          );
          for (var n = 0; n < 3; n++) {
            final s = job.advance(maxParts: 32);
            expect(s.partsPrepared, 0);
            expect(s.waitingForLayoutBudget, isTrue);
          }
          expect((
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            prefixCalls,
          ), before);
          pin.release();
          second.release();
          final value = _finish(job, cache, emphasis: emphasis).value;
          try {
            expect(value.page.content, same(f.input.content));
            expect(cache.activeLeases, 1);
          } finally {
            value.parent.release();
          }
        },
      );
      test(
        'pin release while capturing prefix retries without stale intrinsic failure $index/$emphasis',
        () {
          final cache = _cache(entries: 2),
              f = _fixture(child, emphasis: emphasis),
              pin = _pin(cache),
              second = _pin(cache, 'second');
          var released = false;
          final job = _open(
            f,
            cache,
            emphasis: emphasis,
            owned: () {
              if (!released) {
                released = true;
                pin.release();
                second.release();
              }
              return const [];
            },
          );
          final value = _finish(job, cache, emphasis: emphasis).value;
          try {
            expect(released, isTrue);
            expect(value.page.content, same(f.input.content));
            expect(cache.activeLeases, 1);
          } finally {
            value.parent.release();
          }
        },
      );
    }
  }
  for (final index in [0, 1, 4, 5]) {
    test(
      'owned prefix remains visible at every later native-free boundary $index',
      () {
        final baselineCache = _cache(entries: 2),
            baselineFixture = _fixture(
              mixedEmphasisChildren[index],
              emphasis: true,
            );
        final baseline = _finish(
          _open(
            baselineFixture,
            baselineCache,
            emphasis: true,
            owned: () => const [],
          ),
          baselineCache,
          emphasis: true,
        );
        baseline.value.parent.release();
        baselineCache.close();
        var injected = 0;
        for (var boundary = 0; boundary < baseline.calls; boundary++) {
          final cache = _cache(entries: 2),
              f = _fixture(mixedEmphasisChildren[index], emphasis: true);
          final pins = <ForumBodyNativeParagraphLease>[];
          final job = _open(f, cache, emphasis: true, owned: () => pins);
          try {
            for (var n = 0; n < boundary && !job.isReady; n++) {
              final s = job.advance(maxParts: 1);
              expect(s.waitingForLayoutBudget, isFalse);
            }
            if (job.isReady || cache.activeLeases != 0) continue;
            pins.add(_pin(cache, 'first'));
            pins.add(_pin(cache, 'second'));
            final before = (cache.layoutBuildCount, cache.pictureBuildCount);
            _expectOwnedFailure(job);
            expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
            expect(cache.activeLeases, 2);
            expect(pins.every((p) => p.isActive), isTrue);
            injected++;
          } finally {
            job.close();
            for (final pin in pins) {
              pin.release();
            }
            cache.close();
          }
        }
        expect(injected, greaterThan(5));
      },
    );
  }
  test(
    'line marker measurement ignores a rejection retired by its prefix callback',
    () {
      final cache = _cache(entries: 2),
          first = _pin(cache),
          second = _pin(cache, 'second');
      final doc = const ForumBodyParser().parse(
        html: '<p style="text-emphasis:circle">A</p>',
        sourceId: 'line-prefix-release',
        conversionIdentity: 'none',
      );
      final content = const ForumBodyParagraphContentBuilder().build(
        document: doc,
        styles: const ForumBodyStyleResolver().resolve(
          doc,
          ForumBodyReaderStyle(
            textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
            fontRevision: 'line-prefix-release',
            linkColor: const Color(0xff0000ff),
          ),
        ),
        path: '0',
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
      final text = ForumBodyEmphasisTextPreparation(content: content);
      while (!text.isReady) {
        text.advance(maxParts: 1);
      }
      final input = text.takeInput();
      var callbacks = 0;
      final work = ForumBodyEmphasisLineMetricsPreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
        additionalOwnedLeases: () {
          if (++callbacks == 2) {
            first.release();
            second.release();
          }
          return const [];
        },
      );
      try {
        for (var n = 0; !work.isReady; n++) {
          expect(n, lessThan(50000));
          final s = work.advance(maxParts: 1);
          expect(s.waitingForLayoutBudget, isFalse);
          expect(work.cacheMiss, isFalse);
        }
        expect(work.takeMetrics().input, same(input));
        expect(callbacks, greaterThanOrEqualTo(2));
        expect(cache.activeLeases, 0);
      } finally {
        work.close();
      }
    },
  );
  test(
    'mixed parent marker font classification recaptures after pin release',
    () {
      final cache = _cache(entries: 2),
          f = _fixture(mixedEmphasisChildren.first, emphasis: true);
      final measured = _finish(
        _open(f, cache, emphasis: true),
        cache,
        emphasis: true,
      ).value;
      addTearDown(measured.parent.release);
      final geometryWork = ForumBodyInlineEmphasisGeometryPreparation(
        input: f.text,
        parent: measured.parent,
        ensureOwner: () {},
      );
      while (!geometryWork.isReady) {
        geometryWork.advance(maxParts: 1);
      }
      final geometry = geometryWork.takeGeometry();
      geometryWork.close();
      final pin = _pin(cache);
      var callbacks = 0;
      final work = ForumBodyInlineEmphasisFontPreparation(
        geometry: geometry,
        parentRequest: ForumBodyInlineParagraphRequest(
          content: measured.parent.content,
          dimensions: measured.page.dimensions,
          layoutMode: measured.page.layoutMode,
        ),
        parent: measured.parent,
        cache: cache,
        ensureOwner: () {},
        expectedTextScaler: TextScaler.noScaling,
        width: 300,
        additionalOwnedLeases: () {
          if (++callbacks == 2) pin.release();
          return const [];
        },
      );
      try {
        for (var n = 0; !work.isReady; n++) {
          expect(n, lessThan(50000));
          final s = work.advance(maxParts: 1);
          expect(s.waitingForLayoutBudget, isFalse);
          expect(work.cacheMiss, isFalse);
        }
        expect(work.takeMetrics().geometry, same(geometry));
        expect(callbacks, greaterThanOrEqualTo(2));
        expect(cache.activeLeases, 1);
      } finally {
        work.close();
      }
    },
  );
  test('flow constructor passes caller prefix through source preparation', () {
    final cache = _cache(), pin = _pin(cache);
    var validated = 0;
    final job = ForumBodyInlinePlanPreparation.fromFlow(
      input: _flow(),
      width: 300,
      cache: cache,
      textScaler: TextScaler.noScaling,
      ensureOwner: () {},
      validateInput: (_) {
        validated++;
      },
      additionalOwnedLeases: () => [pin],
    );
    _expectOwnedFailure(job);
    expect(validated, 1);
    expect(pin.isActive, isTrue);
    expect(cache.activeLeases, 1);
  });
  test(
    'prefix wakeup recaptures newly owned resources instead of waiting again',
    () {
      final cache = _cache(),
          f = _fixture(mixedEmphasisChildren.first),
          pin = _pin(cache);
      var nowOwned = false;
      final job = _open(f, cache, owned: () => nowOwned ? [pin] : const []);
      addTearDown(job.close);
      for (var n = 0; ; n++) {
        expect(n, lessThan(50000));
        if (job.advance(maxParts: 1).waitingForLayoutBudget) break;
      }
      final alias = cache.acquire(content: pin.content, width: 300);
      alias.release();
      nowOwned = true;
      _expectOwnedFailure(job);
      expect(pin.isActive, isTrue);
      expect(cache.activeLeases, 1);
    },
  );
  test(
    'retirement while blocked still checks owner and preserves borrowed pins',
    () {
      final cache = _cache(),
          f = _fixture(mixedEmphasisChildren.first),
          pin = _pin(cache);
      var active = true;
      final job = _open(
        f,
        cache,
        guard: () {
          if (!active) throw StateError('Retired');
        },
      );
      for (var n = 0; ; n++) {
        expect(n, lessThan(50000));
        if (job.advance(maxParts: 1).waitingForLayoutBudget) break;
      }
      active = false;
      expect(() => job.advance(maxParts: 32), throwsStateError);
      job.close();
      expect(pin.isActive, isTrue);
      expect(cache.activeLeases, 1);
    },
  );
  test(
    'foreign, oversized and retiring prefix cannot install partial plans',
    () {
      final cache = _cache(),
          foreign = _cache(),
          localPin = _pin(cache),
          foreignPin = _pin(foreign),
          f = _fixture(mixedEmphasisChildren.first);
      final wrong = _open(f, cache, owned: () => [foreignPin]);
      expect(() => _finish(wrong, cache), throwsStateError);
      expect(cache.activeLeases, 1);
      final oversized = _open(
        f,
        cache,
        owned: () => Iterable.generate(32769, (_) => localPin),
      );
      expect(
        () => _finish(oversized, cache),
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphInputFailure.inputLimit,
          ),
        ),
      );
      late ForumBodyInlinePlanPreparation retired;
      Iterable<ForumBodyNativeParagraphLease> prefix() sync* {
        yield localPin;
        retired.close();
        yield localPin;
      }

      retired = _open(f, cache, owned: prefix);
      expect(() => _finish(retired, cache), throwsStateError);
      expect(localPin.isActive, isTrue);
      expect(cache.activeLeases, 1);
    },
  );
}
