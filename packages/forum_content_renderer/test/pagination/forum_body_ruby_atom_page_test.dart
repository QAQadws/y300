import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_annotation_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_annotation_pairing.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_group_metrics.dart'
    show ForumBodyRubyLevelUnion;
import 'package:forum_content_renderer/src/inline/forum_body_ruby_row_alignment.dart';

import '../inline/test_support/ruby_segment_fixture.dart';
import 'test_support/ruby_atom_page_fixture.dart';

List<ForumBodyRubyGroupContent> _readRubyGroups(
  ForumBodyDocument document,
  ForumBodyReaderStyle reader,
) {
  final flow = ForumBodyStyledFlowCursor(document: document, reader: reader);
  final groups = <ForumBodyRubyGroupContent>[];
  try {
    while (flow.moveNext()) {
      if (flow.current!.phase != ForumBodyFlowPhase.open ||
          flow.current!.node is! ForumBodyElement ||
          (flow.current!.node as ForumBodyElement).kind !=
              ForumBodyElementKind.ruby) {
        continue;
      }
      final cursor = ForumBodyRubyContentCursor.openCurrent(flow);
      try {
        while (!cursor.isComplete) {
          if (cursor.advance(maxEvents: 1).hasOutput) {
            groups.add(cursor.current!);
          }
        }
      } finally {
        cursor.close();
      }
    }
  } finally {
    flow.close();
  }
  return groups;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final q in [1, 7, 32]) {
    for (final dense in [false, true]) {
      test(
        'actual spanning requests pass Composer and cold/warm Page job q=$q dense=$dense',
        () {
          final fixture = RubyAtomPageFixture.segment(dense: dense);
          addTearDown(fixture.close);
          final expected = dense ? 103 : 7;
          final job = fixture.open(0);
          expect(job.expectedNativeLeaseCount, expected);
          expect(job.tryPrepareCached(maxParts: 1), isFalse);
          expect(job.cacheMiss, isTrue);
          expect(fixture.cache.layoutBuildCount, 0);
          fixture.finish(job, q: q);
          expect(fixture.transfers, 0);
          final fragment =
              job.takeFragments().single as ForumBodyPreparedInlineFragment;
          expect(fragment.nativeLeases.length, expected);
          expect(fragment.view.atomIndices, [0]);
          expect(fixture.cache.pictureBuildCount, dense ? 102 : 6);
          final window = fixture.input.content.contexts.last;
          final box = fragment
              .glyphBoxes(window.startUtf16 + 1, window.startUtf16 + 2)
              .single;
          final hit = fragment.view.sourceAt(
            Offset(box.left + .001, (box.top + box.bottom) / 2),
          );
          expect(
            hit.sourceRune,
            window.content.projection.sourceAtUtf16(1).sourceRune,
          );
          expect(hit.isExact, isTrue);
          fragment.close();
          expect(fixture.cache.activeLeases, 0);
          final counts = (
            fixture.cache.layoutBuildCount,
            fixture.cache.pictureBuildCount,
          );
          final warm = fixture.open(0);
          for (var i = 0; !warm.isReady && i < 30000; i++) {
            final leases = fixture.cache.activeLeases;
            warm.tryPrepareCached(maxParts: 1);
            expect(warm.cacheMiss, isFalse);
            expect(fixture.cache.activeLeases - leases, inInclusiveRange(0, 1));
            expect((
              fixture.cache.layoutBuildCount,
              fixture.cache.pictureBuildCount,
            ), counts);
          }
          expect(warm.isReady, isTrue);
          warm.takeFragments().single.close();
          expect(fixture.cache.activeLeases, 0);
        },
      );
    }
  }

  testWidgets(
    'existing PageSurface paints and taps an original span and releases on unmount',
    (tester) async {
      final fixture = RubyAtomPageFixture.segment();
      addTearDown(fixture.close);
      final job = fixture.open(0);
      fixture.finish(job);
      final fragments = job.takeFragments();
      final view = (fragments.single as ForumBodyPreparedInlineFragment).view;
      final counts = (
        fixture.cache.layoutBuildCount,
        fixture.cache.pictureBuildCount,
      );
      final hits = <int>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: ForumBodyTextPageSurface.prepared(
              snapshot: fixture.snapshot,
              pageIndex: 0,
              layoutId: fixture.snapshot.layoutId,
              fragments: fragments,
              onSourceTap: (_, position) => hits.add(position.sourceRune),
            ),
          ),
        ),
      );
      final window = fixture.input.content.contexts[4];
      final box = view
          .selectionBoxes(window.startUtf16 + 1, window.startUtf16 + 2)
          .single;
      await tester.tapAt(
        tester.getTopLeft(find.byType(ForumBodyInlineParagraphSurface)) +
            Offset(box.left + .1, (box.top + box.bottom) / 2),
      );
      expect(hits, [window.content.projection.sourceAtUtf16(1).sourceRune]);
      expect((
        fixture.cache.layoutBuildCount,
        fixture.cache.pictureBuildCount,
      ), counts);
      await tester.pumpWidget(const SizedBox());
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'RTL scaled tight leading uses the same native requests and parent coordinates',
    () {
      final fixture = RubyAtomPageFixture.segment(
        direction: TextDirection.rtl,
        lineHeight: .25,
        textScaler: const TextScaler.linear(1.27),
      );
      addTearDown(fixture.close);
      final job = fixture.open(0);
      fixture.finish(job, q: 1);
      final fragment =
          job.takeFragments().single as ForumBodyPreparedInlineFragment;
      for (final window in fixture.input.content.contexts) {
        final box = fragment
            .glyphBoxes(window.startUtf16, window.endUtf16)
            .first;
        expect(box.top, greaterThanOrEqualTo(-1e-4));
        expect(box.bottom, lessThanOrEqualTo(fragment.view.height + 1e-4));
      }
      fragment.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'prefix/continuation pages acquire only visible atoms and keep physical coverage',
    () {
      final fixture = RubyAtomPageFixture.segment(
        dense: true,
        surrounding: true,
      );
      addTearDown(fixture.close);
      expect(fixture.snapshot.length, greaterThan(1));
      expect(fixture.atomPage, greaterThan(0));
      final prefix = fixture.open(0);
      fixture.finish(prefix, q: 1);
      expect(prefix.expectedNativeLeaseCount, 1);
      expect(fixture.cache.pictureBuildCount, 0);
      prefix.takeFragments().single.close();
      final job = fixture.open(fixture.atomPage);
      fixture.finish(job, q: 1);
      final fragment =
          job.takeFragments().single as ForumBodyPreparedInlineFragment;
      expect(fragment.nativeLeases.length, 103);
      expect(fragment.view.startLine, greaterThan(0));
      final window = fixture.input.content.contexts[5];
      final box = fragment
          .glyphBoxes(window.startUtf16 + 1, window.startUtf16 + 2)
          .single;
      expect(
        fragment.view
            .sourceAt(Offset(box.left + .001, (box.top + box.bottom) / 2))
            .isExact,
        isTrue,
      );
      fragment.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'complete component and whole-page foreign-pin probes are bounded and resume in place',
    () {
      final fixture = RubyAtomPageFixture.segment(dense: true, entries: 3);
      addTearDown(fixture.close);
      final foreign = fixture.cache.acquire(
        content: fixture.source!.bases.first,
        width: 300,
      );
      addTearDown(foreign.release);
      final job = fixture.open(0);
      var inspected = 0;
      for (var i = 0; !job.waitingForLayoutBudget && i < 30000; i++) {
        final step = job.advance(maxFragments: 32, maxParts: 1);
        expect(step.partsPrepared + step.partsInspected, lessThanOrEqualTo(1));
        expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
        inspected += step.partsInspected;
      }
      expect(job.waitingForLayoutBudget, isTrue);
      expect(inspected, 103);
      final before = (
        fixture.cache.layoutBuildCount,
        fixture.cache.pictureBuildCount,
      );
      final stable = job.advance(maxFragments: 32, maxParts: 7);
      expect(stable.waitingForLayoutBudget, isTrue);
      expect(stable.partsPrepared + stable.partsInspected, 0);
      expect((
        fixture.cache.layoutBuildCount,
        fixture.cache.pictureBuildCount,
      ), before);
      foreign.release();
      fixture.finish(job, q: 1);
      job.takeFragments().single.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  for (final hiddenByForeign in [false, true]) {
    test(
      'intrinsic page overflow cannot wait or retain pins, foreign=$hiddenByForeign',
      () {
        final fixture = RubyAtomPageFixture.segment(
          dense: !hiddenByForeign,
          individual: hiddenByForeign,
          entries: hiddenByForeign ? 4 : 2,
        );
        addTearDown(fixture.close);
        final foreign = hiddenByForeign
            ? fixture.cache.acquire(
                content: fixture.source!.bases.first,
                width: 300,
                textScaler: const TextScaler.linear(2),
              )
            : null;
        addTearDown(() => foreign?.release());
        final job = fixture.open(0);
        expect(
          () {
            for (var i = 0; !job.isReady && i < 30000; i++) {
              expect(
                job
                    .advance(maxFragments: 32, maxParts: 1)
                    .waitingForLayoutBudget,
                isFalse,
              );
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
        expect(fixture.cache.activeLeases, hiddenByForeign ? 1 : 0);
        expect(fixture.transfers, 0);
      },
    );
  }

  for (final ready in [false, true]) {
    test(
      'owner retirement releases parent, prepared component and binding, ready=$ready',
      () {
        final fixture = RubyAtomPageFixture.segment(dense: true);
        addTearDown(fixture.close);
        var retired = false;
        final job = fixture.open(
          0,
          ensureOwner: () {
            if (retired) throw StateError('retired');
          },
        );
        if (ready) {
          fixture.finish(job);
        } else {
          while (fixture.cache.activeLeases < 103) {
            job.advance(maxFragments: 32, maxParts: 1);
          }
          expect(job.isReady, isFalse);
        }
        retired = true;
        expect(
          () => ready
              ? job.takeFragments()
              : job.advance(maxFragments: 32, maxParts: 1),
          throwsStateError,
        );
        expect(fixture.cache.activeLeases, 0);
        expect(fixture.transfers, 0);
      },
    );
  }

  test(
    'canonical atom input is immutable and column-only access cannot hide spans',
    () {
      final fixture = RubyAtomPageFixture.segment();
      addTearDown(fixture.close);
      final plan = fixture.input.rubyAtoms.single as ForumBodyRubySegmentPlan;
      expect(plan.nativeHandleCount, 6);
      expect(() => fixture.input.rubyAtoms.clear(), throwsUnsupportedError);
      expect(() => fixture.input.rubyGroups, throwsStateError);
      expect(() => fixture.input.rubyLevelMetrics, throwsStateError);
      final changed = ForumBodyRubySegmentRequest(
        bases: plan.request.bases,
        sides: plan.request.sides,
        spans: plan.request.spans,
        direction: TextDirection.rtl,
      );
      expect(
        () => ForumBodyRubyAtomPlan.segment(
          request: changed,
          metrics: plan.metrics,
        ),
        throwsArgumentError,
      );
      expect(fixture.cache.layoutBuildCount, 0);
    },
  );

  test(
    'one actual paragraph mixes a legacy column and a connected spanning atom',
    () {
      final document = const ForumBodyParser().parse(
        html:
            '<p><ruby><rb style="font-size:30px">A</rb><rt>x</rt></ruby><ruby><rb>B</rb><rb>C</rb><rtc>xyz</rtc></ruby></p>',
        sourceId: 'mixed-atom-page',
        conversionIdentity: 'none',
      );
      final reader = ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
        fontRevision: 'mixed-atom',
        linkColor: const Color(0xff0000ff),
      );
      final groups = _readRubyGroups(document, reader);
      expect(groups.length, 2);
      expect(groups.first.rootPath, isNot(groups.last.rootPath));
      final base =
          ((groups.first.base.single as ForumBodyRubyBaseContent).parts.single
                  as ForumBodyRubyTextContent)
              .content;
      final rt =
          (groups.first.annotations.single.parts.single
                  as ForumBodyRubyTextContent)
              .content;
      final bases = [
        for (final rb in groups.last.base.cast<ForumBodyRubyBaseContent>())
          (rb.parts.single as ForumBodyRubyTextContent).content,
      ];
      final pairing = ForumBodyRubyAnnotationPairing(
        group: groups.last,
        baseColumnCount: 2,
      );
      expect(pairing.hasMultiColumnSpans, isTrue);
      final span = pairing.levels.single.spans.single;
      final annotation =
          (span.box as ForumBodyRubyAnonymousAnnotationInput).content;
      final contexts = [base, rt, ...bases, annotation];
      final band = ForumBodyTextBandContent(contexts: contexts);
      ForumBodyTextRequest request(ForumBodyParagraphContent c) =>
          ForumBodyTextRequest.bandChild(
            band: band,
            childIndex: contexts.indexOf(c),
          );
      final column = ForumBodyRubyColumnRequest(
        base: request(base),
        annotation: request(rt),
      );
      final segment = ForumBodyRubySegmentRequest(
        bases: bases.map(request).toList(),
        sides: [pairing.levels.single.side],
        spans: [
          (
            request: request(annotation),
            startColumn: span.startColumn,
            endColumn: span.endColumn,
            annotationIndex: 0,
            gap: 0.0,
          ),
        ],
      );
      final planning = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(planning.close);
      final columnMeasure = ForumBodyRubyGroupPreparation.forMetrics(
        cache: planning,
        base: column.base,
        annotation: column.annotation,
        ensureOwner: () {},
      );
      addTearDown(columnMeasure.close);
      while (!columnMeasure.isReady) {
        columnMeasure.advance(maxParts: 1);
      }
      final columnMetrics = columnMeasure.takeMetrics();
      final spanMeasure = ForumBodyRubySegmentMetricsPreparation(
        cache: planning,
        request: segment,
        ensureOwner: () {},
      );
      addTearDown(spanMeasure.close);
      while (!spanMeasure.isReady) {
        spanMeasure.advance(maxParts: 1);
      }
      final metrics = spanMeasure.takeMetrics();
      final roots = groups.map((group) => group.rootPath).toSet().toList();
      final atoms = [
        ForumBodyRubyAtomMetrics.column(columnMetrics),
        ForumBodyRubyAtomMetrics.segment(metrics),
      ];
      // Merging these actual fonts WOULD move annotation baselines. Distinct
      // parsed roots must therefore stay isolated even on the same parent row.
      final union = ForumBodyRubyLevelUnion();
      for (final atom in atoms) {
        final merge = union.mergeAtom(atom);
        while (!merge.isComplete) {
          merge.advance(maxParts: 1);
        }
      }
      expect(metrics.needsLevelAlignment(union.value), isTrue);
      final row = ForumBodyRubyRowAlignment.atoms(
        atoms: atoms,
        levelIds: [for (final group in groups) roots.indexOf(group.rootPath)],
        atomOffsets: [0, 1],
      );
      while (!row.isComplete && !row.needsRows) {
        expect(row.advance(maxParts: 1), 1);
      }
      expect(row.isComplete, isTrue);
      expect(row.hasChanges, isFalse);
      final styles = const ForumBodyStyleResolver().resolve(document, reader);
      final content = ForumBodyInlineSpanContent.compose(
        identity: document.identity,
        path: '0',
        fontRevision: styles.fontRevision,
        styleRevision: styles.resolverRevision,
        style: styles.byPath['0']!,
        contexts: contexts,
        atomicRanges: [
          (startUtf16: 0, endUtf16: 2),
          (startUtf16: 2, endUtf16: 7),
        ],
      );
      final input = ForumBodyInlinePageContent.atoms(
        content: content,
        dimensions: row.dimensions,
        rubyAtoms: [
          ForumBodyRubyAtomPlan.column(request: column),
          ForumBodyRubyAtomPlan.segment(request: segment, metrics: metrics),
        ],
      );
      final fixture = RubyAtomPageFixture.compose(
        input: input,
        planning: planning,
        entries: 2,
      );
      addTearDown(fixture.close);
      final job = fixture.open(0);
      fixture.finish(job, q: 1);
      final fragment =
          job.takeFragments().single as ForumBodyPreparedInlineFragment;
      expect(job.expectedNativeLeaseCount, 6);
      expect(fragment.view.atomIndices, [0, 1]);
      expect(fixture.cache.pictureBuildCount, 5);
      for (final window in content.contexts) {
        final box = fragment
            .glyphBoxes(window.startUtf16, window.startUtf16 + 1)
            .first;
        expect(
          fragment.view
              .sourceAt(Offset(box.left + .001, (box.top + box.bottom) / 2))
              .sourceRune,
          window.content.projection.sourceAtUtf16(0).sourceRune,
        );
      }
      fragment.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'actual orphan annotation page retains its empty font strut and missing rank',
    () {
      final document = const ForumBodyParser().parse(
        html: '<p><ruby><rtc>word</rtc><rtc></rtc></ruby></p>',
        sourceId: 'orphan-atom-page',
        conversionIdentity: 'none',
      );
      final reader = ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
        fontRevision: 'orphan-atom',
        linkColor: const Color(0xff0000ff),
      );
      final group = _readRubyGroups(document, reader).single;
      final pairing = ForumBodyRubyAnnotationPairing(
        group: group,
        baseColumnCount: 0,
      );
      final original = pairing.levels.first.spans.single;
      final annotation =
          (original.box as ForumBodyRubyAnonymousAnnotationInput).content;
      final empty = ForumBodyParagraphContent.anonymousInline(
        identity: group.identity,
        fontRevision: group.fontRevision,
        styleRevision: group.styleRevision,
        style: group.style,
      );
      final band = ForumBodyTextBandContent(contexts: [annotation]);
      final request = ForumBodyRubySegmentRequest(
        bases: [ForumBodyTextRequest.paragraph(empty)],
        sides: pairing.levels.map((level) => level.side).toList(),
        spans: [
          (
            request: ForumBodyTextRequest.bandChild(band: band, childIndex: 0),
            startColumn: original.startColumn,
            endColumn: original.endColumn,
            annotationIndex: 0,
            gap: 0.0,
          ),
        ],
      );
      final planning = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 24,
      );
      addTearDown(planning.close);
      final measure = ForumBodyRubySegmentMetricsPreparation(
        cache: planning,
        request: request,
        ensureOwner: () {},
      );
      addTearDown(measure.close);
      while (!measure.isReady) {
        measure.advance(maxParts: 1);
      }
      final metrics = measure.takeMetrics();
      final styles = const ForumBodyStyleResolver().resolve(document, reader);
      final content = ForumBodyInlineSpanContent.compose(
        identity: document.identity,
        path: '0',
        fontRevision: styles.fontRevision,
        styleRevision: styles.resolverRevision,
        style: styles.byPath['0']!,
        contexts: [annotation],
        atomicRanges: [(startUtf16: 0, endUtf16: 4)],
      );
      final input = ForumBodyInlinePageContent.atoms(
        content: content,
        dimensions: [metrics.placeholderDimensions],
        rubyAtoms: [
          ForumBodyRubyAtomPlan.segment(request: request, metrics: metrics),
        ],
      );
      final fixture = RubyAtomPageFixture.compose(
        input: input,
        planning: planning,
        entries: 3,
      );
      addTearDown(fixture.close);
      final job = fixture.open(0);
      fixture.finish(job, q: 1);
      final fragment =
          job.takeFragments().single as ForumBodyPreparedInlineFragment;
      expect(fragment.nativeLeases.length, 3);
      expect(request.sides.length, 2);
      expect(fixture.cache.pictureBuildCount, 1);
      final box = fragment.glyphBoxes(1, 2).single;
      expect(
        fragment.view
            .sourceAt(Offset(box.left + .01, (box.top + box.bottom) / 2))
            .isExact,
        isTrue,
      );
      expect(
        fragment.view
            .sourceAt(Offset(metrics.size.width / 2, fragment.view.height - 1))
            .isExact,
        isFalse,
      );
      fragment.close();
      expect(fixture.cache.activeLeases, 0);
    },
  );

  test(
    'cancelling a partial whole-page probe releases component pins and keeps foreign ownership',
    () {
      final fixture = RubyAtomPageFixture.segment(dense: true, entries: 3);
      addTearDown(fixture.close);
      final foreign = fixture.cache.acquire(
        content: fixture.source!.bases.first,
        width: 300,
      );
      addTearDown(foreign.release);
      final job = fixture.open(0);
      var inspected = false;
      for (var i = 0; !inspected && i < 30000; i++) {
        inspected =
            job.advance(maxFragments: 32, maxParts: 1).partsInspected > 0;
      }
      expect(inspected, isTrue);
      expect(job.waitingForLayoutBudget, isFalse);
      job.close();
      expect(fixture.cache.activeLeases, 1);
      expect(foreign.isActive, isTrue);
      expect(fixture.retirements, 1);
    },
  );

  test(
    'a numeric component cannot be paired with altered parent dimensions',
    () {
      final fixture = RubyAtomPageFixture.segment();
      addTearDown(fixture.close);
      final original = fixture.input.dimensions.single;
      expect(
        () => ForumBodyInlinePageContent.atoms(
          content: fixture.input.content,
          rubyAtoms: fixture.input.rubyAtoms,
          dimensions: [
            PlaceholderDimensions(
              size: original.size + const Offset(1, 0),
              alignment: original.alignment,
              baseline: original.baseline,
              baselineOffset: original.baselineOffset,
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(fixture.cache.layoutBuildCount, 0);
    },
  );

  for (final bandTail in [false, true]) {
    test(
      'current source and complete band-tail admission cannot be bypassed, band=$bandTail',
      () {
        final fixture = RubyAtomPageFixture.segment(surrounding: bandTail);
        addTearDown(fixture.close);
        final plan = fixture.input.rubyAtoms.single as ForumBodyRubySegmentPlan;
        final source = fixture.source!;
        late ForumBodyInlineSpanContent content;
        var request = plan.request;
        if (bandTail) {
          final prefix = fixture.input.content.contexts.first.content;
          final band = ForumBodyTextBandContent(
            contexts: [prefix, source.bases.first],
          );
          request = request.mapRequests(
            (r) => identical(r.content, source.bases.first)
                ? ForumBodyTextRequest.bandChild(band: band, childIndex: 1)
                : r,
          );
          final original = fixture.input.content;
          content = ForumBodyInlineSpanContent.compose(
            identity: original.identity,
            path: original.path,
            fontRevision: original.fontRevision,
            styleRevision: original.styleRevision,
            style: original.style,
            contexts: [...source.bases, ...source.annotations],
            atomicRanges: [
              (
                startUtf16: 0,
                endUtf16: [
                  ...source.bases,
                  ...source.annotations,
                ].fold<int>(0, (sum, c) => sum + c.projection.text.length),
              ),
            ],
          );
        } else {
          final current = RubySegmentFixture();
          addTearDown(current.close);
          content = current.inlineContent;
        }
        expect(
          () => ForumBodyInlinePageContent.atoms(
            content: content,
            dimensions: fixture.input.dimensions,
            rubyAtoms: [
              ForumBodyRubyAtomPlan.segment(
                request: request,
                metrics: plan.metrics,
              ),
            ],
          ),
          throwsA(
            isA<ForumBodyParagraphInputException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphInputFailure.identity,
            ),
          ),
        );
        expect(fixture.cache.layoutBuildCount, 0);
      },
    );
  }
}
