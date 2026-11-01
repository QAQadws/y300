import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_group_metrics.dart'
    show ForumBodyRubySegmentAlignment;

import '../pagination/test_support/ruby_atom_page_fixture.dart';
import 'test_support/ruby_gap_fixture.dart';

/// Independent native painters for the real source grid. Production component,
/// gap/column offsets and target numeric dimensions are never used as a control.
Future<List<int>> _reference(RubyGapFixture f) async {
  final r = f.request;
  final contents = r.nativeRequests.map((r) => r.content).toList();
  final painters = [
    for (final c in contents)
      TextPainter(
        text: c.textSpan,
        textDirection: c.style.textDirection,
        textScaler: f.scaler,
      )..layout(),
  ];
  try {
    final bounds = [
      for (var i = 0; i < painters.length; i++)
        painters[i]
            .getBoxesForSelection(
              TextSelection(
                baseOffset: 0,
                extentOffset: contents[i].projection.text.length,
              ),
            )
            .fold(
              Rect.fromLTWH(0, 0, painters[i].width, painters[i].height),
              (Rect a, b) => a.expandToInclude(b.toRect()),
            ),
    ];
    final baseline = [
      for (final p in painters)
        p.height - p.computeLineMetrics().single.descent,
    ];
    int index(ForumBodyTextRequest request) =>
        contents.indexOf(request.content);
    final a = index(r.bases[0]);
    final b = index(r.bases[1]);
    final bg = r.gaps.isEmpty ? null : index(r.gaps.single.request);
    final ag = r.annotationGaps.isEmpty
        ? null
        : index(r.annotationGaps.single.request);
    final x = index(r.spans[0].request);
    final y = index(r.spans[1].request);
    final outer = index(r.spans[2].request);
    final edge = math.max(
      bg == null ? 0.0 : bounds[bg].width,
      ag == null ? 0.0 : bounds[ag].width,
    );
    final widths = [
      math.max(bounds[a].width, bounds[x].width),
      math.max(bounds[b].width, bounds[y].width),
    ];
    final deficit =
        math.max(0, bounds[outer].width - (widths[0] + (widths[1] + edge))) / 2;
    widths[0] += deficit;
    widths[1] += deficit;
    final total = widths[0] + edge + widths[1];
    final bases = [a, b, ?bg];
    final ascent = bases
        .map((i) => baseline[i] - bounds[i].top)
        .reduce(math.max);
    final descent = bases
        .map((i) => bounds[i].bottom - baseline[i])
        .reduce(math.max);
    final overAscent = [
      x,
      ?ag,
      y,
    ].map((i) => baseline[i] - bounds[i].top).reduce(math.max);
    final overDescent = [
      x,
      ?ag,
      y,
    ].map((i) => bounds[i].bottom - baseline[i]).reduce(math.max);
    final common = ascent + overAscent + overDescent;
    final offsets = <int, ({double left, double width, double relative})>{
      a: (left: 0, width: widths[0], relative: 0),
      b: (left: widths[0] + edge, width: widths[1], relative: 0),
      ?bg: (left: widths[0], width: edge, relative: 0),
      x: (left: 0, width: widths[0], relative: -ascent - overDescent),
      y: (
        left: widths[0] + edge,
        width: widths[1],
        relative: -ascent - overDescent,
      ),
      ?ag: (left: widths[0], width: edge, relative: -ascent - overDescent),
      outer: (
        left: 0,
        width: total,
        relative: descent + baseline[outer] - bounds[outer].top,
      ),
    };
    return await rubyGapPixels((canvas) {
      for (var i = 0; i < painters.length; i++) {
        final offset = offsets[i]!;
        final left = f.direction == TextDirection.ltr
            ? offset.left
            : total - offset.left - offset.width;
        painters[i].paint(
          canvas,
          const Offset(20, 20) +
              Offset(
                left + (offset.width - bounds[i].width) / 2 - bounds[i].left,
                common + offset.relative - baseline[i],
              ),
        );
      }
    });
  } finally {
    for (final p in painters) {
      p.dispose();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final direction in TextDirection.values) {
    for (final root in [false, true]) {
      for (final baseGap in [false, true]) {
        test(
          'CJK segment origin has no phantom gap font or pixels $direction root=$root base=$baseGap',
          () async {
            final f = RubyGapFixture(
              direction: direction,
              rootAnnotationGap: root,
              annotationGapSize: 40,
              annotationGapText: '\n',
              firstAnnotation: '漢',
              secondAnnotation: '字',
              includeBaseGap: baseGap,
              gapSize: 20,
              tight: true,
              scaler: const TextScaler.linear(1.27),
            );
            addTearDown(f.close);
            expect(f.request.annotationGaps, isEmpty);
            final fence = f.input.content.contexts.singleWhere(
              (w) => w.content.projection.text.isEmpty,
            );
            expect(fence.startUtf16, fence.endUtf16);
            expect(fence.content.isSourceFree, isFalse);
            expect(fence.content.projection.sourceAtUtf16(0).isExact, isFalse);
            final metrics = f.measure(1);
            expect(metrics.annotationGaps, isEmpty);
            final layout = f.prepare(metrics, 1);
            try {
              expect(layout.nativeLeases.length, baseGap ? 6 : 5);
              final actual = await rubyGapPixels(
                (c) => layout.paint(c, const Offset(20, 20)),
              );
              expect(actual, await _reference(f));
            } finally {
              layout.close();
            }
            expect(f.cache.activeLeases, 0);
          },
        );
      }
    }
  }
  test(
    'annotation gaps require original adjacent spans and unique whitespace',
    () {
      final f = RubyGapFixture(
        direction: TextDirection.ltr,
        annotationGapSize: 40,
      );
      addTearDown(f.close);
      final r = f.request;
      ForumBodyRubySegmentRequest request(
        List<ForumBodyRubyAnnotationGapRequest> gaps,
      ) => ForumBodyRubySegmentRequest(
        bases: r.bases,
        sides: r.sides,
        spans: r.spans,
        gaps: r.gaps,
        annotationGaps: gaps,
      );
      final gap = r.annotationGaps.single;
      for (final index in [-1, 0, 2, r.spans.length]) {
        expect(
          () => request([
            (beforeSpanIndex: index, request: gap.request, gap: gap.gap),
          ]),
          throwsA(isA<ForumBodyRubyGroupException>()),
          reason: 'index=$index is not an original following adjacent span',
        );
      }
      expect(
        () => request([gap, gap]),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      expect(
        () => request([
          (beforeSpanIndex: 1, request: r.spans.first.request, gap: gap.gap),
        ]),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      expect(f.cache.layoutBuildCount, 0);
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'numeric annotation gaps reject missing neighbours and inside-word edges',
    () {
      final f = RubyGapFixture(
        direction: TextDirection.ltr,
        annotationGapSize: 40,
      );
      addTearDown(f.close);
      final raw = f.measure(1);
      final counts = (f.cache.layoutBuildCount, f.cache.pictureBuildCount);
      final gap = raw.annotationGaps.single.input;
      ForumBodyRubySegmentMetrics compose({
        List<ForumBodyRubyMeasuredSpan>? spans,
        List<ForumBodyRubyMeasuredAnnotationGap>? gaps,
      }) => ForumBodyRubySegmentMetrics.compose(
        columns: raw.columns,
        spans: spans ?? [for (final s in raw.spans) s.input],
        gaps: [for (final g in raw.gaps) g.input],
        annotationGaps: gaps ?? [gap],
      );
      for (final removed in [0, 1]) {
        expect(
          () => compose(
            spans: [
              for (final (index, s) in raw.spans.indexed)
                if (index != removed) s.input,
            ],
          ),
          throwsA(isA<ForumBodyRubyGroupException>()),
        );
      }
      expect(
        () => compose(
          spans: [
            ForumBodyRubyMeasuredSpan(
              startColumn: 0,
              endColumn: 2,
              annotationIndex: 0,
              annotation: raw.spans.first.input.annotation,
            ),
            raw.spans.last.input,
          ],
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      for (final edge in [0, 2]) {
        expect(
          () => compose(
            gaps: [
              ForumBodyRubyMeasuredAnnotationGap(
                beforeColumn: edge,
                annotationIndex: gap.annotationIndex,
                annotation: gap.annotation,
              ),
            ],
          ),
          throwsA(isA<ForumBodyRubyGroupException>()),
        );
      }
      expect((f.cache.layoutBuildCount, f.cache.pictureBuildCount), counts);
      expect(f.cache.activeLeases, 0);
    },
  );

  test('page atom rejects a missing or changed annotation gap target', () {
    final f = RubyGapFixture(
      direction: TextDirection.ltr,
      annotationGapSize: 40,
    );
    addTearDown(f.close);
    final raw = f.measure(1);
    final counts = (f.cache.layoutBuildCount, f.cache.pictureBuildCount);
    final missing = ForumBodyRubySegmentMetrics.compose(
      columns: raw.columns,
      spans: [for (final s in raw.spans) s.input],
      gaps: [for (final g in raw.gaps) g.input],
    );
    expect(
      () => ForumBodyRubyAtomPlan.segment(request: f.request, metrics: missing),
      throwsArgumentError,
    );
    final original = f.request;
    final gap = original.annotationGaps.single;
    final changed = ForumBodyRubySegmentRequest(
      bases: original.bases,
      sides: original.sides,
      spans: original.spans,
      gaps: original.gaps,
      annotationGaps: [
        (beforeSpanIndex: gap.beforeSpanIndex, request: gap.request, gap: 1),
      ],
    );
    expect(
      () => ForumBodyRubyAtomPlan.segment(request: changed, metrics: raw),
      throwsArgumentError,
    );
    expect((f.cache.layoutBuildCount, f.cache.pictureBuildCount), counts);
    expect(f.cache.activeLeases, 0);
  });

  for (final direction in TextDirection.values) {
    for (final tight in [false, true]) {
      for (final (baseGap, root) in [
        for (final baseGap in [false, true])
          for (final root in [false, true]) (baseGap, root),
      ]) {
        test(
          'original annotation gap has its own level font/edge/source and exact RGBA $direction tight=$tight base=$baseGap root=$root',
          () async {
            final f = RubyGapFixture(
              direction: direction,
              includeBaseGap: baseGap,
              gapSize: 20,
              annotationGapSize: 40,
              rootAnnotationGap: root,
              tight: tight,
              scaler: tight ? TextScaler.linear(1.27) : TextScaler.noScaling,
            );
            addTearDown(f.close);
            final metrics = f.measure(1);
            expect(metrics.columns.length, 2);
            expect(metrics.spans.length, 3);
            expect(metrics.annotationGaps.single.beforeSpanIndex, 1);
            expect(metrics.annotationGaps.single.input.annotationIndex, 0);
            expect(metrics.annotationGaps.single.input.beforeColumn, 1);
            expect(metrics.level.baseAscent, metrics.columns[1].baseAscent);
            expect(
              metrics.level.annotations.first.ascent,
              greaterThan(metrics.spans[0].input.annotation.ascent),
            );
            expect(metrics.edgeWidths[1], metrics.annotationGaps.single.width);
            expect(metrics.gaps.length, baseGap ? 1 : 0);
            final layout = f.prepare(metrics, 1);
            try {
              expect(layout.nativeLeases.length, baseGap ? 7 : 6);
              final box = layout
                  .selectionBoxesForAnnotationGap(
                    gapIndex: 0,
                    startUtf16: 0,
                    endUtf16: 1,
                  )
                  .single;
              final hit = layout.sourceAt(
                Offset(box.left + .001, (box.top + box.bottom) / 2),
              );
              expect(hit.annotationGapIndex, 0);
              expect(hit.columnIndex, isNull);
              expect(hit.spanIndex, isNull);
              expect(
                hit.position.sourceRune,
                f.request.annotationGaps.single.request.content.projection
                    .sourceAtUtf16(0)
                    .sourceRune,
              );
              expect(hit.position.isExact, isTrue);
              if (baseGap) {
                final base = layout
                    .selectionBoxesForGap(
                      gapIndex: 0,
                      startUtf16: 0,
                      endUtf16: 1,
                    )
                    .single;
                final baseHit = layout.sourceAt(
                  Offset(base.left + .001, (base.top + base.bottom) / 2),
                );
                expect(baseHit.gapIndex, 0);
                expect(baseHit.annotationGapIndex, isNull);
                expect(
                  baseHit.position.sourceRune,
                  f.request.gaps.single.request.content.projection
                      .sourceAtUtf16(0)
                      .sourceRune,
                );
              }
              final actual = await rubyGapPixels(
                (c) => layout.paint(c, const Offset(20, 20)),
              );
              final expected = await _reference(f);
              var differences = 0;
              for (var i = 0; i < actual.length; i++) {
                if (actual[i] != expected[i]) differences++;
              }
              expect(differences, 0);
            } finally {
              layout.close();
            }
            expect(f.cache.activeLeases, 0);
          },
        );
      }
    }
  }

  for (final q in [1, 7, 32]) {
    test(
      'row target keeps annotation/base gap rectangles and original span identities q=$q',
      () {
        final f = RubyGapFixture(
          direction: TextDirection.rtl,
          gapSize: 20,
          annotationGapSize: 40,
        );
        final larger = RubyGapFixture(
          direction: TextDirection.rtl,
          gapSize: 20,
          annotationGapSize: 60,
        );
        addTearDown(f.close);
        addTearDown(larger.close);
        final raw = f.measure(q);
        final level = larger.measure(q).level;
        final work = ForumBodyRubySegmentAlignment(
          segment: raw,
          level: level,
          prepareResult: true,
        );
        final native = (
          f.cache.layoutBuildCount,
          f.cache.pictureBuildCount,
          f.cache.activeLeases,
        );
        while (!work.isComplete) {
          expect(work.advance(maxParts: q), inInclusiveRange(1, q));
        }
        expect((
          f.cache.layoutBuildCount,
          f.cache.pictureBuildCount,
          f.cache.activeLeases,
        ), native);
        final aligned = work.result;
        expect(work.hasChanges, isTrue);
        expect(aligned.edgeWidths, raw.edgeWidths);
        expect(aligned.columnWidths, raw.columnWidths);
        expect(aligned.columnLefts, raw.columnLefts);
        expect(
          aligned.annotationGaps.single.left,
          raw.annotationGaps.single.left,
        );
        expect(
          aligned.annotationGaps.single.width,
          raw.annotationGaps.single.width,
        );
        expect(aligned.gaps.single.left, raw.gaps.single.left);
        expect(
          identical(
            aligned.annotationGaps.single.input,
            raw.annotationGaps.single.input,
          ),
          isTrue,
        );
        final layout = f.prepare(aligned, q);
        layout.close();
        expect(f.cache.activeLeases, 0);
      },
    );

    test(
      'cold whole Page binds actual annotation gap in original source order q=$q',
      () {
        final f = RubyGapFixture(
          direction: TextDirection.ltr,
          gapSize: 20,
          annotationGapSize: 40,
        );
        addTearDown(f.close);
        final metrics = f.measure(q);
        final root = f.request.rootBox!;
        final rootLease = f.cache.acquire(
          content: root.fontStrut,
          width: 300,
          textScaler: f.scaler,
        );
        late final ForumBodyRubyRootFontBox rootFont;
        try {
          rootFont = ForumBodyRubyRootFontBox(
            input: root,
            height: rootLease.layout.height,
            alphabeticBaseline: rootLease.layout.alphabeticBaseline,
          );
        } finally {
          rootLease.release();
        }
        final page = RubyAtomPageFixture.compose(
          input: ForumBodyInlinePageContent.atoms(
            content: f.input.content,
            dimensions: [
              rootFont
                  .enclose(
                    childSize: metrics.size,
                    childBaseline: metrics.baseline,
                  )
                  .dimensions,
            ],
            rootFonts: {0: rootFont},
            rubyAtoms: [
              ForumBodyRubyAtomPlan.segment(
                request: f.request,
                metrics: metrics,
              ),
            ],
          ),
          planning: f.cache,
          entries: 2,
        );
        addTearDown(page.close);
        final job = page.open(0);
        page.finish(job, q: q);
        final fragment =
            job.takeFragments().single as ForumBodyPreparedInlineFragment;
        try {
          expect(fragment.nativeLeases.length, 8);
          for (final window in f.input.content.contexts) {
            if (window.content.projection.text.isEmpty) continue;
            final box = fragment
                .glyphBoxes(window.startUtf16, window.startUtf16 + 1)
                .first;
            final hit = fragment.view.sourceAt(
              Offset(box.left + .001, (box.top + box.bottom) / 2),
            );
            expect(
              hit.sourceRune,
              window.content.projection.sourceAtUtf16(0).sourceRune,
            );
            expect(hit.isExact, isTrue);
          }
        } finally {
          fragment.close();
        }
        expect(page.cache.activeLeases, 0);
      },
    );
  }

  test(
    'cancel at actual annotation gap pin preserves independent ownership',
    () {
      final f = RubyGapFixture(
        direction: TextDirection.ltr,
        annotationGapSize: 40,
      );
      addTearDown(f.close);
      final metrics = f.measure(1);
      final content = f.request.annotationGaps.single.request.content;
      final foreign = f.cache.acquire(content: content, width: 300);
      final job = ForumBodyRubySegmentPreparation(
        cache: f.cache,
        request: f.request,
        metrics: metrics,
        ensureOwner: () {},
      );
      try {
        var reached = false;
        for (var i = 0; !reached && i < 10000; i++) {
          job.advance(maxParts: 1);
          reached = job.nativeLeases.whereType<ForumBodyTextLease>().any(
            (l) => identical(l.content, content),
          );
        }
        expect(reached, isTrue);
        job.close();
        expect(foreign.isActive, isTrue);
        expect(f.cache.activeLeases, 1);
      } finally {
        job.close();
        foreign.release();
      }
      expect(f.cache.activeLeases, 0);
    },
  );
}
