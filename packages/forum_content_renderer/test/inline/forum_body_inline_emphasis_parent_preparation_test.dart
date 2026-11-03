import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

typedef _Measurement = ({
  ForumBodyInlineEmphasisParentMetrics metrics,
  ForumBodyInlineParagraphLease parent,
});

ForumBodyParagraphCache _cache({int entries = 512}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(cache.close);
  return cache;
}

({int parts, _Measurement value}) _finish(
  ForumBodyInlineEmphasisParentPreparation work,
  ForumBodyParagraphCache cache, {
  int quantum = 1,
  bool cachedOnly = false,
}) {
  var parts = 0;
  for (var n = 0; !work.isReady; n++) {
    expect(n, lessThan(200000));
    final before = (cache.layoutBuildCount, cache.pictureBuildCount);
    final step = work.advance(maxParts: quantum, cachedOnly: cachedOnly);
    expect(step.partsPrepared, inInclusiveRange(1, quantum));
    expect(step.nativeLayoutsBuilt, cache.layoutBuildCount - before.$1);
    expect(step.nativeLayoutsBuilt, inInclusiveRange(0, 1));
    expect(step.waitingForLayoutBudget, isFalse);
    expect(work.cacheMiss, isFalse);
    expect(step.picturesRecorded, 0);
    expect(cache.pictureBuildCount, before.$2);
    parts += step.partsPrepared;
  }
  expect(cache.activeLeases, work.nativeLeases.length);
  expect(work.nativeLeases.length, 1);
  expect(work.advance(maxParts: 1).partsPrepared, 0);
  final value = work.takeMeasurement();
  expect(work.nativeLeases, isEmpty);
  work.close();
  return (parts: parts, value: value);
}

ForumBodyInlineFlowContent _flow(String body) {
  final doc = const ForumBodyParser().parse(
    html: '<p style="text-emphasis:circle;line-height:.4">$body</p>',
    sourceId: 'whole-parent',
    conversionIdentity: 'none',
  );
  final cursor = ForumBodyTextFlowCursor(
    document: doc,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        color: Color(0xff123456),
      ),
      fontRevision: 'whole-parent',
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
    throw StateError('Expected actual inline flow');
  } finally {
    cursor.close();
  }
}

ForumBodyParagraphLease _pin(ForumBodyParagraphCache cache, String id) {
  final doc = const ForumBodyParser().parse(
    html: '<p>$id</p>',
    sourceId: id,
    conversionIdentity: 'none',
  );
  return cache.acquire(
    content: const ForumBodyParagraphContentBuilder().build(
      document: doc,
      styles: const ForumBodyStyleResolver().resolve(
        doc,
        ForumBodyReaderStyle(
          textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
          fontRevision: id,
          linkColor: const Color(0xff0000ff),
        ),
      ),
      path: '0',
    ),
    width: 300,
  );
}

