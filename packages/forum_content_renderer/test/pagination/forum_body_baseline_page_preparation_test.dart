import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_page_preparation_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final batched in [false, true]) {
    testWidgets(
      'baseline atoms use actual page sources and local copy (band: $batched)',
      (tester) async {
        final fixture = MixedPagePreparationFixture(
          baselineShifts: [-4, 8, -4, 8],
          batched: batched,
          width: 80,
          height: 40,
          entries: 8,
        );
        addTearDown(fixture.close);
        expect(fixture.snapshot.length, greaterThan(1));
        final visited = <int>{};
        for (var page = 0; page < fixture.snapshot.length; page++) {
          final job = fixture.open(page);
          final steps = fixture.finish(job, maxParts: 1);
          expect(
            steps.every((s) => s.layoutsBuilt + s.picturesBuilt <= 1),
            isTrue,
          );
          final fragments = job.takeFragments();
          final binding = fragments.single as ForumBodyPreparedInlineFragment;
          final metadata = fixture.snapshot[page].fragments.single;
          final builds = fixture.cache.layoutBuildCount;
          final pictures = fixture.cache.pictureBuildCount;
          final hits = <int>[];
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: Align(
                alignment: Alignment.topLeft,
                child: ForumBodyTextPageSurface.prepared(
                  snapshot: fixture.snapshot,
                  pageIndex: page,
                  layoutId: fixture.snapshot.layoutId,
                  fragments: fragments,
                  onSourceTap: (_, position) => hits.add(position.sourceRune),
                ),
              ),
            ),
          );
          final origin = tester.getTopLeft(
            find.byType(ForumBodyInlineParagraphSurface),
          );
          for (final index in binding.view.atomIndices) {
            visited.add(index);
            final context = fixture.content.contexts[index * 2];
            final box = binding
                .glyphBoxes(context.startUtf16, context.startUtf16 + 1)
                .single;
            final point = Offset(
              box.left + (box.right - box.left) * .25,
              (box.top + box.bottom) * .5,
            );
            expect(box.top, greaterThanOrEqualTo(0));
            expect(box.bottom, lessThanOrEqualTo(metadata.height));
            final copy = forumBodyTextSelectionAt(
              binding: binding,
              fragment: metadata,
              pageSize: Size(fixture.snapshot.width, fixture.snapshot.height),
              point: point,
            )!;
            expect(copy.text, 'b$index');
            expect(copy.isAnnotation, isFalse);
            expect(copy.isCode, isFalse);
            expect(
              copy.position.sourceRune,
              context.content.projection.sourceAtUtf16(0).sourceRune,
            );
            await tester.tapAt(origin + point);
            expect(hits.last, copy.position.sourceRune);
          }
          expect(fixture.cache.layoutBuildCount, builds);
          expect(fixture.cache.pictureBuildCount, pictures);
          await tester.pumpWidget(const SizedBox.shrink());
          expect(fixture.cache.activeLeases, 0);
        }
        expect(visited, {0, 1, 2, 3});
      },
    );

    test('warm baseline page does no native work (band: $batched)', () {
      final fixture = MixedPagePreparationFixture(
        baselineShifts: [-4, 8, -4, 8],
        batched: batched,
        width: 80,
        height: 40,
        entries: 8,
      );
      addTearDown(fixture.close);
      final cold = fixture.open(0);
      expect(cold.tryPrepareCached(maxParts: 1), isFalse);
      expect(fixture.cache.layoutBuildCount, 0);
      expect(fixture.cache.pictureBuildCount, 0);
      fixture.finish(cold, maxParts: 1);
      cold.takeFragments().single.close();
      final builds = fixture.cache.layoutBuildCount,
          pictures = fixture.cache.pictureBuildCount;
      final warm = fixture.open(0);
      for (var i = 0; !warm.isReady; i++) {
        expect(i, lessThan(1000));
        warm.tryPrepareCached(maxParts: 1);
      }
      expect(fixture.cache.layoutBuildCount, builds);
      expect(fixture.cache.pictureBuildCount, pictures);
      warm.takeFragments().single.close();
      expect(fixture.cache.activeLeases, 0);
    });
  }

  test(
    'cancellation at every preparation boundary releases only page ownership',
    () {
      var reachedReady = false;
      for (var stop = 0; !reachedReady; stop++) {
        expect(stop, lessThan(256));
        final fixture = MixedPagePreparationFixture(
          baselineShifts: [8, -4, 8, -4],
          height: 40,
          entries: 8,
        );
        try {
          final foreign = fixture.cache.acquire(
            content: fixture.contexts.first,
            width: 101,
          );
          final job = fixture.open(0);
          for (var work = 0; work < stop && !job.isReady; work++) {
            job.advance(maxFragments: 1, maxParts: 1);
          }
          reachedReady = job.isReady;
          job.close();
          expect(foreign.isActive, isTrue);
          expect(fixture.cache.activeLeases, 1);
          expect(fixture.transfers, 0);
          foreign.release();
        } finally {
          fixture.close();
        }
      }
      expect(reachedReady, isTrue);
    },
  );

  test(
    'changed glyph scaling cannot be delivered under old baseline geometry',
    () {
      final fixture = MixedPagePreparationFixture(
        baselineShifts: [8, -4, 8, -4],
        height: 40,
        entries: 8,
      );
      addTearDown(fixture.close);
      final job = fixture.open(0, textScaler: const TextScaler.linear(1.5));
      expect(() => fixture.finish(job, maxParts: 1), throwsA(anything));
      expect(fixture.transfers, 0);
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'external pins wait without repeated native work, then resume the same job',
    () {
      final fixture = MixedPagePreparationFixture(
        baselineShifts: [-4, 8, -4, 8],
        width: 80,
        height: 40,
        entries: 2,
      );
      addTearDown(fixture.close);
      final foreign = fixture.cache.acquire(
        content: fixture.contexts.first,
        width: 101,
      );
      final job = fixture.open(0);
      for (var i = 0; !job.waitingForLayoutBudget; i++) {
        expect(i, lessThan(1000));
        job.advance(maxFragments: 1, maxParts: 1);
      }
      final builds = fixture.cache.layoutBuildCount,
          pictures = fixture.cache.pictureBuildCount;
      for (var i = 0; i < 5; i++) {
        job.advance(maxFragments: 1, maxParts: 1);
        expect(job.waitingForLayoutBudget, isTrue);
      }
      expect(fixture.cache.layoutBuildCount, builds);
      expect(fixture.cache.pictureBuildCount, pictures);
      foreign.release();
      fixture.finish(job, maxParts: 1);
      job.takeFragments().single.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test('own baseline footprint cannot become a permanent external wait', () {
    final fixture = MixedPagePreparationFixture(
      baselineShifts: [-4, 8, -4, 8],
      width: 80,
      height: 40,
      entries: 2,
      batched: false,
    );
    addTearDown(fixture.close);
    final job = fixture.open(0);
    expect(
      () => fixture.finish(job, maxParts: 1),
      throwsA(
        isA<ForumBodyTextPagePreparationException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyTextPagePreparationFailure.intrinsicBudget,
        ),
      ),
    );
    expect(job.waitingForLayoutBudget, isFalse);
    expect(fixture.cache.activeLeases, 0);
  });

  for (final reenter in [false, true]) {
    test('ready baseline transfer rejects owner loss/reentry ($reenter)', () {
      final fixture = MixedPagePreparationFixture(
        baselineShifts: [-4, 8, -4, 8],
        width: 80,
        height: 40,
        entries: 8,
      );
      addTearDown(fixture.close);
      var transferring = false;
      late ForumBodyTextBaselinePreparation job;
      final plan =
          fixture.input.rubyAtoms.first as ForumBodyTextBaselineAtomPlan;
      job = ForumBodyTextBaselinePreparation(
        cache: fixture.cache,
        request: plan.request,
        width: plan.maxWidth,
        baselineShift: plan.metrics.baselineShift,
        textScaler: TextScaler.noScaling,
        ensureOwner: () {
          if (transferring) {
            if (reenter) {
              job.takeLayout();
            }
            throw StateError('Retired baseline owner');
          }
        },
      );
      for (var i = 0; !job.isReady; i++) {
        expect(i, lessThan(100));
        final builds = fixture.cache.layoutBuildCount,
            pictures = fixture.cache.pictureBuildCount;
        job.advance(maxParts: 1);
        expect(
          fixture.cache.layoutBuildCount -
              builds +
              fixture.cache.pictureBuildCount -
              pictures,
          lessThanOrEqualTo(1),
        );
      }
      transferring = true;
      expect(job.takeLayout, throwsStateError);
      expect(fixture.cache.activeLeases, 0);
    });
  }
}
