import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/layer_page_preparation_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'column requests preserve all ranks and legacy single construction without native work',
    () {
      final fixture = LayerPagePreparationFixture(ranks: 3);
      addTearDown(fixture.close);
      final column = fixture.column;
      expect(column.annotations.length, 3);
      expect(column.nativeHandleCount, 4);
      expect(
        column.nativeRequests.map((request) => request.content),
        fixture.raw.parts,
      );
      expect(() => column.annotations.clear(), throwsUnsupportedError);
      expect(() => column.nativeRequests.clear(), throwsUnsupportedError);
      expect(() => column.annotation, throwsStateError);
      expect(() => column.gap, throwsStateError);
      expect(() => column.side, throwsStateError);
      final pair = ForumBodyRubyPairRequest(
        base: column.base,
        annotation: column.annotations.first.request,
      );
      expect(pair, isA<ForumBodyRubyColumnRequest>());
      expect(pair.annotation, same(column.annotations.first.request));
      expect(pair.nativeHandleCount, 2);
      final mutable = column.annotations.toList();
      final copy = ForumBodyRubyColumnRequest.layers(
        base: column.base,
        annotations: mutable,
      );
      mutable.clear();
      expect(copy.annotations.length, 3);
      expect(copy.nativeHandleCount, 4);
      expect(fixture.cache.layoutBuildCount, 0);
      expect(fixture.cache.pictureBuildCount, 0);
    },
  );

  test(
    '100-rank composed page counts actual handles and hidden continuation pages borrow no children',
    () {
      final fixture = LayerPagePreparationFixture(surroundingText: true);
      addTearDown(fixture.close);
      expect(fixture.snapshot.length, greaterThanOrEqualTo(3));
      final columnPage = fixture.columnPage;
      expect(columnPage, greaterThan(0));
      for (var page = 0; page < fixture.snapshot.length; page++) {
        final pictures = fixture.cache.pictureBuildCount;
        final job = fixture.open(page);
        expect(job.expectedNativeLeaseCount, page == columnPage ? 102 : 1);
        fixture.finish(job);
        final fragments = job.takeFragments();
        expect(
          fragments.expand((fragment) => fragment.nativeLeases).length,
          job.expectedNativeLeaseCount,
        );
        expect(
          fixture.cache.pictureBuildCount - pictures,
          page == columnPage ? 101 : 0,
        );
        final view = (fragments.single as ForumBodyPreparedInlineFragment).view;
        expect(view.atomIndices, page == columnPage ? [0] : isEmpty);
        if (page == columnPage) {
          final content = fixture.raw.parts[100];
          final window = fixture.raw.content.contexts.singleWhere(
            (context) => identical(context.content, content),
          );
          final box = view
              .selectionBoxes(
                window.startUtf16,
                window.startUtf16 + 1,
                clipToView: false,
              )
              .single
              .toRect();
          expect(box.top, greaterThanOrEqualTo(-1e-4));
          expect(box.bottom, lessThanOrEqualTo(view.height + 1e-4));
          final hit = view.sourceAt(Offset(box.left + .01, box.center.dy));
          expect(hit.isExact, isTrue);
          expect(
            hit.sourceRune,
            content.projection.sourceAtUtf16(0).sourceRune,
          );
        }
        for (final fragment in fragments) {
          fragment.close();
        }
        expect(fixture.cache.activeLeases, 0);
      }
      expect(fixture.cache.entryCount, lessThanOrEqualTo(3));
    },
  );

  test(
    'cached-only page delivery retains bounded partial layer work instead of declaring a miss',
    () {
      final fixture = LayerPagePreparationFixture();
      addTearDown(fixture.close);
      final first = fixture.open(fixture.columnPage);
      fixture.finish(first);
      first.takeFragments().single.close();
      final builds = fixture.cache.layoutBuildCount;
      final pictures = fixture.cache.pictureBuildCount;
      final warm = fixture.open(fixture.columnPage);
      var calls = 0;
      while (!warm.isReady && calls++ < 1000) {
        warm.tryPrepareCached(maxParts: 1);
        expect(fixture.cache.layoutBuildCount, builds);
        expect(fixture.cache.pictureBuildCount, pictures);
      }
      expect(warm.isReady, isTrue);
      expect(calls, greaterThan(7));
      expect(fixture.transfers, 1);
      final fragment = warm.takeFragments().single;
      expect(fragment.nativeLeases.length, 102);
      expect(fixture.transfers, 2);
      fragment.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    '100 sparse ranks retain their indices but count only actual glyph handles',
    () {
      final fixture = LayerPagePreparationFixture(
        missing: true,
        emptyBase: true,
      );
      addTearDown(fixture.close);
      expect(fixture.column.annotations.length, 100);
      expect(fixture.column.nativeHandleCount, 7);
      final job = fixture.open(fixture.columnPage);
      expect(job.expectedNativeLeaseCount, 8);
      fixture.finish(job);
      final fragment =
          job.takeFragments().single as ForumBodyPreparedInlineFragment;
      expect(fragment.nativeLeases.length, 8);
      // The empty base is a real native font strut, not a recorded glyph picture.
      expect(fixture.cache.pictureBuildCount, 6);
      final last = fixture.raw.parts[86];
      final window = fixture.raw.content.contexts.singleWhere(
        (context) => identical(context.content, last),
      );
      final box = fragment
          .glyphBoxes(window.startUtf16, window.startUtf16 + 1)
          .single
          .toRect();
      expect(
        fragment.view
            .sourceAt(Offset(box.left + .01, box.center.dy))
            .sourceRune,
        last.projection.sourceAtUtf16(0).sourceRune,
      );
      fragment.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  for (final cancel in [false, true]) {
    test(
      'whole-page probe inspects parent and every rank before waiting, cancel=$cancel',
      () {
        final fixture = LayerPagePreparationFixture();
        addTearDown(fixture.close);
        final foreign = fixture.cache.acquire(
          content: fixture.raw.parts.last,
          width: 100,
        );
        addTearDown(foreign.release);
        final job = fixture.open(fixture.columnPage);
        var inspected = 0;
        for (var i = 0; !job.waitingForLayoutBudget && i < 1000; i++) {
          final step = job.advance(maxFragments: 1, maxParts: 1);
          inspected += step.partsInspected;
          expect(step.partsInspected, lessThanOrEqualTo(1));
          expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
          if (cancel && inspected > 0) break;
        }
        if (cancel) {
          expect(inspected, 1);
          job.close();
          expect(fixture.cache.activeLeases, 1);
          expect(foreign.isActive, isTrue);
        } else {
          expect(inspected, 102);
          expect(job.waitingForLayoutBudget, isTrue);
          final waiting = job.advance(maxFragments: 1, maxParts: 1);
          expect(waiting.partsInspected, 0);
          expect(waiting.madeProgress, isFalse);
          foreign.release();
          fixture.finish(job);
          job.takeFragments().single.close();
          expect(fixture.cache.activeLeases, 0);
        }
      },
    );
  }

  test(
    'aggregate parent and multi-band footprint rejects intrinsic page failure without losing foreign pins',
    () {
      final fixture = LayerPagePreparationFixture(entries: 2);
      addTearDown(fixture.close);
      final foreign = fixture.cache.acquire(
        content: fixture.raw.parts.last,
        width: 100,
      );
      addTearDown(foreign.release);
      final job = fixture.open(fixture.columnPage);
      var failed = false;
      for (var i = 0; i < 1000; i++) {
        try {
          job.advance(maxFragments: 1, maxParts: 1);
        } on ForumBodyTextPagePreparationException catch (error) {
          expect(
            error.failure,
            ForumBodyTextPagePreparationFailure.intrinsicBudget,
          );
          failed = true;
          break;
        }
      }
      expect(failed, isTrue);
      expect(job.state, ForumBodyTextPagePreparationState.failed);
      expect(foreign.isActive, isTrue);
      expect(fixture.cache.activeLeases, 1);
      expect(fixture.transfers, 0);
    },
  );

  test(
    'an old but equal outer request cannot bind a fresh retained parent',
    () {
      final fixture = LayerPagePreparationFixture(ranks: 3);
      final old = LayerPagePreparationFixture(ranks: 3);
      addTearDown(fixture.close);
      addTearDown(old.close);
      final column = ForumBodyRubyColumnRequest.layers(
        base: fixture.column.base,
        annotations: [
          fixture.column.annotations[0],
          fixture.column.annotations[1],
          old.column.annotations[2],
        ],
      );
      expect(
        () => ForumBodyInlinePageContent(
          content: fixture.raw.content,
          dimensions: fixture.input.dimensions,
          rubyGroups: [column],
        ),
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyParagraphInputFailure.identity,
          ),
        ),
      );
      expect(fixture.cache.layoutBuildCount, 0);
    },
  );

  test(
    'an outer band tail outside retained input cannot evade pure budgets',
    () {
      final fixture = LayerPagePreparationFixture(
        ranks: 3,
        surroundingText: true,
      );
      addTearDown(fixture.close);
      final tail = fixture.raw.content.contexts.last.content;
      final band = ForumBodyTextBandContent(
        contexts: [fixture.raw.parts.last, tail],
      );
      final column = ForumBodyRubyColumnRequest.layers(
        base: fixture.column.base,
        annotations: [
          fixture.column.annotations[0],
          fixture.column.annotations[1],
          (
            request: ForumBodyTextRequest.bandChild(band: band, childIndex: 0),
            gap: 0.0,
            side: ForumBodyRubySide.over,
          ),
        ],
      );
      final subset = ForumBodyInlineSpanContent.compose(
        identity: fixture.raw.content.identity,
        path: '0',
        fontRevision: fixture.raw.content.fontRevision,
        styleRevision: fixture.raw.content.styleRevision,
        style: fixture.raw.content.style,
        contexts: fixture.raw.parts,
        atomicRanges: [
          (
            startUtf16: 0,
            endUtf16: fixture.raw.parts.fold(
              0,
              (sum, part) => sum + part.projection.text.length,
            ),
          ),
        ],
      );
      expect(
        () => ForumBodyInlinePageContent(
          content: subset,
          dimensions: fixture.input.dimensions,
          rubyGroups: [column],
        ),
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyParagraphInputFailure.identity,
          ),
        ),
      );
      expect(fixture.cache.layoutBuildCount, 0);
    },
  );

  test('row targets must preserve rank count and original side sequence', () {
    final fixture = LayerPagePreparationFixture(ranks: 3);
    final short = LayerPagePreparationFixture(ranks: 1);
    final reversed = LayerPagePreparationFixture(
      ranks: 3,
      sides: List.filled(3, ForumBodyRubySide.under),
    );
    addTearDown(fixture.close);
    addTearDown(short.close);
    addTearDown(reversed.close);
    for (final metrics in [short.metrics, reversed.metrics]) {
      expect(
        () => ForumBodyInlinePageContent(
          content: fixture.raw.content,
          dimensions: fixture.input.dimensions,
          rubyGroups: [fixture.column],
          rubyLevelMetrics: [ForumBodyRubyLevelMetrics.single(metrics)],
        ),
        throwsArgumentError,
      );
    }
    expect(fixture.cache.layoutBuildCount, 0);
  });

  for (final direction in ['ltr', 'rtl']) {
    testWidgets(
      'prepared 100-rank $direction Surface routes the last RT and retires all handles',
      (tester) async {
        final fixture = LayerPagePreparationFixture(direction: direction);
        addTearDown(fixture.close);
        final page = fixture.columnPage;
        final job = fixture.open(page);
        fixture.finish(job);
        final fragments = job.takeFragments();
        final fragment = fragments.single as ForumBodyPreparedInlineFragment;
        final hits = <int>[];
        await tester.pumpWidget(
          Directionality(
            textDirection: direction == 'rtl'
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: ForumBodyTextPageSurface.prepared(
                snapshot: fixture.snapshot,
                pageIndex: page,
                layoutId: fixture.snapshot.layoutId,
                fragments: fragments,
                onSourceTap: (_, hit) {
                  if (hit.isExact) hits.add(hit.sourceRune);
                },
              ),
            ),
          ),
        );
        final content = fixture.raw.parts.last;
        final window = fixture.raw.content.contexts.singleWhere(
          (context) => identical(context.content, content),
        );
        final box = fragment
            .glyphBoxes(window.startUtf16, window.startUtf16 + 1)
            .single
            .toRect();
        final counts = (
          fixture.cache.layoutBuildCount,
          fixture.cache.pictureBuildCount,
        );
        await tester.tapAt(
          tester.getTopLeft(find.byType(ForumBodyInlineParagraphSurface)) +
              Offset(box.left + .01, box.center.dy),
        );
        await tester.pump();
        expect(hits, [content.projection.sourceAtUtf16(0).sourceRune]);
        expect((
          fixture.cache.layoutBuildCount,
          fixture.cache.pictureBuildCount,
        ), counts);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(fixture.cache.activeLeases, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