class _Scaler extends TextScaler {
  const _Scaler(this.resolve);
  final double Function(double) resolve;
  @override
  double scale(double size) => resolve(size);
  @override
  double get textScaleFactor => throw StateError('Use real sizes');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final (i, child) in mixedEmphasisChildren.indexed) {
    for (final side in ['over', 'under']) {
      for (final direction in TextDirection.values) {
        for (final scaler in [
          TextScaler.noScaling,
          const MixedEmphasisCurve(),
        ]) {
          for (final width in [70.0, 300.0]) {
            test('complete parent $i/$side/$direction/$scaler/$width', () {
              final cache = _cache();
              final fixture = MixedEmphasisParentFixture(
                child,
                direction: direction,
                width: width,
                parentStyle:
                    'text-emphasis:circle;text-emphasis-position:$side;line-height:.4',
                prefix:
                    '<span style="font-size:120px;text-emphasis:none">W</span>P',
                suffix: 'Q<br>R',
              );
              final initial = fixture
                  .finish(fixture.open(cache, scaler: scaler), cache)
                  .value;
              final rows = ForumBodyInlineEmphasisRowPlacementPreparation(
                input: fixture.bands(initial, cache, scaler: scaler),
                ensureOwner: () {},
              );
              while (!rows.isReady) {
                rows.advance(maxParts: 1);
              }
              final expectedWork = ForumBodyInlineEmphasisReflowPreparation(
                placement: rows.takePlacement(),
                original: initial.lease,
                cache: cache,
                ensureOwner: () {},
              );
              while (!expectedWork.isReady) {
                expectedWork.advance(maxParts: 1);
              }
              final expected = expectedWork.takeMeasurement();
              initial.lease.release();
              expected.parent.release();
              final job = ForumBodyInlineEmphasisParentPreparation(
                input: fixture.input,
                cache: cache,
                textScaler: scaler,
                ensureOwner: () {},
              );
              final result = _finish(
                job,
                cache,
                quantum: i.isEven ? 1 : 7,
              ).value;
              addTearDown(result.parent.release);
              expect(result.metrics.text.content, same(fixture.input.content));
              expect(
                result.parent.content,
                same(result.metrics.text.glyphInput.glyphs),
              );
              expect(
                result.metrics.geometry.lines,
                same(result.parent.layout.lines),
              );
              expect(
                result.metrics.geometry.nativeInputIdentity,
                result.parent.nativeInputIdentity,
              );
              expect(
                result.metrics.reflow.finalInputIdentity,
                expected.reference.finalInputIdentity,
              );
              expect(
                result.metrics.reflow.baselineDeltas,
                expected.reference.baselineDeltas,
              );
              expect(
                result.metrics.geometry.atomLineIndices,
                expected.geometry.atomLineIndices,
              );
              expect(
                result.metrics.geometry.targets.map((t) => t.fontBounds),
                expected.geometry.targets.map((t) => t.fontBounds),
              );
              expect(
                result.metrics.geometry.targets.map(
                  (t) => t.governingFontBounds,
                ),
                expected.geometry.targets.map((t) => t.governingFontBounds),
              );
              expect(
                result.metrics.parentRequest.content,
                same(result.parent.content),
              );
              expect(
                result.parent.layout.dimensions,
                result.metrics.page.dimensions,
              );
              expect(
                result.metrics.parentRequest.layoutMode,
                result.metrics.page.layoutMode,
              );
              expect(cache.pictureBuildCount, 0);
              expect(cache.activeLeases, 1);
              expect(
                () => result.metrics.effectiveScales[20] = 4,
                throwsUnsupportedError,
              );
            });
          }
        }
      }
    }
  }

  test(
    'fromFlow freezes complete parent and opaque-child sizes before native work',
    () {
      final cache = _cache(), calls = <double, int>{};
      var sealed = false, validated = 0;
      final curve = _Scaler((s) {
        expect(sealed, isFalse);
        expect(cache.layoutBuildCount, 0);
        calls[s] = (calls[s] ?? 0) + 1;
        return const MixedEmphasisCurve().scale(s);
      });
      final work = ForumBodyInlineEmphasisParentPreparation.fromFlow(
        input: _flow(
          '<span style="font-size:31px">P</span>${mixedEmphasisChildren[4]}Q',
        ),
        width: 70,
        cache: cache,
        textScaler: curve,
        ensureOwner: () {},
        validateInput: (_) {
          validated++;
        },
      );
      while (!work.isReady) {
        final step = work.advance(maxParts: 1);
        if (step.nativeLayoutsBuilt > 0) sealed = true;
      }
      final value = work.takeMeasurement();
      addTearDown(value.parent.release);
      expect(validated, 1);
      expect(calls.values, everyElement(1));
      expect(calls.keys, containsAll([20.0, 31.0, 15.5, 10.0, 12.0, 6.0]));
      expect(value.metrics.effectiveScales.keys, unorderedEquals(calls.keys));
      for (final size in calls.keys) {
        expect(
          value.metrics.textScaler.scale(size),
          const MixedEmphasisCurve().scale(size),
        );
      }
      expect(() => value.metrics.textScaler.scale(123.45), throwsStateError);
      expect(cache.activeLeases, 1);
    },
  );

  test(
    'whole parent exceeds primitive target and box defaults without truncation',
    () {
      final cache = _cache();
      final work = ForumBodyInlineEmphasisParentPreparation.fromFlow(
        input: _flow(
          '${List.filled(4200, 'P').join()}${mixedEmphasisChildren[0]}Q',
        ),
        width: 300,
        cache: cache,
        textScaler: TextScaler.noScaling,
        ensureOwner: () {},
      );
      final value = _finish(work, cache, quantum: 53).value;
      addTearDown(value.parent.release);
      expect(value.metrics.text.units.length, 4201);
      expect(value.metrics.geometry.targets.length, 4201);
      expect(value.metrics.reflow.children.placement.marks.length, 4201);
      expect(cache.activeLeases, 1);
    },
  );

  test('cold cached-only miss preserves one plan and resumes in place', () {
    final cache = _cache();
    final work = ForumBodyInlineEmphasisParentPreparation.fromFlow(
      input: _flow('P${mixedEmphasisChildren[1]}Q'),
      width: 70,
      cache: cache,
      textScaler: const MixedEmphasisCurve(),
      ensureOwner: () {},
    );
    for (var i = 0; !work.cacheMiss; i++) {
      expect(i, lessThan(10000));
      work.advance(maxParts: 7, cachedOnly: true);
    }
    expect(cache.layoutBuildCount, 0);
    final value = _finish(work, cache).value;
    addTearDown(value.parent.release);
    expect(value.metrics.geometry.targets.length, 2);
  });

  test(
    'warm retired discovery misses resume without repeating source or caller scaling',
    () {
      final cache = _cache();
      final input = _flow('P${mixedEmphasisChildren[5]}Q');
      final first = _finish(
        ForumBodyInlineEmphasisParentPreparation.fromFlow(
          input: input,
          width: 70,
          cache: cache,
          textScaler: const MixedEmphasisCurve(),
          ensureOwner: () {},
        ),
        cache,
      ).value;
      final key = first.parent.nativeInputIdentity;
      first.parent.release();
      var validated = 0, misses = 0, resume = false;
      final sizes = <double>{};
      final work = ForumBodyInlineEmphasisParentPreparation.fromFlow(
        input: input,
        width: 70,
        cache: cache,
        ensureOwner: () {},
        validateInput: (_) {
          validated++;
        },
        textScaler: _Scaler((size) {
          expect(sizes.add(size), isTrue);
          return const MixedEmphasisCurve().scale(size);
        }),
      );
      addTearDown(work.close);
      for (var n = 0; !work.isReady; n++) {
        expect(n, lessThan(10000));
        final cached = !resume, before = cache.layoutBuildCount;
        final step = work.advance(maxParts: 1, cachedOnly: cached);
        expect(step.nativeLayoutsBuilt, inInclusiveRange(0, 1));
        expect(step.waitingForLayoutBudget, isFalse);
        if (cached) expect(cache.layoutBuildCount, before);
        if (work.cacheMiss) {
          expect(cached, isTrue);
          misses++;
          resume = true;
        } else {
          expect(step.partsPrepared, 1);
          resume = false;
        }
      }
      final value = work.takeMeasurement();
      addTearDown(value.parent.release);
      expect(misses, greaterThan(0));
      expect(validated, 1);
      expect(value.parent.nativeInputIdentity, key);
      expect(cache.activeLeases, 1);
      expect(cache.pictureBuildCount, 0);
    },
  );

  for (final owned in [false, true]) {
    test(
      'whole preparing prefix ${owned ? 'fails owned pressure' : 'waits for external pressure'}',
      () {
        final cache = _cache(entries: 2);
        final pins = [_pin(cache, 'pin1'), _pin(cache, 'pin2')];
        addTearDown(() {
          for (final pin in pins) {
            pin.release();
          }
        });
        final fixture = MixedEmphasisParentFixture(mixedEmphasisChildren[1]);
        final work = ForumBodyInlineEmphasisParentPreparation(
          input: fixture.input,
          cache: cache,
          textScaler: TextScaler.noScaling,
          ensureOwner: () {},
          additionalOwnedLeases: owned ? () => pins : null,
        );
        addTearDown(work.close);
        var waited = false, rejected = false;
        for (var i = 0; !waited && !rejected; i++) {
          expect(i, lessThan(10000));
          try {
            waited = work.advance(maxParts: 1).waitingForLayoutBudget;
          } on ForumBodyParagraphBudgetException catch (error) {
            expect(error.failure, ForumBodyParagraphBudgetFailure.content);
            rejected = true;
          }
        }
        expect(rejected, owned);
        expect(pins.every((p) => p.isActive), isTrue);
        if (!owned) {
          for (var i = 0; i < 3; i++) {
            final step = work.advance(maxParts: 99);
            expect(step.partsPrepared, 0);
            expect(step.waitingForLayoutBudget, isTrue);
          }
          for (final pin in pins) {
            pin.release();
          }
          final value = _finish(work, cache).value;
          addTearDown(value.parent.release);
        }
      },
    );
  }

  test(
    'retirement at every quantum releases owned resources, including transfer boundaries',
    () {
      final cache = _cache();
      final fixture = MixedEmphasisParentFixture(mixedEmphasisChildren[1]);
      final baseline = _finish(
        ForumBodyInlineEmphasisParentPreparation(
          input: fixture.input,
          cache: cache,
          textScaler: TextScaler.noScaling,
          ensureOwner: () {},
        ),
        cache,
      );
      baseline.value.parent.release();
      for (var boundary = 0; boundary <= baseline.parts; boundary++) {
        var retired = false;
        final work = ForumBodyInlineEmphasisParentPreparation(
          input: fixture.input,
          cache: cache,
          textScaler: TextScaler.noScaling,
          ensureOwner: () {
            if (retired) throw StateError('retired');
          },
        );
        for (var i = 0; i < boundary && !work.isReady; i++) {
          work.advance(maxParts: 1, cachedOnly: true);
        }
        retired = true;
        expect(() => work.advance(maxParts: 1), throwsStateError);
        work.close();
        expect(cache.activeLeases, 0);
        expect(work.nativeLeases, isEmpty);
      }
    },
  );

  test('guard close after child transfer cannot leak an unadopted lease', () {
    final cache = _cache();
    final fixture = MixedEmphasisParentFixture(mixedEmphasisChildren[1]);
    final baseline = _finish(
      ForumBodyInlineEmphasisParentPreparation(
        input: fixture.input,
        cache: cache,
        textScaler: TextScaler.noScaling,
        ensureOwner: () {},
      ),
      cache,
    );
    baseline.value.parent.release();
    // After transfer, the subworker no longer reports the returned parent.
    // Exercise every guard call around each publication, not just advances.
    var guardCount = 0;
    var work = ForumBodyInlineEmphasisParentPreparation(
      input: fixture.input,
      cache: cache,
      textScaler: TextScaler.noScaling,
      ensureOwner: () {
        guardCount++;
      },
    );
    while (!work.isReady) {
      work.advance(maxParts: 32, cachedOnly: true);
    }
    work.takeMeasurement().parent.release();
    for (var retireAt = 1; retireAt <= guardCount; retireAt++) {
      var count = 0;
      ForumBodyInlineEmphasisParentPreparation? active;
      void guard() {
        if (++count == retireAt) {
          active?.close();
          throw StateError('retired');
        }
      }

      try {
        work = ForumBodyInlineEmphasisParentPreparation(
          input: fixture.input,
          cache: cache,
          textScaler: TextScaler.noScaling,
          ensureOwner: guard,
        );
        active = work;
        while (!work.isReady) {
          work.advance(maxParts: 32, cachedOnly: true);
        }
        final value = work.takeMeasurement();
        value.parent.release();
      } on StateError {
        /* Expected retirement at the selected guard. */
      } finally {
        active?.close();
      }
      expect(count, greaterThanOrEqualTo(retireAt));
      expect(cache.activeLeases, 0, reason: 'guard $retireAt');
    }
  });

  for (final scale in [0.0, -1.0, double.nan, double.infinity, 4097.0]) {
    test('invalid scale $scale fails before native work', () {
      final cache = _cache();
      final work = ForumBodyInlineEmphasisParentPreparation.fromFlow(
        input: _flow('P${mixedEmphasisChildren[0]}Q'),
        width: 300,
        cache: cache,
        textScaler: _Scaler((_) => scale),
        ensureOwner: () {},
      );
      expect(() {
        while (!work.isReady) {
          work.advance(maxParts: 7);
        }
      }, throwsA(isA<ForumBodyParagraphLayoutException>()));
      expect(cache.layoutBuildCount, 0);
      expect(cache.activeLeases, 0);
    });
  }

  test('font size cardinality cap fails before native work', () {
    final cache = _cache();
    final work = ForumBodyInlineEmphasisParentPreparation.fromFlow(
      input: _flow('P${mixedEmphasisChildren[1]}Q'),
      width: 300,
      cache: cache,
      textScaler: TextScaler.noScaling,
      ensureOwner: () {},
      maxFontSizes: 1,
    );
    expect(() {
      while (!work.isReady) {
        work.advance(maxParts: 1);
      }
    }, throwsA(isA<ForumBodyEmphasisGeometryException>()));
    expect(cache.layoutBuildCount, 0);
    expect(cache.activeLeases, 0);
  });
}
