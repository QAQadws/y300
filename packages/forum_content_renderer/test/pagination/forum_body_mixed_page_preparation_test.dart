import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/pagination/forum_body_text_page_preparation.dart'
    show createForumBodyTextPagePreparation;

import 'test_support/mixed_page_preparation_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'cold shared-band page prepares one native operation per unit and delivers only complete views',
    (tester) async {
      final input = MixedPagePreparationFixture();
      addTearDown(input.close);
      final prepare = input.open(0);
      expect(prepare.expectedNativeLeaseCount, 7);
      expect(prepare.tryPrepareCached(), isFalse);
      expect(input.cache.layoutBuildCount, 0);
      expect(input.cache.pictureBuildCount, 0);
      final steps = input.finish(prepare);
      expect(
        steps.every((step) => step.layoutsBuilt + step.picturesBuilt <= 1),
        isTrue,
      );
      expect(steps.every((step) => step.madeProgress), isTrue);
      expect(input.cache.layoutBuildCount, 2);
      expect(input.cache.pictureBuildCount, 1);
      expect(input.cache.activeLeases, 7);
      expect(input.transfers, 0);
      expect(prepare.takeLeases, throwsStateError);
      expect(prepare.isReady, isTrue);
      final fragments = prepare.takeFragments();
      expect(input.transfers, 1);
      expect(fragments.single.nativeLeases.length, 7);
      final binding = fragments.single as ForumBodyPreparedInlineFragment;
      expect(binding.view.atomIndices, [0, 1, 2]);
      final hits = <int>[];
      final builds = input.cache.layoutBuildCount;
      final pictures = input.cache.pictureBuildCount;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: ForumBodyTextPageSurface.prepared(
              snapshot: input.snapshot,
              pageIndex: 0,
              layoutId: input.snapshot.layoutId,
              fragments: fragments,
              onSourceTap: (_, position) => hits.add(position.sourceRune),
            ),
          ),
        ),
      );
      final window = input.content.contexts[5];
      final box = binding.view
          .selectionBoxes(window.startUtf16, window.startUtf16 + 1)
          .first;
      await tester.tapAt(
        tester.getTopLeft(find.byType(ForumBodyInlineParagraphSurface)) +
            Offset(box.left + .1, (box.top + box.bottom) / 2),
      );
      expect(hits, [window.content.projection.sourceAtUtf16(0).sourceRune]);
      expect(input.cache.layoutBuildCount, builds);
      expect(input.cache.pictureBuildCount, pictures);
      await tester.pumpWidget(const SizedBox());
      expect(input.cache.activeLeases, 0);
    },
  );

  test(
    'a continuation records only its one visible group rather than the whole parent',
    () {
      final input = MixedPagePreparationFixture();
      addTearDown(input.close);
      final prepare = input.open(1);
      expect(prepare.expectedNativeLeaseCount, 3);
      input.finish(prepare);
      expect(input.cache.pictureBuildCount, 1);
      expect(input.cache.layoutBuildCount, 2);
      final binding =
          prepare.takeFragments().single as ForumBodyPreparedInlineFragment;
      expect(binding.view.atomIndices, [3]);
      expect(
        binding.view.coverageStartUtf16,
        input.content.projection.atoms[3].displayStartUtf16,
      );
      expect(binding.view.selectionBoxes(0, 1), isEmpty);
      binding.close();
      expect(input.cache.activeLeases, 0);
    },
  );

  test(
    'cached-only lookup and warm group work are bounded without shaping or recording',
    () {
      final input = MixedPagePreparationFixture();
      addTearDown(input.close);
      final first = input.open(0);
      input.finish(first);
      for (final fragment in first.takeFragments()) {
        fragment.close();
      }
      final builds = input.cache.layoutBuildCount;
      final pictures = input.cache.pictureBuildCount;
      final warm = input.open(0);
      expect(warm.tryPrepareCached(maxParts: 1), isFalse);
      expect(input.cache.activeLeases, 1);
      var calls = 0;
      while (!warm.isReady && calls++ < 1000) {
        final leases = input.cache.activeLeases;
        warm.tryPrepareCached(maxParts: 1);
        expect(input.cache.activeLeases - leases, inInclusiveRange(0, 1));
      }
      expect(warm.isReady, isTrue);
      expect(calls, greaterThan(10));
      expect(input.cache.layoutBuildCount, builds);
      expect(input.cache.pictureBuildCount, pictures);
      warm.takeFragments().single.close();
    },
  );

  test(
    'foreign pressure waits after a bounded whole-page probe and resumes the same parent',
    () {
      final input = MixedPagePreparationFixture();
      addTearDown(input.close);
      final foreign = input.cache.acquire(
        content: input.contexts.last,
        width: 100,
      );
      final prepare = input.open(0);
      var work = 0;
      while (!prepare.waitingForLayoutBudget) {
        expect(work++, lessThan(30));
        final step = prepare.advance(maxFragments: 1, maxParts: 1);
        expect(step.partsInspected, lessThanOrEqualTo(1));
      }
      expect(input.cache.layoutBuildCount, 2); // Foreign + current parent.
      expect(input.cache.pictureBuildCount, 0);
      expect(foreign.isActive, isTrue);
      foreign.release();
      input.finish(prepare, maxParts: 1);
      expect(input.cache.layoutBuildCount, 3);
      expect(input.cache.pictureBuildCount, 1);
      prepare.takeFragments().single.close();
    },
  );

  test(
    'own sibling pins are intrinsic pressure and cannot become an external wait',
    () {
      final input = MixedPagePreparationFixture(batched: false, entries: 3);
      addTearDown(input.close);
      final prepare = input.open(0);
      Object? rejection;
      for (var i = 0; i < 50; i++) {
        try {
          final step = prepare.advance(maxFragments: 1, maxParts: 1);
          expect(step.waitingForLayoutBudget, isFalse);
        } catch (error) {
          rejection = error;
          break;
        }
      }
      expect(rejection, isA<ForumBodyTextPagePreparationException>());
      expect(prepare.state, ForumBodyTextPagePreparationState.failed);
      expect(input.cache.activeLeases, 0);
    },
  );

  test(
    'whole-page probe rejects future sibling footprint even while a real foreign pin stays visible',
    () {
      final input = MixedPagePreparationFixture(batched: false, entries: 4);
      addTearDown(input.close);
      final foreign = input.cache.acquire(
        content: input.contexts.last,
        width: 100,
      );
      final prepare = input.open(0);
      Object? rejection;
      for (var i = 0; i < 50; i++) {
        try {
          prepare.advance(maxFragments: 1, maxParts: 1);
        } catch (error) {
          rejection = error;
          break;
        }
      }
      expect(rejection, isA<ForumBodyTextPagePreparationException>());
      expect(prepare.state, ForumBodyTextPagePreparationState.failed);
      expect(foreign.isActive, isTrue);
      expect(input.cache.activeLeases, 1);
      foreign.release();
    },
  );

  test(
    'closing or losing a generation between units releases all partial mixed handles',
    () {
      final input = MixedPagePreparationFixture();
      addTearDown(input.close);
      var current = true;
      final prepare = input.open(
        0,
        ensureOwner: () {
          if (!current) throw StateError('Retired test generation');
        },
      );
      prepare.advance(maxFragments: 1);
      expect(input.cache.activeLeases, 1);
      current = false;
      expect(() => prepare.advance(maxFragments: 1), throwsStateError);
      expect(prepare.state, ForumBodyTextPagePreparationState.failed);
      expect(input.cache.activeLeases, 0);
      final other = input.open(0);
      other.advance(maxFragments: 1, maxParts: 1);
      other.close();
      expect(input.cache.activeLeases, 0);
    },
  );

  test(
    'retirement in Picture.onCreate cannot publish or leak a partial child',
    () {
      final input = MixedPagePreparationFixture();
      addTearDown(input.close);
      final prepare = input.open(0);
      prepare.advance(maxFragments: 1);
      prepare.advance(maxFragments: 1);
      final previous = ui.Picture.onCreate;
      ui.Picture.onCreate = (_) => prepare.close();
      try {
        expect(() => prepare.advance(maxFragments: 1), throwsStateError);
      } finally {
        ui.Picture.onCreate = previous;
      }
      expect(prepare.state, ForumBodyTextPagePreparationState.closed);
      expect(input.cache.activeLeases, 0);
      expect(input.cache.preparedPictureCount, 0);
    },
  );

  test(
    'empty annotations neither reserve native handles nor record blank upper rows',
    () {
      final input = MixedPagePreparationFixture(
        emptyAnnotations: true,
        height: 20,
      );
      addTearDown(input.close);
      final prepare = input.open(0);
      expect(prepare.expectedNativeLeaseCount, 4);
      input.finish(prepare);
      expect(input.cache.pictureBuildCount, 1);
      final binding =
          prepare.takeFragments().single as ForumBodyPreparedInlineFragment;
      expect(binding.view.height, 20);
      expect(binding.nativeLeases.length, 4);
      binding.close();
    },
  );

  for (final childOnly in [false, true]) {
    test(
      'changed native scaling rejects planned geometry and a fresh request can retry (child=$childOnly)',
      () {
        final input = MixedPagePreparationFixture();
        addTearDown(input.close);
        final prefix = input.snapshot.first;
        final prepare = input.open(
          0,
          textScaler: childOnly
              ? const AnnotationScaler()
              : TextScaler.linear(2),
        );
        Object? failure;
        for (var i = 0; i < 50 && !prepare.isReady; i++) {
          try {
            prepare.advance(maxFragments: 1);
          } catch (error) {
            failure = error;
            break;
          }
        }
        expect(
          failure,
          childOnly
              ? isA<ForumBodyInlineViewException>()
              : isA<ForumBodyTextPageSurfaceException>(),
        );
        expect(prepare.state, ForumBodyTextPagePreparationState.failed);
        expect(input.transfers, 0);
        expect(input.cache.activeLeases, 0);
        expect(input.snapshot.first, same(prefix));
        final retry = input.open(0);
        input.finish(retry);
        retry.takeFragments().single.close();
        expect(input.cache.activeLeases, 0);
      },
    );
  }

  for (final intrinsic in [false, true]) {
    test(
      'empty mixed native frame has no synthetic selection or precise source proof (intrinsic=$intrinsic)',
      () {
        final document = const ForumBodyParser().parse(
          html: '<p></p>',
          sourceId: 'empty-mixed-frame',
          conversionIdentity: 'none',
        );
        final styles = const ForumBodyStyleResolver().resolve(
          document,
          ForumBodyReaderStyle(
            textStyle: const TextStyle(
              fontFamily: 'Ahem',
              fontSize: 20,
              height: 1,
            ),
            fontRevision: 'loaded',
            linkColor: const Color(0xff0000ff),
          ),
        );
        final content = ForumBodyInlineSpanContent.compose(
          identity: document.identity,
          path: '0',
          fontRevision: styles.fontRevision,
          styleRevision: styles.resolverRevision,
          style: styles.byPath['0']!,
          contexts: [],
          atomicRanges: [],
        );
        final cache = ForumBodyParagraphCache(
          maxEntries: 2,
          maxEstimatedBytes: 1 << 20,
        );
        addTearDown(cache.close);
        final mode = intrinsic
            ? ForumBodyParagraphLayoutMode.intrinsicSingleLine
            : ForumBodyParagraphLayoutMode.wrap;
        final composer = ForumBodyTextPageComposer(
          identity: document.identity,
          layoutId: 'empty-frame',
          width: 60,
          height: 40,
          maxPages: 10,
          maxFragments: 10,
        );
        addTearDown(composer.close);
        composer.appendInline(
          lease: cache.acquireInline(
            content: content,
            width: 60,
            dimensions: [],
            layoutMode: mode,
          ),
          paragraphIndex: 0,
          left: 0,
          spaceBefore: 0,
          spaceAtPageStart: 0,
        );
        while (!composer.needsInput) {
          composer.advance(maxLines: 1);
        }
        composer.finish();
        expect(composer.snapshot.single.fragments.single.sourceHint, isNull);
        final prepare = createForumBodyTextPagePreparation(
          cache: cache,
          snapshot: composer.snapshot,
          pageIndex: 0,
          inputs: [
            ForumBodyInlinePageContent(
              content: content,
              dimensions: [],
              rubyGroups: [],
              layoutMode: mode,
            ),
          ],
          textScaler: TextScaler.noScaling,
          ensureOwner: () {},
          onTransfer: (_, _) {},
          onRetire: (_) {},
        );
        addTearDown(prepare.close);
        expect(prepare.tryPrepareCached(), isTrue);
        final binding =
            prepare.takeFragments().single as ForumBodyPreparedInlineFragment;
        expect(binding.view.selectionBoxes(0, 0), isEmpty);
        expect(binding.view.sourceAt(Offset.zero).isExact, isFalse);
        expect(cache.pictureBuildCount, 0);
        binding.close();
        expect(cache.activeLeases, 0);
      },
    );
  }

  test('generation guards cannot reenter the active page operation', () {
    final input = MixedPagePreparationFixture();
    addTearDown(input.close);
    late ForumBodyTextPagePreparation prepare;
    var attempted = false;
    prepare = input.open(
      0,
      ensureOwner: () {
        if (!attempted) {
          attempted = true;
          expect(() => prepare.advance(maxFragments: 1), throwsStateError);
        }
      },
    );
    input.finish(prepare, maxParts: 1);
    expect(attempted, isTrue);
    prepare.takeFragments().single.close();
    expect(input.cache.activeLeases, 0);
  });
}

final class AnnotationScaler extends TextScaler {
  const AnnotationScaler();
  @override
  double scale(double size) => size == 10 ? 20 : size;
  @override
  double get textScaleFactor => 1;
}
