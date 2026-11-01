import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_paragraph_view.dart'
    show ForumBodyInlineViewAssembly;

import '../pagination/test_support/layer_page_preparation_fixture.dart';
import '../pagination/test_support/mixed_page_preparation_fixture.dart';
import 'test_support/ruby_segment_fixture.dart';

ForumBodyInlineSpanContent _fresh(ForumBodyInlineSpanContent source) =>
    ForumBodyInlineSpanContent.compose(
      identity: source.identity,
      path: source.path,
      fontRevision: source.fontRevision,
      styleRevision: source.styleRevision,
      style: source.style,
      contexts: source.contexts.map((w) => w.content).toList(),
      atomicRanges: [
        for (final atom in source.projection.atoms)
          (startUtf16: atom.displayStartUtf16, endUtf16: atom.displayEndUtf16),
      ],
    );

({
  ForumBodyInlineViewAssembly job,
  ForumBodyInlineSpanContent content,
  ForumBodyInlineParagraphLease parent,
  ForumBodyRubySegmentLayout segment,
})
_segment(RubySegmentFixture fixture, {void Function()? ensureOwner}) {
  final segment = fixture.prepare(fixture.compose());
  final content = fixture.inlineContent;
  final parent = fixture.cache.acquireInline(
    content: content,
    width: 300,
    dimensions: [segment.metrics.placeholderDimensions],
  );
  return (
    job: ForumBodyInlineViewAssembly(
      cache: fixture.cache,
      parent: parent,
      startLine: 0,
      endLine: parent.layout.lines.length,
      rubySegments: {0: segment},
      ensureOwner: ensureOwner,
    ),
    content: content,
    parent: parent,
    segment: segment,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final q in [1, 7, 32]) {
    for (final span in [false, true]) {
      test(
        'actual 100-rank ${span ? 'segment' : 'column'} View source binding obeys q=$q',
        () {
          late ForumBodyParagraphCache cache;
          late ForumBodyInlineViewAssembly job;
          late ForumBodyInlineSpanContent content;
          late int members;
          late int expectedUnits;
          if (span) {
            final fixture = RubySegmentFixture(dense: true);
            addTearDown(fixture.close);
            final input = _segment(fixture);
            cache = fixture.cache;
            job = input.job;
            content = input.content;
            members = 103;
            expectedUnits =
                408; // init +102 contexts +atom +2*(base+100 ranks)+100 spans+binding+publish.
          } else {
            final fixture = LayerPagePreparationFixture();
            addTearDown(fixture.close);
            cache = fixture.cache;
            content = _fresh(fixture.raw.content);
            final prepare = ForumBodyRubyGroupPreparation.fromLayerRequests(
              cache: cache,
              base: fixture.column.base,
              annotations: fixture.column.annotations,
              ensureOwner: () {},
            );
            addTearDown(prepare.close);
            while (!prepare.isReady) {
              prepare.advance();
            }
            final group = prepare.takeLayout();
            final parent = cache.acquireInline(
              content: content,
              width: 300,
              dimensions: [group.placeholderDimensions],
            );
            job = ForumBodyInlineViewAssembly(
              cache: cache,
              parent: parent,
              startLine: 0,
              endLine: parent.layout.lines.length,
              rubyGroups: {0: group},
            );
            members = 102;
            expectedUnits =
                208; // Includes the two actual empty ordinary edge contexts.
          }
          addTearDown(job.close);
          expect(content.isContextIndexReady, isFalse);
          final before = (
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            cache.activeLeases,
          );
          var units = 0;
          for (var i = 0; !job.isReady && i < 30000; i++) {
            final step = job.advance(maxParts: q);
            expect(step, inInclusiveRange(1, q));
            units += step;
            expect((
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.activeLeases,
            ), before);
          }
          expect(job.isReady, isTrue);
          expect(units, expectedUnits);
          expect(job.workCount, units);
          expect(job.preparedAtomCount, 1);
          final view = job.takeView();
          addTearDown(view.close);
          expect(job.nativeLeases, isEmpty);
          expect(view.nativeLeases.length, members);
          final last = content.contexts.lastWhere(
            (window) => window.content.projection.text.isNotEmpty,
          );
          final box = view
              .selectionBoxes(last.startUtf16 + 1, last.startUtf16 + 2)
              .single;
          final hit = view.sourceAt(
            Offset(box.left + .001, (box.top + box.bottom) / 2),
          );
          expect(hit.isExact, isTrue);
          expect(
            hit.sourceRune,
            last.content.projection.sourceAtUtf16(1).sourceRune,
          );
          expect((
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            cache.activeLeases,
          ), before);
          job.close();
          expect(view.isActive, isTrue);
          view.close();
          expect(cache.activeLeases, 0);
        },
      );
    }
  }

  for (final at in [1, 55, 200, 408]) {
    test(
      'generation retirement at source binding unit $at releases only supplied ownership',
      () {
        final fixture = RubySegmentFixture(dense: true);
        addTearDown(fixture.close);
        var retired = false;
        final input = _segment(
          fixture,
          ensureOwner: () {
            if (retired) throw StateError('retired');
          },
        );
        final job = input.job;
        addTearDown(job.close);
        final unrelated = fixture.cache.acquire(
          content: fixture.bases.first,
          width: 300,
        );
        addTearDown(unrelated.release);
        while (job.workCount < at) {
          job.advance(maxParts: 1);
        }
        retired = true;
        expect(
          () => job.isReady ? job.takeView() : job.advance(maxParts: 1),
          throwsStateError,
        );
        expect(job.nativeLeases, isEmpty);
        expect(fixture.cache.activeLeases, 1);
        expect(unrelated.isActive, isTrue);
      },
    );
  }

  test(
    'late unconsumed annotation lease failure cannot publish or leak its prefix',
    () {
      final fixture = RubySegmentFixture(dense: true);
      addTearDown(fixture.close);
      final input = _segment(fixture);
      addTearDown(input.job.close);
      input.job.advance(maxParts: 7);
      input.segment.inspectMembers().spans.last.lease!.release();
      expect(
        () {
          for (var i = 0; !input.job.isReady && i < 30000; i++) {
            input.job.advance(maxParts: 1);
          }
        },
        throwsA(
          isA<ForumBodyInlineViewException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyInlineViewFailure.leases,
          ),
        ),
      );
      expect(input.job.preparedAtomCount, 0);
      expect(fixture.cache.activeLeases, 0);
    },
  );

  for (final reenter in [false, true]) {
    test(
      'callback ${reenter ? 'reentrance' : 'close'} cannot deliver a partial source binding',
      () {
        final fixture = RubySegmentFixture(dense: true);
        addTearDown(fixture.close);
        late ForumBodyInlineViewAssembly job;
        final input = _segment(
          fixture,
          ensureOwner: () {
            if (reenter) {
              job.advance(maxParts: 1);
            } else {
              job.close();
            }
          },
        );
        job = input.job;
        addTearDown(job.close);
        expect(() => job.advance(maxParts: 32), throwsStateError);
        expect(fixture.cache.activeLeases, 0);
        expect(job.nativeLeases, isEmpty);
      },
    );
  }

  test(
    'a cancelled index prefix is reusable and incomplete atom coverage stays invalid',
    () {
      final fixture = RubySegmentFixture(dense: true);
      addTearDown(fixture.close);
      final content = fixture.inlineContent;
      expect(() => content.openAtomicContexts(0), throwsStateError);
      expect(content.prepareContextIndex(maxContexts: 7), 7);
      expect(content.isContextIndexReady, isFalse);
      final windows = content.resolveAtomicContexts(0, [
        ...fixture.bases,
        ...fixture.annotations,
      ]);
      expect(windows.length, 102);
      expect(content.isContextIndexReady, isTrue);
      expect(content.prepareContextIndex(maxContexts: 7), 0);
      final cursor = content.openAtomicContexts(0);
      cursor.resolve(fixture.bases.first);
      cursor.close();
      expect(() => cursor.resolve(fixture.bases.last), throwsStateError);
      expect(
        () => content.resolveAtomicContexts(0, fixture.bases),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
    },
  );

  for (final q in [1, 7, 32]) {
    test(
      'actual page carries remaining q=$q through group and final View binding',
      () {
        final fixture = LayerPagePreparationFixture();
        addTearDown(fixture.close);
        for (final warm in [false, true]) {
          final job = fixture.open(fixture.columnPage);
          final before = (
            fixture.cache.layoutBuildCount,
            fixture.cache.pictureBuildCount,
          );
          var calls = 0;
          for (; !job.isReady && calls < 30000; calls++) {
            final step = job.advance(maxFragments: 32, maxParts: q);
            expect(
              step.partsPrepared + step.partsInspected,
              lessThanOrEqualTo(q),
            );
            expect(
              step.layoutsBuilt + step.picturesBuilt,
              lessThanOrEqualTo(1),
            );
            expect(step.waitingForLayoutBudget, isFalse);
            expect(step.madeProgress, isTrue);
          }
          expect(job.isReady, isTrue);
          expect(calls, greaterThan(100 ~/ q));
          if (warm) {
            expect((
              fixture.cache.layoutBuildCount,
              fixture.cache.pictureBuildCount,
            ), before);
          }
          job.takeFragments().single.close();
          expect(fixture.cache.activeLeases, 0);
        }
      },
    );
  }

  test(
    'cache-only page binds gradually without acquiring a complete column in one unit',
    () {
      final fixture = MixedPagePreparationFixture();
      addTearDown(fixture.close);
      final cold = fixture.open(0);
      fixture.finish(cold);
      for (final fragment in cold.takeFragments()) {
        fragment.close();
      }
      final before = (
        fixture.cache.layoutBuildCount,
        fixture.cache.pictureBuildCount,
      );
      final warm = fixture.open(0);
      var calls = 0;
      while (!warm.isReady && calls++ < 30000) {
        final leases = fixture.cache.activeLeases;
        warm.tryPrepareCached(maxParts: 1);
        expect(warm.cacheMiss, isFalse);
        expect(fixture.cache.activeLeases - leases, inInclusiveRange(0, 1));
        expect((
          fixture.cache.layoutBuildCount,
          fixture.cache.pictureBuildCount,
        ), before);
      }
      expect(warm.isReady, isTrue);
      expect(calls, greaterThan(20));
      warm.takeFragments().single.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );
  test(
    'late current-context substitution fails after its bounded original prefix',
    () {
      final fixture = RubySegmentFixture(dense: true);
      addTearDown(fixture.close);
      final segment = fixture.prepare(fixture.compose());
      final original = fixture.inlineContent;
      final tail = fixture.annotations.last;
      final changed = tail.displayWindow(
        startUtf16: 0,
        endUtf16: tail.projection.text.length,
      );
      final content = ForumBodyInlineSpanContent.compose(
        identity: original.identity,
        path: original.path,
        fontRevision: original.fontRevision,
        styleRevision: original.styleRevision,
        style: original.style,
        contexts: [...fixture.bases, ...fixture.annotations.take(99), changed],
        atomicRanges: [
          (startUtf16: 0, endUtf16: original.projection.display.text.length),
        ],
      );
      final parent = fixture.cache.acquireInline(
        content: content,
        width: 300,
        dimensions: [segment.metrics.placeholderDimensions],
      );
      final job = ForumBodyInlineViewAssembly(
        cache: fixture.cache,
        parent: parent,
        startLine: 0,
        endLine: parent.layout.lines.length,
        rubySegments: {0: segment},
      );
      addTearDown(job.close);
      expect(
        () {
          for (var i = 0; !job.isReady && i < 30000; i++) {
            job.advance(maxParts: 1);
          }
        },
        throwsA(
          isA<ForumBodyInlineViewException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyInlineViewFailure.identity,
          ),
        ),
      );
      expect(job.workCount, greaterThan(300));
      expect(job.preparedAtomCount, 0);
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'member-map mutation cannot change transferred assembly input or ownership',
    () {
      final fixture = RubySegmentFixture();
      addTearDown(fixture.close);
      final segment = fixture.prepare(fixture.compose());
      final parent = fixture.cache.acquireInline(
        content: fixture.inlineContent,
        width: 300,
        dimensions: [segment.metrics.placeholderDimensions],
      );
      final supplied = {0: segment};
      final job = ForumBodyInlineViewAssembly(
        cache: fixture.cache,
        parent: parent,
        startLine: 0,
        endLine: parent.layout.lines.length,
        rubySegments: supplied,
      );
      addTearDown(job.close);
      supplied.clear();
      while (!job.isReady) {
        job.advance(maxParts: 1);
      }
      final view = job.takeView();
      expect(view.atomIndices, [0]);
      expect(view.nativeLeases.length, 7);
      view.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );
}
