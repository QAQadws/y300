import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyEmphasisTextInput _input({
  ForumBodyParagraphLayoutMode mode =
      ForumBodyParagraphLayoutMode.intrinsicSingleLine,
  TextDirection direction = TextDirection.ltr,
  String html =
      '<p style="text-emphasis:\'X\' red;line-height:.4;">ffi é 中 '
      '<span style="font-size:15px;text-emphasis-color:blue;text-emphasis-position:under">الع 👩‍👩‍👧‍👦</span></p>',
}) {
  final doc = const ForumBodyParser().parse(
    html: html,
    sourceId: 'emphasis-metrics',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    doc,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        color: Color(0xff123456),
      ),
      fontRevision: 'metrics-ahem',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
    ),
  );
  final original = const ForumBodyParagraphContentBuilder().build(
    document: doc,
    styles: styles,
    path: '0',
    layoutMode: mode,
  );
  return _source(original);
}

ForumBodyEmphasisTextInput _source(ForumBodyParagraphContent original) {
  final job = ForumBodyEmphasisTextPreparation(content: original);
  while (!job.isReady) {
    job.advance(maxParts: 1);
  }
  return job.takeInput();
}

ForumBodyParagraphCache _cache({int entries = 16}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 24,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyEmphasisLineMetrics _measure(
  ForumBodyEmphasisLineMetricsPreparation job, {
  bool cachedOnly = false,
}) {
  var steps = 0;
  while (!job.isReady) {
    final work = job.advance(maxParts: 1, cachedOnly: cachedOnly);
    expect(work.partsPrepared, lessThanOrEqualTo(1));
    expect(work.nativeLayoutsBuilt, lessThanOrEqualTo(1));
    expect(work.picturesRecorded, 0);
    expect(work.waitingForLayoutBudget, isFalse);
    expect(job.cacheMiss, isFalse);
    expect(++steps, lessThan(10000));
  }
  expect(job.nativeLeases, isEmpty);
  return job.takeMetrics();
}

ForumBodyEmphasisLineLayout _visible(
  ForumBodyEmphasisLinePreparation job, {
  bool cachedOnly = false,
}) {
  var steps = 0;
  while (!job.isReady) {
    final work = job.advance(maxParts: 1, cachedOnly: cachedOnly);
    expect(work.partsPrepared, lessThanOrEqualTo(1));
    expect(
      work.nativeLayoutsBuilt + work.picturesRecorded,
      lessThanOrEqualTo(1),
    );
    expect(work.waitingForLayoutBudget, isFalse);
    expect(job.cacheMiss, isFalse);
    expect(++steps, lessThan(10000));
  }
  return job.takeLayout();
}

final class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double size) => size < 20 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in ForumBodyParagraphLayoutMode.values) {
    for (final direction in TextDirection.values) {
      test(
        'numeric plan makes no pictures, survives font eviction $mode $direction',
        () {
          final input = _input(mode: mode, direction: direction),
              cache = _cache();
          final width = mode == ForumBodyParagraphLayoutMode.wrap
              ? 900.0
              : 120.0;
          final previous = ui.Picture.onCreate;
          var created = 0;
          ui.Picture.onCreate = (_) {
            created++;
          };
          late ForumBodyEmphasisLineMetrics metrics;
          try {
            metrics = _measure(
              ForumBodyEmphasisLineMetricsPreparation(
                input: input,
                cache: cache,
                width: width,
                textScaler: const _Nonlinear(),
                ensureOwner: () {},
              ),
            );
          } finally {
            ui.Picture.onCreate = previous;
          }
          expect(created, 0);
          expect(cache.pictureBuildCount, 0);
          expect(cache.activeLeases, 0);
          expect(metrics.input, same(input));
          expect(metrics.effectiveScales[20], 22);
          expect(metrics.effectiveScales[10], 14);
          expect(metrics.effectiveScales[15], 21);
          expect(metrics.effectiveScales[7.5], 10.5);
          expect(metrics.nativeFootprint, hasLength(3));
          expect(() => metrics.effectiveScales.clear(), throwsUnsupportedError);
          expect(() => metrics.marks.clear(), throwsUnsupportedError);
          expect(cache.tryAcquireTextPicture(metrics.pictureInput), isNull);
          cache.clearUnpinned();
          expect(cache.entryCount, 0);
          final line = _visible(
            ForumBodyEmphasisLinePreparation.fromMetrics(
              input: input,
              metrics: metrics,
              cache: cache,
              width: width,
              expectedTextScaler: const _Nonlinear(),
              ensureOwner: () {},
            ),
          );
          try {
            expect(line.metrics, same(metrics));
            expect(line.projection, same(input.content.projection));
            expect(cache.activeLeases, 2);
            expect(cache.pictureBuildCount, 1);
            final old = cache.pictureBuildCount,
                builds = cache.layoutBuildCount;
            final warm = _visible(
              ForumBodyEmphasisLinePreparation.fromMetrics(
                input: input,
                metrics: metrics,
                cache: cache,
                width: width,
                expectedTextScaler: const _Nonlinear(),
                ensureOwner: () {},
              ),
              cachedOnly: true,
            );
            warm.close();
            expect(cache.pictureBuildCount, old);
            expect(cache.layoutBuildCount, builds);
            expect(metrics.marks, hasLength(input.units.length));
            for (final mark in metrics.marks) {
              final hit = line.sourceAt(mark.fontBounds.center);
              final unit = input.units[mark.unitIndex];
              expect(
                hit.sourceRune,
                input.content.projection
                    .sourceAtUtf16(unit.governingUtf16)
                    .sourceRune,
              );
              expect(hit.isExact, isFalse);
            }
          } finally {
            line.close();
          }
          expect(cache.activeLeases, 0);
        },
      );
    }
  }
  test(
    'picture admission is available from numbers without a native picture',
    () {
      final input = _input(), cache = _cache(entries: 3);
      final metrics = _measure(
        ForumBodyEmphasisLineMetricsPreparation(
          input: input,
          cache: cache,
          ensureOwner: () {},
        ),
      );
      final probe = cache.createBudgetProbe();
      try {
        for (final slot in metrics.nativeFootprint) {
          slot.request.includeBudget(
            probe,
            width: slot.width,
            textScaler: metrics.textScaler,
            minimumLineCount: slot.minimumLineCount,
          );
        }
        expect(
          () => probe.includeTextPicture(metrics.pictureInput),
          throwsA(
            isA<ForumBodyParagraphBudgetException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphBudgetFailure.content,
            ),
          ),
        );
        expect(cache.pictureBuildCount, 0);
        expect(cache.activeLeases, 0);
      } finally {
        probe.close();
      }
    },
  );
  test(
    'changed width, source and half-size scaling cannot reuse an old plan',
    () {
      final input = _input(), cache = _cache();
      final metrics = _measure(
        ForumBodyEmphasisLineMetricsPreparation(
          input: input,
          cache: cache,
          width: 120,
          textScaler: const _Nonlinear(),
          ensureOwner: () {},
        ),
      );
      cache.clearUnpinned();
      final builds = cache.layoutBuildCount;
      expect(
        () => ForumBodyEmphasisLinePreparation.fromMetrics(
          input: input,
          metrics: metrics,
          cache: cache,
          width: 121,
          expectedTextScaler: const _Nonlinear(),
          ensureOwner: () {},
        ),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      final other = _source(input.content);
      expect(
        () => ForumBodyEmphasisLinePreparation.fromMetrics(
          input: other,
          metrics: metrics,
          cache: cache,
          width: 120,
          expectedTextScaler: const _Nonlinear(),
          ensureOwner: () {},
        ),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      final changed = ForumBodyEmphasisLinePreparation.fromMetrics(
        input: input,
        metrics: metrics,
        cache: cache,
        width: 120,
        ensureOwner: () {},
        expectedTextScaler: _Scale(
          (size) => size == 10 ? 15 : const _Nonlinear().scale(size),
        ),
      );
      expect(
        () => _visible(changed),
        throwsA(
          isA<ForumBodyEmphasisLineException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyEmphasisLineFailure.metrics,
          ),
        ),
      );
      expect(cache.layoutBuildCount, builds);
      expect(cache.activeLeases, 0);
      expect(metrics.marks, hasLength(input.units.length));
    },
  );
  test(
    'actual values qualify independent scaler strategies and cache owners',
    () {
      final input = _input(), first = _cache();
      final metrics = _measure(
        ForumBodyEmphasisLineMetricsPreparation(
          input: input,
          cache: first,
          ensureOwner: () {},
        ),
      );
      first.close();
      final second = _cache();
      final line = _visible(
        ForumBodyEmphasisLinePreparation.fromMetrics(
          input: input,
          metrics: metrics,
          cache: second,
          width: metrics.requestWidth,
          expectedTextScaler: _Scale((size) => size),
          ensureOwner: () {},
        ),
      );
      expect(line.metrics, same(metrics));
      line.close();
      expect(second.activeLeases, 0);
    },
  );
  test(
    'band planning never prepares child images, visible binding keeps its selector',
    () {
      final whole = _input(html: '<p style="text-emphasis:\'X\' red">AB</p>');
      final a = _source(
        whole.content.displayWindow(startUtf16: 0, endUtf16: 1),
      );
      final b = _source(
        whole.content.displayWindow(startUtf16: 1, endUtf16: 2),
      );
      final cache = _cache();
      final request = ForumBodyTextRequest.bandChild(
        band: ForumBodyTextBandContent(
          contexts: [a.glyphInput.glyphs, b.glyphInput.glyphs],
        ),
        childIndex: 1,
      );
      final metrics = _measure(
        ForumBodyEmphasisLineMetricsPreparation(
          input: b,
          cache: cache,
          baseRequest: request,
          ensureOwner: () {},
        ),
      );
      expect(cache.preparedPictureCount, 0);
      expect(cache.pictureBuildCount, 0);
      expect(metrics.pictureInput.commands.first.bandChildIndex, 1);
      final job = ForumBodyEmphasisLinePreparation.fromMetrics(
        input: b,
        metrics: metrics,
        cache: cache,
        width: metrics.requestWidth,
        expectedTextScaler: TextScaler.noScaling,
        ensureOwner: () {},
      );
      while (!job.cacheMiss) {
        job.advance(maxParts: 1, cachedOnly: true);
      }
      expect(cache.pictureBuildCount, 0);
      final line = _visible(job);
      expect(cache.pictureBuildCount, 2);
      expect(line.projection, same(b.content.projection));
      line.close();
      expect(cache.activeLeases, 0);
    },
  );
  for (final retired in ['cache', 'generation']) {
    for (final ready in [false, true]) {
      test(
        'measurement $retired retirement ready=$ready prevents late numbers',
        () {
          final input = _input(), cache = _cache();
          var current = true;
          final job = ForumBodyEmphasisLineMetricsPreparation(
            input: input,
            cache: cache,
            ensureOwner: () {
              if (!current) throw StateError('Retired');
            },
          );
          if (ready) {
            while (!job.isReady) {
              job.advance(maxParts: 1);
            }
          } else {
            while (job.nativeLeases.isEmpty) {
              job.advance(maxParts: 1);
            }
          }
          if (retired == 'cache') {
            cache.close();
          } else {
            current = false;
          }
          expect(
            ready ? job.takeMetrics : () => job.advance(maxParts: 1),
            throwsStateError,
          );
          job.close();
          expect(cache.activeLeases, 0);
          expect(cache.pictureBuildCount, 0);
        },
      );
    }
  }
  test('numeric cancellation at every boundary leaves no pins or pictures', () {
    final input = _input(), firstCache = _cache();
    final first = ForumBodyEmphasisLineMetricsPreparation(
      input: input,
      cache: firstCache,
      ensureOwner: () {},
    );
    var count = 0;
    while (!first.isReady) {
      first.advance(maxParts: 1);
      count++;
    }
    first.takeMetrics();
    for (var cut = 0; cut <= count; cut++) {
      final cache = _cache();
      final job = ForumBodyEmphasisLineMetricsPreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
      );
      for (var i = 0; i < cut && !job.isReady; i++) {
        job.advance(maxParts: 1);
      }
      job.close();
      expect(cache.activeLeases, 0);
      expect(cache.pictureBuildCount, 0);
      expect(job.takeMetrics, throwsStateError);
    }
  });
  test('numeric cached-only miss and warm plans do not allocate drawings', () {
    final input = _input(), cache = _cache();
    final cold = ForumBodyEmphasisLineMetricsPreparation(
      input: input,
      cache: cache,
      ensureOwner: () {},
    );
    while (!cold.cacheMiss) {
      cold.advance(maxParts: 1, cachedOnly: true);
    }
    expect(cache.layoutBuildCount, 0);
    expect(cache.pictureBuildCount, 0);
    final first = _measure(cold);
    final builds = cache.layoutBuildCount;
    final second = _measure(
      ForumBodyEmphasisLineMetricsPreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
      ),
      cachedOnly: true,
    );
    expect(cache.layoutBuildCount, builds);
    expect(cache.pictureBuildCount, 0);
    expect(first.pictureInput, second.pictureInput);
    expect(first.nativeFootprint, hasLength(3));
    expect(first.marks, hasLength(input.units.length));
    expect(cache.activeLeases, 0);
  });
  test(
    'current scaler callback cancellation leaves its measured plan intact',
    () {
      final input = _input(), cache = _cache();
      final metrics = _measure(
        ForumBodyEmphasisLineMetricsPreparation(
          input: input,
          cache: cache,
          ensureOwner: () {},
        ),
      );
      cache.clearUnpinned();
      final builds = cache.layoutBuildCount;
      ForumBodyEmphasisLinePreparation? job;
      job = ForumBodyEmphasisLinePreparation.fromMetrics(
        input: input,
        metrics: metrics,
        cache: cache,
        width: metrics.requestWidth,
        ensureOwner: () {},
        expectedTextScaler: _Scale((size) {
          job!.close();
          return size;
        }),
      );
      expect(() => job!.advance(maxParts: 1), throwsStateError);
      expect(cache.activeLeases, 0);
      expect(cache.layoutBuildCount, builds);
      expect(metrics.effectiveScales[10], 10);
      expect(metrics.nativeFootprint, hasLength(3));
      expect(metrics.marks, hasLength(input.units.length));
    },
  );
}

final class _Scale extends TextScaler {
  const _Scale(this.sample);
  final double Function(double) sample;
  @override
  double scale(double size) => sample(size);
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}
