import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/paragraph/forum_body_text_request_preparation.dart';

import 'test_support/ruby_segment_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final q in [1, 7, 32]) {
    for (final dense in [false, true]) {
      test(
        'actual segment request releases measured glyphs within q=$q dense=$dense',
        () {
          final fixture = RubySegmentFixture(dense: dense);
          addTearDown(fixture.close);
          final expected = fixture.compose();
          final request = fixture.request();
          fixture.releaseGlyphs();
          // Two bands cannot be pinned together in this cache, but glyph-only
          // planning needs only one current member. Visible admission is separate.
          final cache = ForumBodyParagraphCache(
            maxEntries: 1,
            maxEstimatedBytes: 1 << 24,
          );
          addTearDown(cache.close);
          final job = ForumBodyRubySegmentMetricsPreparation(
            cache: cache,
            request: request,
            ensureOwner: () {},
          );
          addTearDown(job.close);
          var calls = 0;
          while (!job.isReady && calls++ < 30000) {
            final before = cache.layoutBuildCount;
            final step = job.advance(maxParts: q);
            expect(step.layoutsBuilt, cache.layoutBuildCount - before);
            expect(step.layoutsBuilt, lessThanOrEqualTo(1));
            expect(step.picturesBuilt, 0);
            expect(step.formatUnitsPrepared, inInclusiveRange(1, q));
            expect(step.waitingForLayoutBudget, isFalse);
            expect(cache.activeLeases, lessThanOrEqualTo(1));
          }
          expect(job.isReady, isTrue);
          expect(cache.activeLeases, 0);
          expect(cache.pictureBuildCount, 0);
          expect(job.preparedColumnCount, 2);
          expect(job.preparedSpanCount, dense ? 100 : 4);
          final result = job.takeMetrics();
          expect(result.size.width, expected.size.width);
          expect(result.size.height, closeTo(expected.size.height, 1e-4));
          expect(result.columnWidths, expected.columnWidths);
          expect(job.nativeLeases, isEmpty);
          expect(job.currentRequest, isNull);
          cache.close();
          expect(cache.estimatedRetainedBytes, 0);
          expect(result.spans.length, dense ? 100 : 4);
        },
      );
    }
  }

  test('warm cache-only numeric progress is not a glyph miss or a rebuild', () {
    final fixture = RubySegmentFixture(dense: true);
    addTearDown(fixture.close);
    final request = fixture.request();
    fixture.releaseGlyphs(clear: false);
    final before = fixture.cache.layoutBuildCount;
    final job = ForumBodyRubySegmentMetricsPreparation(
      cache: fixture.cache,
      request: request,
      ensureOwner: () {},
    );
    addTearDown(job.close);
    expect(job.tryPrepareCached(maxParts: 1), isFalse);
    expect(job.cacheMiss, isFalse);
    for (var i = 0; !job.isReady && i < 30000; i++) {
      job.tryPrepareCached(maxParts: 1);
      expect(job.cacheMiss, isFalse);
      expect(fixture.cache.layoutBuildCount, before);
      expect(fixture.cache.pictureBuildCount, 0);
    }
    expect(job.isReady, isTrue);
    job.takeMetrics();
    expect(fixture.cache.activeLeases, 0);
  });

  test('cold cache-only query reports an actual miss without native work', () {
    final fixture = RubySegmentFixture();
    addTearDown(fixture.close);
    final request = fixture.request();
    fixture.releaseGlyphs();
    final before = fixture.cache.layoutBuildCount;
    final job = ForumBodyRubySegmentMetricsPreparation(
      cache: fixture.cache,
      request: request,
      ensureOwner: () {},
    );
    addTearDown(job.close);
    expect(job.tryPrepareCached(maxParts: 7), isFalse);
    expect(job.cacheMiss, isTrue);
    expect(fixture.cache.layoutBuildCount, before);
    expect(fixture.cache.activeLeases, 0);
    while (!job.isReady) {
      job.advance(maxParts: 7);
    }
    job.takeMetrics();
    expect(fixture.cache.activeLeases, 0);
  });

  test('empty base is a native font strut, not fabricated readable source', () {
    final fixture = RubySegmentFixture();
    addTearDown(fixture.close);
    final word = fixture.request().spans[2].request;
    fixture.releaseGlyphs();
    final request = ForumBodyRubySegmentRequest(
      bases: [ForumBodyTextRequest.paragraph(fixture.empty)],
      sides: [ForumBodyRubySide.over],
      spans: [
        (
          request: word,
          startColumn: 0,
          endColumn: 1,
          annotationIndex: 0,
          gap: 0.0,
        ),
      ],
    );
    final cache = ForumBodyParagraphCache(
      maxEntries: 1,
      maxEstimatedBytes: 1 << 24,
    );
    addTearDown(cache.close);
    final job = ForumBodyRubySegmentMetricsPreparation(
      cache: cache,
      request: request,
      ensureOwner: () {},
    );
    addTearDown(job.close);
    while (!job.isReady) {
      job.advance(maxParts: 1);
      expect(cache.activeLeases, lessThanOrEqualTo(1));
    }
    final metrics = job.takeMetrics();
    expect(metrics.columns.single.size.width, 0);
    expect(
      metrics.level.baseAscent + metrics.level.baseDescent,
      greaterThan(0),
    );
    expect(metrics.spans.single.metrics.hasAnnotation, isTrue);
    expect(request.nativeHandleCount, 2);
    expect(fixture.empty.isSourceFree, isTrue);
    expect(fixture.empty.projection.text, isEmpty);
    expect(cache.activeLeases, 0);
    expect(cache.pictureBuildCount, 0);
  });

  test(
    'foreign pin pressure waits on the same cursor and resumes after release',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final request = fixture.request();
      fixture.releaseGlyphs();
      final cache = ForumBodyParagraphCache(
        maxEntries: 1,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(cache.close);
      final foreign = cache.acquire(content: fixture.bases.first, width: 300);
      final before = cache.layoutBuildCount;
      final job = ForumBodyRubySegmentMetricsPreparation(
        cache: cache,
        request: request,
        ensureOwner: () {},
      );
      addTearDown(job.close);
      try {
        expect(job.advance(maxParts: 1).waitingForLayoutBudget, isTrue);
        expect(job.lastBudgetRejection, isNotNull);
        expect(job.advance(maxParts: 1).waitingForLayoutBudget, isTrue);
        expect(job.preparedColumnCount, 0);
        expect(cache.layoutBuildCount, before);
      } finally {
        foreign.release();
      }
      while (!job.isReady) {
        job.advance(maxParts: 7);
      }
      job.takeMetrics();
      expect(cache.activeLeases, 0);
    },
  );

  for (final ready in [false, true]) {
    test(
      'cancel or generation retirement releases current glyph, ready=$ready',
      () {
        final fixture = RubySegmentFixture(dense: true);
        addTearDown(fixture.close);
        final request = fixture.request();
        fixture.releaseGlyphs();
        var retired = false;
        final job = ForumBodyRubySegmentMetricsPreparation(
          cache: fixture.cache,
          request: request,
          ensureOwner: () {
            if (retired) throw StateError('retired');
          },
        );
        addTearDown(job.close);
        if (ready) {
          while (!job.isReady) {
            job.advance(maxParts: 32);
          }
        } else {
          job.advance(maxParts: 1);
          expect(fixture.cache.activeLeases, 1);
        }
        retired = true;
        expect(
          () => ready ? job.takeMetrics() : job.advance(maxParts: 1),
          throwsStateError,
        );
        expect(job.nativeLeases, isEmpty);
        expect(fixture.cache.activeLeases, 0);
        expect(job.state, ForumBodyRubySegmentMetricsPreparationState.failed);
      },
    );
  }

  test(
    'owner cancellation inside a native scaler cannot leak a late acquired lease',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final request = fixture.request();
      fixture.releaseGlyphs();
      late ForumBodyRubySegmentMetricsPreparation job;
      job = ForumBodyRubySegmentMetricsPreparation(
        cache: fixture.cache,
        request: request,
        ensureOwner: () {},
        textScaler: _Scaler((size) {
          job.close();
          return size;
        }),
      );
      expect(() => job.advance(maxParts: 1), throwsStateError);
      expect(fixture.cache.activeLeases, 0);
      expect(job.nativeLeases, isEmpty);
    },
  );

  test(
    'band failure identifies its original request without retrying or retaining pins',
    () {
      final fixture = RubySegmentFixture(lineHeight: .25);
      addTearDown(fixture.close);
      final request = fixture.request().mapRequests(
        (request) => request is ForumBodyTextBandChildRequest
            ? ForumBodyTextRequest.bandChild(
                band: request.band,
                childIndex: request.childIndex,
                gutter: 1,
              )
            : request,
      );
      fixture.releaseGlyphs();
      final job = ForumBodyRubySegmentMetricsPreparation(
        cache: fixture.cache,
        request: request,
        ensureOwner: () {},
      );
      expect(
        () => job.advance(maxParts: 32),
        throwsA(isA<ForumBodyTextBandLayoutException>()),
      );
      expect(job.failedRequest, same(request.bases.first));
      expect(fixture.cache.activeLeases, 0);
      job.close();
      expect(job.failedRequest, isNull);
    },
  );

  test('single request paint preparation yields between shape and picture', () {
    final fixture = RubySegmentFixture();
    addTearDown(fixture.close);
    final request = fixture.request().spans.first.request;
    fixture.releaseGlyphs();
    final job = ForumBodyTextRequestPreparation(
      cache: fixture.cache,
      request: request,
      ensureOwner: () {},
      preparePaint: true,
    );
    addTearDown(job.close);
    final before = fixture.cache.layoutBuildCount;
    expect(job.advance().waiting, isFalse);
    expect(job.isReady, isFalse);
    expect(fixture.cache.layoutBuildCount, before + 1);
    expect(fixture.cache.pictureBuildCount, 0);
    job.advance();
    expect(job.isReady, isTrue);
    expect(fixture.cache.pictureBuildCount, 1);
    final lease = job.takeLease();
    expect(lease.layout.isPaintPrepared, isTrue);
    lease.release();
    expect(fixture.cache.activeLeases, 0);
  });

  test(
    'warm glyph without a picture reports a real paint miss and resumes',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final request = fixture.request().spans.first.request;
      fixture.releaseGlyphs(clear: false);
      final before = fixture.cache.layoutBuildCount;
      final job = ForumBodyTextRequestPreparation(
        cache: fixture.cache,
        request: request,
        ensureOwner: () {},
        preparePaint: true,
      );
      addTearDown(job.close);
      expect(job.advance(cachedOnly: true).cacheMiss, isTrue);
      expect(job.isReady, isFalse);
      expect(fixture.cache.activeLeases, 1);
      expect(fixture.cache.pictureBuildCount, 0);
      job.advance();
      final lease = job.takeLease();
      expect(fixture.cache.layoutBuildCount, before);
      expect(fixture.cache.pictureBuildCount, 1);
      lease.release();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  for (final owned in [false, true]) {
    test(
      'single span distinguishes foreign pressure from owned budget, $owned',
      () {
        final fixture = RubySegmentFixture();
        addTearDown(fixture.close);
        final request = fixture.request().spans.first.request;
        fixture.releaseGlyphs();
        final cache = ForumBodyParagraphCache(
          maxEntries: 1,
          maxEstimatedBytes: 1 << 24,
        );
        addTearDown(cache.close);
        final prefix = cache.acquire(content: fixture.bases.first, width: 300);
        addTearDown(prefix.release);
        final job = ForumBodyTextRequestPreparation(
          cache: cache,
          request: request,
          ensureOwner: () {},
          preparePaint: false,
          additionalOwnedLeases: () => [if (owned) prefix],
        );
        addTearDown(job.close);
        final before = cache.layoutBuildCount;
        if (owned) {
          expect(
            job.advance,
            throwsA(
              isA<ForumBodyParagraphBudgetException>().having(
                (e) => e.failure,
                'failure',
                ForumBodyParagraphBudgetFailure.content,
              ),
            ),
          );
          expect(cache.layoutBuildCount, before);
          expect(prefix.isActive, isTrue);
        } else {
          expect(job.advance().waiting, isTrue);
          expect(job.lastBudgetRejection, isNotNull);
          final sameRevision = job.advance();
          expect(sameRevision.waiting, isTrue);
          expect(sameRevision.units, 0);
          expect(cache.layoutBuildCount, before);
          prefix.release();
          job.advance();
          expect(job.isReady, isTrue);
          job.takeLease().release();
          expect(cache.activeLeases, 0);
        }
      },
    );
  }

  test(
    'cancellation in the actual span phase releases a late acquired glyph',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final request = fixture.request();
      fixture.releaseGlyphs();
      var cancel = false;
      late ForumBodyRubySegmentMetricsPreparation job;
      job = ForumBodyRubySegmentMetricsPreparation(
        cache: fixture.cache,
        request: request,
        ensureOwner: () {},
        textScaler: _Scaler((size) {
          if (cancel) job.close();
          return size;
        }),
      );
      addTearDown(job.close);
      while (job.preparedColumnCount < request.bases.length) {
        job.advance(maxParts: 1);
      }
      expect(job.preparedSpanCount, 0);
      expect(fixture.cache.activeLeases, 0);
      fixture.cache.clearUnpinned();
      cancel = true;
      expect(() => job.advance(maxParts: 1), throwsStateError);
      expect(fixture.cache.activeLeases, 0);
      expect(job.nativeLeases, isEmpty);
    },
  );

  test(
    'single request scaler cancellation releases even a lease returned after close',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final request = fixture.request().spans.first.request;
      fixture.releaseGlyphs();
      late ForumBodyTextRequestPreparation job;
      job = ForumBodyTextRequestPreparation(
        cache: fixture.cache,
        request: request,
        ensureOwner: () {},
        preparePaint: false,
        textScaler: _Scaler((size) {
          job.close();
          return size;
        }),
      );
      expect(() => job.advance(), throwsStateError);
      expect(fixture.cache.activeLeases, 0);
      expect(job.nativeLeases, isEmpty);
    },
  );

  test(
    'request vectors and mappings retain actual source identity and all native slots',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final request = fixture.request();
      final bases = request.bases.toList();
      final sides = request.sides.toList();
      final spans = request.spans.toList();
      final copy = ForumBodyRubySegmentRequest(
        bases: bases,
        sides: sides,
        spans: spans,
      );
      bases.clear();
      sides.clear();
      spans.clear();
      expect(copy.nativeHandleCount, 6);
      expect(() => copy.nativeRequests.clear(), throwsUnsupportedError);
      final mapped = copy.mapRequests(
        (request) => ForumBodyTextRequest.paragraph(request.content),
      );
      expect(
        mapped.nativeRequests.map((r) => r.content),
        copy.nativeRequests.map((r) => r.content),
      );
      expect(
        () => ForumBodyRubySegmentRequest(
          bases: [copy.bases.first, copy.bases.first],
          sides: copy.sides,
          spans: copy.spans,
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
    },
  );
}

final class _Scaler extends TextScaler {
  const _Scaler(this.callback);
  final double Function(double) callback;
  @override
  double scale(double fontSize) => callback(fontSize);
  @override
  double get textScaleFactor => 1;
}
