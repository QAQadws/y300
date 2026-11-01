import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_soft_space_row_fixture.dart';

void _finish(
  ForumBodyRubySoftSpacePreparation job,
  ForumBodyParagraphCache cache,
  int q,
) {
  for (var i = 0; !job.isReady && i < 30000; i++) {
    final step = job.advance(maxParts: q);
    expect(step.formatUnitsPrepared, inInclusiveRange(1, q));
    expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
    expect(step.waitingForLayoutBudget, isFalse);
  }
  expect(job.isReady, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final q in [1, 7, 32]) {
    for (final banded in [false, true]) {
      test(
        'actual member metrics and visible preparation share bounded text worker q=$q banded=$banded',
        () {
          final f = RubySoftSpaceRowFixture(
            baseGap: true,
            ranks: 3,
            gapSize: 40,
          );
          addTearDown(f.close);
          final cache = ForumBodyParagraphCache(
            maxEntries: 8,
            maxEstimatedBytes: 1 << 24,
          );
          addTearDown(cache.close);
          final band = ForumBodyTextBandContent(
            contexts: f.softSpace.nativeRequests.map((r) => r.content).toList(),
          );
          final request = banded
              ? f.softSpace.mapRequests(
                  (r) => ForumBodyTextRequest.bandChild(
                    band: band,
                    childIndex: band.contexts.indexOf(r.content),
                  ),
                )
              : f.softSpace;
          final metricsJob = ForumBodyRubySoftSpacePreparation.forMetrics(
            cache: cache,
            request: request,
            ensureOwner: () {},
          );
          expect(metricsJob.tryPrepareCached(maxParts: q), isFalse);
          expect(metricsJob.cacheMiss, isTrue);
          expect(cache.layoutBuildCount, 0);
          while (!metricsJob.isReady) {
            final step = metricsJob.advance(maxParts: q);
            expect(step.formatUnitsPrepared, inInclusiveRange(1, q));
            expect(step.layoutsBuilt, lessThanOrEqualTo(1));
            expect(step.picturesBuilt, 0);
            expect(cache.activeLeases, 0);
          }
          expect(() => metricsJob.takeLayout(), throwsStateError);
          final metrics = metricsJob.takeMetrics();
          expect(metrics.members.length, 4);
          expect(metrics.level.baseAscent, greaterThan(0));
          expect(metrics.size.width, closeTo(f.spaceMetrics.size.width, 1e-4));
          final job = ForumBodyRubySoftSpacePreparation.fromRequests(
            cache: cache,
            request: request,
            metrics: metrics,
            ensureOwner: () {},
          );
          _finish(job, cache, q);
          expect(() => job.takeMetrics(), throwsStateError);
          final layout = job.takeLayout();
          expect(layout.isOwnedBy(cache), isTrue);
          expect(layout.nativeLeases.length, 4);
          expect(layout.contents, request.nativeRequests.map((r) => r.content));
          for (final (i, member) in metrics.members.indexed) {
            final bounds = member.input.font.bounds.shift(member.offset);
            final hit = layout.sourceAt(bounds.center);
            expect(hit.memberIndex, i);
            expect(
              hit.position.sourceRune,
              inInclusiveRange(
                layout.contents[i].projection.sourceAtUtf16(0).sourceRune,
                layout.contents[i].projection
                    .sourceAtUtf16(layout.contents[i].projection.text.length)
                    .sourceRune,
              ),
            );
            final actual = layout.selectionBoxes(
              memberIndex: i,
              startUtf16: 0,
              endUtf16: layout.contents[i].projection.text.length,
            );
            final raw = layout
                .memberAt(i)
                .layout
                .selectionBoxes(0, layout.contents[i].projection.text.length);
            expect(
              actual.map((b) => b.toRect()),
              raw.map((b) => b.toRect().shift(member.offset)),
            );
          }
          expect(
            layout.sourceAt(const Offset(-100, -100)).position.isExact,
            isFalse,
          );
          layout.close();
          expect(layout.contents, isEmpty);
          expect(cache.activeLeases, 0);
          final before = (cache.layoutBuildCount, cache.pictureBuildCount);
          final warm = ForumBodyRubySoftSpacePreparation.fromRequests(
            cache: cache,
            request: request,
            metrics: metrics,
            ensureOwner: () {},
          );
          while (!warm.isReady) {
            warm.tryPrepareCached(maxParts: q);
          }
          expect((cache.layoutBuildCount, cache.pictureBuildCount), before);
          warm.takeLayout().close();
          metricsJob.close();
          job.close();
          warm.close();
          cache.close();
          expect(cache.estimatedRetainedBytes, 0);
        },
      );
    }
  }

  test(
    'visible gap waits on external pins and resumes the same original member',
    () {
      final f = RubySoftSpaceRowFixture(baseGap: true, ranks: 3, gapSize: 40);
      addTearDown(f.close);
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(cache.close);
      final foreign = f.columns.first.base.acquire(
        cache,
        width: 2000,
        textScaler: TextScaler.noScaling,
        cachedOnly: false,
      )!;
      final job = ForumBodyRubySoftSpacePreparation.fromRequests(
        cache: cache,
        request: f.softSpace,
        metrics: f.spaceMetrics,
        ensureOwner: () {},
      );
      addTearDown(job.close);
      for (var i = 0; !job.waitingForLayoutBudget && i < 30000; i++) {
        job.advance(maxParts: 1);
      }
      expect(job.waitingForLayoutBudget, isTrue);
      expect(job.isReady, isFalse);
      expect(foreign.isActive, isTrue);
      final original = job.currentRequest;
      final before = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        job.workCount,
      );
      for (var i = 0; i < 3; i++) {
        expect(job.advance(maxParts: 7).waitingForLayoutBudget, isTrue);
        expect(job.currentRequest, same(original));
        expect((
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          job.workCount,
        ), before);
      }
      foreign.release();
      _finish(job, cache, 7);
      job.takeLayout().close();
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'owned prefix plus whole gap fails intrinsic budget without waiting or stealing aliases',
    () {
      final f = RubySoftSpaceRowFixture(baseGap: true, ranks: 3, gapSize: 40);
      addTearDown(f.close);
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(cache.close);
      final prefix = f.columns.first.base.acquire(
        cache,
        width: 2000,
        textScaler: TextScaler.noScaling,
        cachedOnly: false,
      )!;
      final job = ForumBodyRubySoftSpacePreparation.fromRequests(
        cache: cache,
        request: f.softSpace,
        metrics: f.spaceMetrics,
        ensureOwner: () {},
        additionalOwnedLeases: () => [prefix],
      );
      expect(() {
        for (var i = 0; !job.isReady && i < 30000; i++) {
          job.advance(maxParts: 1);
        }
      }, throwsA(isA<ForumBodyParagraphBudgetException>()));
      expect(job.state, ForumBodyRubySoftSpacePreparationState.failed);
      expect(job.waitingForLayoutBudget, isFalse);
      expect(prefix.isActive, isTrue);
      expect(cache.activeLeases, 1);
      prefix.release();
      job.close();
    },
  );

  for (final phase in [0, 1, 4]) {
    test(
      'cancel visible preparation releases only its current ownership phase=$phase',
      () {
        final f = RubySoftSpaceRowFixture(baseGap: true, ranks: 3, gapSize: 40);
        addTearDown(f.close);
        final cache = ForumBodyParagraphCache(
          maxEntries: 8,
          maxEstimatedBytes: 1 << 24,
        );
        addTearDown(cache.close);
        final alias = f.softSpace.nativeRequests.first.acquire(
          cache,
          width: 16384,
          textScaler: TextScaler.noScaling,
          cachedOnly: false,
        )!;
        final job = ForumBodyRubySoftSpacePreparation.fromRequests(
          cache: cache,
          request: f.softSpace,
          metrics: f.spaceMetrics,
          ensureOwner: () {},
        );
        while (job.preparedPartCount < phase) {
          job.advance(maxParts: 1);
        }
        job.close();
        expect(alias.isActive, isTrue);
        expect(cache.activeLeases, 1);
        expect(job.nativeLeases, isEmpty);
        expect(() => job.advance(maxParts: 1), throwsStateError);
        alias.release();
      },
    );
  }

  test(
    'late font mismatch retires current member and never publishes stale geometry',
    () {
      final f = RubySoftSpaceRowFixture(baseGap: true, ranks: 3, gapSize: 40);
      final other = RubySoftSpaceRowFixture(
        baseGap: true,
        ranks: 3,
        gapSize: 80,
      );
      addTearDown(f.close);
      addTearDown(other.close);
      final cache = ForumBodyParagraphCache(
        maxEntries: 8,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(cache.close);
      final job = ForumBodyRubySoftSpacePreparation.fromRequests(
        cache: cache,
        request: other.softSpace,
        metrics: f.spaceMetrics,
        ensureOwner: () {},
      );
      expect(
        () => _finish(job, cache, 1),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      expect(job.state, ForumBodyRubySoftSpacePreparationState.failed);
      expect(cache.activeLeases, 0);
      expect(() => job.takeLayout(), throwsStateError);
    },
  );

  test(
    'actual band failure identifies its original gap member and releases pins',
    () {
      final f = RubySoftSpaceRowFixture(
        baseGap: true,
        ranks: 3,
        gapSize: 40,
        lineHeight: .25,
      );
      addTearDown(f.close);
      final cache = ForumBodyParagraphCache(
        maxEntries: 8,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(cache.close);
      final band = ForumBodyTextBandContent(
        contexts: f.softSpace.nativeRequests.map((r) => r.content).toList(),
      );
      final request = f.softSpace.mapRequests(
        (r) => ForumBodyTextRequest.bandChild(
          band: band,
          childIndex: band.contexts.indexOf(r.content),
          gutter: 1,
        ),
      );
      final job = ForumBodyRubySoftSpacePreparation.forMetrics(
        cache: cache,
        request: request,
        ensureOwner: () {},
      );
      expect(
        () => job.advance(maxParts: 32),
        throwsA(isA<ForumBodyTextBandLayoutException>()),
      );
      expect(job.failedRequest, same(request.nativeRequests.first));
      expect(cache.activeLeases, 0);
      job.close();
      expect(job.failedRequest, isNull);
    },
  );

  test('metrics can stream real members through a single-entry owner', () {
    final f = RubySoftSpaceRowFixture(baseGap: true, ranks: 3, gapSize: 40);
    addTearDown(f.close);
    final cache = ForumBodyParagraphCache(
      maxEntries: 1,
      maxEstimatedBytes: 1 << 24,
    );
    addTearDown(cache.close);
    final job = ForumBodyRubySoftSpacePreparation.forMetrics(
      cache: cache,
      request: f.softSpace,
      ensureOwner: () {},
    );
    _finish(job, cache, 1);
    expect(job.takeMetrics().members.length, 4);
    expect(cache.activeLeases, 0);
    expect(cache.layoutBuildCount, 4);
  });
}
