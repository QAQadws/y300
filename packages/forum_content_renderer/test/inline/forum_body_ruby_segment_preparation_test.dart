import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_segment_fixture.dart';

ForumBodyRubySegmentMetrics _measure(
  ForumBodyParagraphCache cache,
  ForumBodyRubySegmentRequest request,
) {
  final job = ForumBodyRubySegmentMetricsPreparation(
    cache: cache,
    request: request,
    ensureOwner: () {},
  );
  try {
    for (var i = 0; !job.isReady && i < 30000; i++) {
      job.advance();
    }
    expect(job.isReady, isTrue);
    return job.takeMetrics();
  } finally {
    job.close();
  }
}

void _drain(
  ForumBodyRubySegmentPreparation job,
  ForumBodyParagraphCache cache,
  int q,
) {
  var calls = 0;
  while (!job.isReady && calls++ < 30000) {
    final before = (cache.layoutBuildCount, cache.pictureBuildCount);
    final step = job.advance(maxParts: q);
    expect(step.formatUnitsPrepared, inInclusiveRange(1, q));
    expect(step.waitingForLayoutBudget, isFalse);
    expect(
      cache.layoutBuildCount - before.$1 + cache.pictureBuildCount - before.$2,
      lessThanOrEqualTo(1),
    );
    expect(step.layoutsBuilt, cache.layoutBuildCount - before.$1);
    expect(step.picturesBuilt, cache.pictureBuildCount - before.$2);
  }
  expect(job.isReady, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final q in [1, 7, 32]) {
    for (final dense in [false, true]) {
      test(
        'actual visible span members acquire and paint within q=$q dense=$dense',
        () {
          final fixture = RubySegmentFixture(dense: dense);
          addTearDown(fixture.close);
          final metrics = fixture.compose();
          final request = fixture.request();
          fixture.releaseGlyphs();
          final job = ForumBodyRubySegmentPreparation(
            cache: fixture.cache,
            request: request,
            metrics: metrics,
            ensureOwner: () {},
          );
          addTearDown(job.close);
          _drain(job, fixture.cache, q);
          expect(job.preparedColumnCount, 2);
          expect(job.preparedSpanCount, dense ? 100 : 4);
          expect(job.preparedPartCount, request.nativeHandleCount);
          expect(job.expectedPartCount, request.nativeHandleCount);
          expect(job.currentRequest, isNull);
          final before = (
            fixture.cache.layoutBuildCount,
            fixture.cache.pictureBuildCount,
          );
          final layout = job.takeLayout();
          addTearDown(layout.close);
          expect(job.nativeLeases, isEmpty);
          expect(layout.nativeLeases.length, request.nativeHandleCount);
          expect(layout.isOwnedBy(fixture.cache), isTrue);
          expect(layout.size, metrics.size);
          expect(fixture.cache.pictureBuildCount, request.nativeHandleCount);
          for (var i = 0; i < request.spans.length; i++) {
            expect(
              layout.contentForSpan(i),
              same(request.spans[i].request.content),
            );
            final box = layout
                .selectionBoxesForSpan(spanIndex: i, startUtf16: 1, endUtf16: 2)
                .single;
            final hit = layout.sourceAt(
              Offset(box.left + .001, (box.top + box.bottom) / 2),
            );
            expect(hit.spanIndex, i);
            expect(hit.position.isExact, isTrue);
            expect(box.top, greaterThanOrEqualTo(-.0001));
            expect(box.bottom, lessThanOrEqualTo(metrics.size.height + .0001));
          }
          final recorder = ui.PictureRecorder();
          layout.paint(ui.Canvas(recorder), Offset.zero);
          recorder.endRecording().dispose();
          expect((
            fixture.cache.layoutBuildCount,
            fixture.cache.pictureBuildCount,
          ), before);
          layout.close();
          expect(fixture.cache.activeLeases, 0);
          fixture.cache.close();
          expect(fixture.cache.estimatedRetainedBytes, 0);
        },
      );
    }
  }

  test('RTL scaled tight leading reuses actual numeric geometry', () {
    final scaler = const TextScaler.linear(1.27);
    final fixture = RubySegmentFixture(
      direction: TextDirection.rtl,
      lineHeight: .25,
      textScaler: scaler,
    );
    addTearDown(fixture.close);
    final metrics = fixture.compose();
    final request = fixture.request();
    fixture.releaseGlyphs();
    final job = ForumBodyRubySegmentPreparation(
      cache: fixture.cache,
      request: request,
      metrics: metrics,
      ensureOwner: () {},
      textScaler: scaler,
    );
    addTearDown(job.close);
    _drain(job, fixture.cache, 7);
    final layout = job.takeLayout();
    addTearDown(layout.close);
    expect(
      layout.metrics.columnLefts.first,
      greaterThan(layout.metrics.columnLefts.last),
    );
    expect(layout.metrics.direction, TextDirection.rtl);
  });

  test(
    'cold misses and warm numeric continuation do not silently shape or record',
    () {
      final fixture = RubySegmentFixture(dense: true);
      addTearDown(fixture.close);
      final metrics = fixture.compose();
      final request = fixture.request();
      fixture.releaseGlyphs();
      ForumBodyRubySegmentPreparation open() => ForumBodyRubySegmentPreparation(
        cache: fixture.cache,
        request: request,
        metrics: metrics,
        ensureOwner: () {},
      );
      final cold = open();
      addTearDown(cold.close);
      final shapes = fixture.cache.layoutBuildCount;
      expect(cold.tryPrepareCached(maxParts: 1), isFalse);
      expect(cold.cacheMiss, isTrue);
      expect(fixture.cache.layoutBuildCount, shapes);
      expect(fixture.cache.pictureBuildCount, 0);
      _drain(cold, fixture.cache, 32);
      cold.takeLayout().close();
      final before = (
        fixture.cache.layoutBuildCount,
        fixture.cache.pictureBuildCount,
      );
      final warm = open();
      addTearDown(warm.close);
      for (var i = 0; !warm.isReady && i < 30000; i++) {
        final work = warm.workCount;
        warm.tryPrepareCached(maxParts: 1);
        expect(warm.workCount - work, 1);
        expect(warm.cacheMiss, isFalse);
        expect((
          fixture.cache.layoutBuildCount,
          fixture.cache.pictureBuildCount,
        ), before);
      }
      expect(warm.isReady, isTrue);
      warm.takeLayout().close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test('resident glyphs without pictures are a real paint miss', () {
    final fixture = RubySegmentFixture();
    addTearDown(fixture.close);
    final request = fixture.request();
    final metrics = fixture.compose();
    fixture.releaseGlyphs(clear: false);
    final before = fixture.cache.layoutBuildCount;
    final job = ForumBodyRubySegmentPreparation(
      cache: fixture.cache,
      request: request,
      metrics: metrics,
      ensureOwner: () {},
    );
    addTearDown(job.close);
    expect(job.tryPrepareCached(maxParts: 32), isFalse);
    expect(job.cacheMiss, isTrue);
    expect(fixture.cache.pictureBuildCount, 0);
    _drain(job, fixture.cache, 32);
    job.takeLayout().close();
    expect(fixture.cache.layoutBuildCount, before);
    expect(fixture.cache.activeLeases, 0);
  });

  for (final releaseEarly in [false, true]) {
    test(
      'complete 102-slot budget probe stays bounded and resumes, early=$releaseEarly',
      () {
        final fixture = RubySegmentFixture(dense: true);
        addTearDown(fixture.close);
        final request = fixture.request();
        final metrics = fixture.compose();
        fixture.releaseGlyphs();
        final cache = ForumBodyParagraphCache(
          maxEntries: 2,
          maxEstimatedBytes: 1 << 24,
        );
        addTearDown(cache.close);
        final foreign = cache.acquire(content: fixture.bases.first, width: 300);
        addTearDown(foreign.release);
        final job = ForumBodyRubySegmentPreparation(
          cache: cache,
          request: request,
          metrics: metrics,
          ensureOwner: () {},
        );
        addTearDown(job.close);
        var inspected = 0;
        var released = false;
        for (
          var i = 0;
          !job.waitingForLayoutBudget && !job.isReady && i < 30000;
          i++
        ) {
          final step = job.advance(maxParts: 1);
          expect(step.formatUnitsPrepared, lessThanOrEqualTo(1));
          inspected += step.partsInspected;
          if (releaseEarly && inspected == 1 && !released) {
            foreign.release();
            released = true;
          }
        }
        expect(inspected, 102);
        if (!releaseEarly) {
          expect(job.waitingForLayoutBudget, isTrue);
          expect(job.lastBudgetRejection, isNotNull);
          final work = job.workCount;
          final before = (cache.layoutBuildCount, cache.pictureBuildCount);
          for (var i = 0; i < 3; i++) {
            expect(job.advance(maxParts: 7).waitingForLayoutBudget, isTrue);
          }
          expect(job.workCount, work);
          expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
          foreign.release();
        }
        if (!job.isReady) _drain(job, cache, 7);
        final layout = job.takeLayout();
        expect(layout.nativeLeases.length, 102);
        layout.close();
        expect(cache.activeLeases, 0);
      },
    );
  }

  for (final prefixCount in [0, 2]) {
    test(
      'whole footprint rejects intrinsic overflow hidden by foreign pin, prefix=$prefixCount',
      () {
        final fixture = RubySegmentFixture();
        addTearDown(fixture.close);
        final request = fixture.request(individual: true);
        fixture.releaseGlyphs();
        final metrics = _measure(fixture.cache, request);
        final cache = ForumBodyParagraphCache(
          maxEntries: prefixCount == 0 ? 3 : 7,
          maxEstimatedBytes: 1 << 24,
        );
        addTearDown(cache.close);
        final prefix = [
          for (var i = 0; i < prefixCount; i++)
            cache.acquire(
              content: fixture.bases.first,
              width: 300,
              textScaler: TextScaler.linear(1.2 + i * .1),
            ),
        ];
        final foreign = cache.acquire(
          content: fixture.bases.first,
          width: 400,
          textScaler: const TextScaler.linear(2),
        );
        addTearDown(() {
          for (final lease in prefix) {
            lease.release();
          }
          foreign.release();
        });
        final job = ForumBodyRubySegmentPreparation(
          cache: cache,
          request: request,
          metrics: metrics,
          ensureOwner: () {},
          additionalOwnedLeases: () => prefix,
        );
        addTearDown(job.close);
        expect(
          () {
            for (var i = 0; !job.isReady && i < 30000; i++) {
              final step = job.advance(maxParts: 1);
              expect(step.waitingForLayoutBudget, isFalse);
            }
          },
          throwsA(
            isA<ForumBodyParagraphBudgetException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphBudgetFailure.content,
            ),
          ),
        );
        expect(job.state, ForumBodyRubySegmentPreparationState.failed);
        expect(cache.activeLeases, prefixCount + 1);
        expect(foreign.isActive, isTrue);
      },
    );
  }

  test('cancel during a partial full probe releases only component pins', () {
    final fixture = RubySegmentFixture(dense: true);
    addTearDown(fixture.close);
    final request = fixture.request();
    final metrics = fixture.compose();
    fixture.releaseGlyphs();
    final cache = ForumBodyParagraphCache(
      maxEntries: 2,
      maxEstimatedBytes: 1 << 24,
    );
    addTearDown(cache.close);
    final foreign = cache.acquire(content: fixture.bases.first, width: 300);
    addTearDown(foreign.release);
    final job = ForumBodyRubySegmentPreparation(
      cache: cache,
      request: request,
      metrics: metrics,
      ensureOwner: () {},
    );
    addTearDown(job.close);
    for (var i = 0; i < 30000; i++) {
      if (job.advance(maxParts: 1).partsInspected > 0) break;
    }
    expect(job.waitingForLayoutBudget, isFalse);
    expect(cache.activeLeases, greaterThan(1));
    job.close();
    expect(cache.activeLeases, 1);
    expect(foreign.isActive, isTrue);
    expect(job.nativeLeases, isEmpty);
  });

  for (final ready in [false, true]) {
    test(
      'late owner retirement rejects transfer and releases members, ready=$ready',
      () {
        final fixture = RubySegmentFixture();
        addTearDown(fixture.close);
        final request = fixture.request();
        final metrics = fixture.compose();
        fixture.releaseGlyphs();
        var retired = false;
        final job = ForumBodyRubySegmentPreparation(
          cache: fixture.cache,
          request: request,
          metrics: metrics,
          ensureOwner: () {
            if (retired) throw StateError('retired');
          },
        );
        addTearDown(job.close);
        if (ready) {
          _drain(job, fixture.cache, 7);
        } else {
          job.advance(maxParts: 1);
        }
        expect(fixture.cache.activeLeases, greaterThan(0));
        retired = true;
        expect(
          () => ready ? job.takeLayout() : job.advance(),
          throwsStateError,
        );
        expect(fixture.cache.activeLeases, 0);
        expect(job.nativeLeases, isEmpty);
      },
    );
  }

  for (final inSpan in [false, true]) {
    test(
      'native scaler cancellation releases late base/span lease, span=$inSpan',
      () {
        final fixture = RubySegmentFixture();
        addTearDown(fixture.close);
        final request = fixture.request();
        final metrics = fixture.compose();
        fixture.releaseGlyphs();
        var cancel = !inSpan;
        late ForumBodyRubySegmentPreparation job;
        job = ForumBodyRubySegmentPreparation(
          cache: fixture.cache,
          request: request,
          metrics: metrics,
          ensureOwner: () {},
          textScaler: _Scaler((size) {
            if (cancel) job.close();
            return size;
          }),
        );
        addTearDown(job.close);
        if (inSpan) {
          while (job.preparedColumnCount < 2) {
            job.advance(maxParts: 1);
          }
          // Cached native acquisition must also reject callback cancellation.
          cancel = true;
        }
        expect(() => job.advance(maxParts: 1), throwsStateError);
        expect(fixture.cache.activeLeases, 0);
      },
    );
  }

  test(
    'original span interval/gap and numeric direction cannot be substituted',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final request = fixture.request();
      final metrics = fixture.compose();
      fixture.releaseGlyphs();
      expect(
        () => ForumBodyRubySegmentPreparation(
          cache: fixture.cache,
          request: ForumBodyRubySegmentRequest(
            bases: request.bases,
            sides: request.sides,
            spans: request.spans,
            direction: TextDirection.rtl,
          ),
          metrics: metrics,
          ensureOwner: () {},
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      final altered = ForumBodyRubySegmentRequest(
        bases: request.bases,
        sides: request.sides,
        spans: [
          for (final (i, span) in request.spans.indexed)
            (
              request: span.request,
              startColumn: span.startColumn,
              endColumn: span.endColumn,
              annotationIndex: span.annotationIndex,
              gap: i == 3 ? 1.0 : span.gap,
            ),
        ],
      );
      final job = ForumBodyRubySegmentPreparation(
        cache: fixture.cache,
        request: altered,
        metrics: metrics,
        ensureOwner: () {},
      );
      addTearDown(job.close);
      expect(() {
        for (var i = 0; !job.isReady && i < 30000; i++) {
          job.advance();
        }
      }, throwsA(isA<ForumBodyRubyGroupException>()));
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'prefix probe deduplicates actual aliases and rejects foreign/retired handles',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final cache = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(cache.close);
      final request = fixture.request().bases.first;
      final one = request.acquire(
        cache,
        cachedOnly: false,
        width: 16384,
        textScaler: TextScaler.noScaling,
      )!;
      final alias = request.acquire(
        cache,
        cachedOnly: false,
        width: 16384,
        textScaler: TextScaler.noScaling,
      )!;
      addTearDown(one.release);
      addTearDown(alias.release);
      final probe = cache.createBudgetProbe();
      addTearDown(probe.close);
      probe.includeLease(one);
      probe.includeLease(alias);
      request.includeBudget(
        probe,
        width: 16384,
        textScaler: TextScaler.noScaling,
      );
      expect(
        () => probe.includeLease(fixture.lease(fixture.bases.first)),
        throwsStateError,
      );
      alias.release();
      expect(() => probe.includeLease(alias), throwsStateError);
      probe.close();
      expect(() => probe.includeLease(one), throwsStateError);
    },
  );

  test(
    'empty base strut and empty span retain rank without fabricated source',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final original = fixture.request();
      final request = ForumBodyRubySegmentRequest(
        bases: [ForumBodyTextRequest.paragraph(fixture.empty)],
        sides: [ForumBodyRubySide.over, ForumBodyRubySide.under],
        spans: [
          (
            request: original.spans.last.request,
            startColumn: 0,
            endColumn: 1,
            annotationIndex: 0,
            gap: 0.0,
          ),
          (
            request: ForumBodyTextRequest.paragraph(fixture.empty),
            startColumn: 0,
            endColumn: 1,
            annotationIndex: 1,
            gap: 0.0,
          ),
        ],
      );
      fixture.releaseGlyphs();
      final metrics = _measure(fixture.cache, request);
      final job = ForumBodyRubySegmentPreparation(
        cache: fixture.cache,
        request: request,
        metrics: metrics,
        ensureOwner: () {},
      );
      addTearDown(job.close);
      _drain(job, fixture.cache, 1);
      final layout = job.takeLayout();
      addTearDown(layout.close);
      expect(layout.nativeLeases.length, 2);
      expect(job.preparedPartCount, 2);
      expect(job.preparedSpanCount, 2);
      expect(layout.contentForSpan(1), same(fixture.empty));
      expect(
        layout.selectionBoxesForSpan(spanIndex: 1, startUtf16: 0, endUtf16: 0),
        isEmpty,
      );
      final blank = layout.sourceAt(
        Offset(metrics.size.width / 2, metrics.baseline),
      );
      expect(blank.position.isExact, isFalse);
      final box = layout
          .selectionBoxesForSpan(spanIndex: 0, startUtf16: 1, endUtf16: 2)
          .single;
      final exact = layout.sourceAt(
        Offset(box.left + .001, (box.top + box.bottom) / 2),
      );
      expect(exact.spanIndex, 0);
      expect(exact.position.isExact, isTrue);
      layout.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'closing inside the full-prefix callback cannot retain a late iterator',
    () {
      final fixture = RubySegmentFixture(dense: true);
      addTearDown(fixture.close);
      final request = fixture.request();
      final metrics = fixture.compose();
      fixture.releaseGlyphs();
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(cache.close);
      final foreign = cache.acquire(content: fixture.bases.first, width: 300);
      addTearDown(foreign.release);
      var callbacks = 0;
      late ForumBodyRubySegmentPreparation job;
      job = ForumBodyRubySegmentPreparation(
        cache: cache,
        request: request,
        metrics: metrics,
        ensureOwner: () {},
        additionalOwnedLeases: () {
          if (++callbacks == 2) job.close();
          return const [];
        },
      );
      addTearDown(job.close);
      expect(() {
        for (var i = 0; !job.isReady && i < 30000; i++) {
          job.advance(maxParts: 1);
        }
      }, throwsStateError);
      expect(callbacks, 2);
      expect(job.nativeLeases, isEmpty);
      expect(cache.activeLeases, 1);
      expect(foreign.isActive, isTrue);
    },
  );

  test(
    'visible band failure reports its original spec and releases all pins',
    () {
      final fixture = RubySegmentFixture(lineHeight: .25);
      addTearDown(fixture.close);
      final metrics = fixture.compose();
      final request = fixture.request().mapRequests(
        (r) => r is ForumBodyTextBandChildRequest
            ? ForumBodyTextRequest.bandChild(
                band: r.band,
                childIndex: r.childIndex,
                gutter: 1,
              )
            : r,
      );
      fixture.releaseGlyphs();
      final job = ForumBodyRubySegmentPreparation(
        cache: fixture.cache,
        request: request,
        metrics: metrics,
        ensureOwner: () {},
      );
      addTearDown(job.close);
      expect(
        () => job.advance(),
        throwsA(isA<ForumBodyTextBandLayoutException>()),
      );
      expect(job.failedRequest, same(request.bases.first));
      expect(fixture.cache.activeLeases, 0);
      job.close();
      expect(job.failedRequest, isNull);
    },
  );
  test(
    'a column-only intrinsic budget failure uses the component budget error',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final request = fixture.request(individual: true);
      fixture.releaseGlyphs();
      final metrics = _measure(fixture.cache, request);
      final cache = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(cache.close);
      final job = ForumBodyRubySegmentPreparation(
        cache: cache,
        request: request,
        metrics: metrics,
        ensureOwner: () {},
      );
      addTearDown(job.close);
      expect(
        () {
          for (var i = 0; !job.isReady && i < 30000; i++) {
            job.advance(maxParts: 1);
          }
        },
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      expect(job.state, ForumBodyRubySegmentPreparationState.failed);
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'owner retirement immediately after recording releases the pending picture lease',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final request = fixture.request();
      final metrics = fixture.compose();
      fixture.releaseGlyphs();
      late ForumBodyRubySegmentPreparation job;
      job = ForumBodyRubySegmentPreparation(
        cache: fixture.cache,
        request: request,
        metrics: metrics,
        ensureOwner: () {
          if (fixture.cache.pictureBuildCount > 0) job.close();
        },
      );
      addTearDown(job.close);
      expect(() {
        for (var i = 0; !job.isReady && i < 100; i++) {
          job.advance(maxParts: 1);
        }
      }, throwsStateError);
      expect(fixture.cache.pictureBuildCount, 1);
      expect(fixture.cache.activeLeases, 0);
      expect(job.nativeLeases, isEmpty);
    },
  );

  test('reentrant acquisition cannot publish or retain the component', () {
    final fixture = RubySegmentFixture();
    addTearDown(fixture.close);
    final request = fixture.request();
    final metrics = fixture.compose();
    fixture.releaseGlyphs();
    late ForumBodyRubySegmentPreparation job;
    job = ForumBodyRubySegmentPreparation(
      cache: fixture.cache,
      request: request,
      metrics: metrics,
      ensureOwner: () {},
      textScaler: _Scaler((size) {
        job.advance(maxParts: 1);
        return size;
      }),
    );
    addTearDown(job.close);
    expect(() => job.advance(maxParts: 1), throwsStateError);
    expect(fixture.cache.activeLeases, 0);
    expect(job.state, ForumBodyRubySegmentPreparationState.failed);
  });
}

final class _Scaler extends TextScaler {
  const _Scaler(this.callback);
  final double Function(double) callback;
  @override
  double scale(double size) => callback(size);
  @override
  double get textScaleFactor => 1;
}
