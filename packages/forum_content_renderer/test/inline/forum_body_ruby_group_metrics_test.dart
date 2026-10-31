import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_pair_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ForumBodyParagraphCache cache;
  setUp(() {
    cache = ForumBodyParagraphCache(maxEntries: 8, maxEstimatedBytes: 1 << 22);
  });
  tearDown(() => cache.close());

  for (final tight in [false, true]) {
    test('glyph-only band metrics match readable geometry, tight=$tight', () {
      final input = rubyPairInput(
        baseLineHeight: tight ? .25 : 1,
        annotationLineHeight: tight ? .25 : 1,
      );
      final band = ForumBodyTextBandContent(
        contexts: [input.base, input.annotation],
      );
      final base = cache.acquireBandChild(content: band, childIndex: 0);
      final annotation = cache.acquireBandChild(content: band, childIndex: 1);
      addTearDown(base.release);
      addTearDown(annotation.release);
      expect(base.layout.isPaintPrepared, isFalse);
      expect(annotation.layout.isPaintPrepared, isFalse);
      final before = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      );
      final metrics = ForumBodyRubyGroupMetrics.measure(
        cache: cache,
        baseLease: base,
        annotation: input.annotation,
        annotationLease: annotation,
        gap: 2,
      );
      expect(metrics.size, const Size(40, 32));
      expect(metrics.baseOffset.dx, 0);
      expect(metrics.annotationOffset.dx, 10);
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.activeLeases,
      ), before);
      expect(metrics.hasAnnotation, isTrue);

      // Borrowed metrics cannot bypass the readable band's explicit paint gate.
      final unreadableBase = cache.acquireBandChild(
        content: band,
        childIndex: 0,
      );
      final unreadableRT = cache.acquireBandChild(content: band, childIndex: 1);
      expect(
        () => ForumBodyRubyGroupLayout.adopt(
          cache: cache,
          baseLease: unreadableBase,
          annotation: input.annotation,
          annotationLease: unreadableRT,
          gap: 2,
        ),
        throwsStateError,
      );
      expect(unreadableBase.isActive, isFalse);
      expect(unreadableRT.isActive, isFalse);
      expect(base.isActive, isTrue);
      expect(annotation.isActive, isTrue);
      expect(cache.pictureBuildCount, 0);

      cache.prepareBandChildPaint(base);
      cache.prepareBandChildPaint(annotation);
      final group = ForumBodyRubyGroupLayout.adopt(
        cache: cache,
        baseLease: base,
        annotation: input.annotation,
        annotationLease: annotation,
        gap: 2,
      );
      expect(group.metrics.size, metrics.size);
      expect(group.metrics.baseline, metrics.baseline);
      expect(group.baseOffset, metrics.baseOffset);
      expect(group.annotationOffset, metrics.annotationOffset);
      expect(
        group.metrics.annotationHitBoundary,
        metrics.annotationHitBoundary,
      );
      expect(group.placeholderDimensions, metrics.placeholderDimensions);
      expect(cache.layoutBuildCount, 1);
      expect(cache.pictureBuildCount, 2);
      group.close();
      cache.close();
      // Numeric plan data does not retain its owner or claim readable content.
      expect(metrics.placeholderDimensions.size, const Size(40, 32));
      expect(cache.activeLeases, 0);
      expect(cache.estimatedRetainedBytes, 0);
    });
  }

  test(
    'nonlinear scaling is already resolved in both numeric child bounds',
    () {
      final input = rubyPairInput();
      final band = ForumBodyTextBandContent(
        contexts: [input.base, input.annotation],
      );
      final base = cache.acquireBandChild(
        content: band,
        childIndex: 0,
        textScaler: const _Scaler(),
      );
      final annotation = cache.acquireBandChild(
        content: band,
        childIndex: 1,
        textScaler: const _Scaler(),
      );
      addTearDown(base.release);
      addTearDown(annotation.release);
      final metrics = ForumBodyRubyGroupMetrics.measure(
        cache: cache,
        baseLease: base,
        annotation: input.annotation,
        annotationLease: annotation,
      );
      expect(metrics.size, const Size(60, 55));
      expect(metrics.placeholderDimensions.baselineOffset, metrics.baseline);
      expect(cache.layoutBuildCount, 1);
      expect(cache.pictureBuildCount, 0);
    },
  );

  test('empty annotation needs no native handle and ignores the gap', () {
    final input = rubyPairInput(annotation: '');
    final base = cache.acquire(content: input.base, width: 100);
    addTearDown(base.release);
    final metrics = ForumBodyRubyGroupMetrics.measure(
      cache: cache,
      baseLease: base,
      annotation: input.annotation,
      gap: 20,
    );
    expect(metrics.size, const Size(40, 20));
    expect(metrics.baseOffset, Offset.zero);
    expect(metrics.hasAnnotation, isFalse);
    expect(cache.activeLeases, 1);
    expect(cache.layoutBuildCount, 1);
  });

  test('failed geometry borrows and preserves every caller handle', () {
    final input = rubyPairInput();
    final base = cache.acquire(content: input.base, width: 100);
    final annotation = cache.acquire(content: input.annotation, width: 100);
    addTearDown(base.release);
    addTearDown(annotation.release);
    for (final (gap, width, failure) in [
      (0.0, 30.0, ForumBodyRubyGroupFailure.overflow),
      (double.nan, 100.0, ForumBodyRubyGroupFailure.geometry),
    ]) {
      expect(
        () => ForumBodyRubyGroupMetrics.measure(
          cache: cache,
          baseLease: base,
          annotation: input.annotation,
          annotationLease: annotation,
          gap: gap,
          maxWidth: width,
        ),
        throwsA(
          isA<ForumBodyRubyGroupException>().having(
            (e) => e.failure,
            'failure',
            failure,
          ),
        ),
      );
      expect(base.isActive, isTrue);
      expect(annotation.isActive, isTrue);
      expect(cache.activeLeases, 2);
      expect(cache.pictureBuildCount, 0);
    }
  });

  test(
    'same text from an old annotation context cannot supply current metrics',
    () {
      final input = rubyPairInput();
      final old = rubyPairInput();
      final base = cache.acquire(content: input.base, width: 100);
      final stale = cache.acquire(content: old.annotation, width: 100);
      addTearDown(base.release);
      addTearDown(stale.release);
      expect(
        () => ForumBodyRubyGroupMetrics.measure(
          cache: cache,
          baseLease: base,
          annotation: input.annotation,
          annotationLease: stale,
        ),
        throwsA(
          isA<ForumBodyRubyGroupException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyRubyGroupFailure.content,
          ),
        ),
      );
      expect(base.isActive, isTrue);
      expect(stale.isActive, isTrue);
    },
  );

  test('foreign and retired owners fail without releasing another owner', () {
    final input = rubyPairInput();
    final foreign = ForumBodyParagraphCache(
      maxEntries: 2,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(foreign.close);
    final base = cache.acquire(content: input.base, width: 100);
    final rt = foreign.acquire(content: input.annotation, width: 100);
    addTearDown(base.release);
    addTearDown(rt.release);
    expect(
      () => ForumBodyRubyGroupMetrics.measure(
        cache: cache,
        baseLease: base,
        annotation: input.annotation,
        annotationLease: rt,
      ),
      throwsStateError,
    );
    expect(base.isActive, isTrue);
    expect(rt.isActive, isTrue);
    cache.close();
    expect(
      () => ForumBodyRubyGroupMetrics.measure(
        cache: cache,
        baseLease: base,
        annotation: input.annotation,
        annotationLease: rt,
      ),
      throwsStateError,
    );
    expect(rt.isActive, isTrue);
    expect(foreign.activeLeases, 1);
  });
}

final class _Scaler extends TextScaler {
  const _Scaler();
  @override
  double scale(double size) => size <= 10 ? size * 2.5 : size * 1.5;
  @override
  double get textScaleFactor => 1.5;
}
