import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_gap_fixture.dart';

/// Independent native painters and the small, actual two-column source grid.
/// No production gap/column/segment positions or dimensions feed this control.
Future<List<int>> _reference(RubyGapFixture f) async {
  final contents = f.request.nativeRequests.map((r) => r.content).toList();
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
    final baselines = [
      for (final p in painters)
        p.height - p.computeLineMetrics().single.descent,
    ];
    // Original members: A, actual gap, B, x, y, whole annotation.
    final widths = [bounds[0].width, bounds[2].width];
    final deficit =
        math.max(
          0,
          bounds[5].width - (widths[0] + (widths[1] + bounds[1].width)),
        ) /
        2;
    widths[0] += deficit;
    widths[1] += deficit;
    final total = widths[0] + bounds[1].width + widths[1];
    final baseAscent = [
      for (final i in [0, 1, 2]) baselines[i] - bounds[i].top,
    ].reduce(math.max);
    final baseDescent = [
      for (final i in [0, 1, 2]) bounds[i].bottom - baselines[i],
    ].reduce(math.max);
    final overAscent = math.max(
      baselines[3] - bounds[3].top,
      baselines[4] - bounds[4].top,
    );
    final overDescent = math.max(
      bounds[3].bottom - baselines[3],
      bounds[4].bottom - baselines[4],
    );
    final baseline = baseAscent + overAscent + overDescent;
    final ltr = [
      0.0,
      widths[0],
      widths[0] + bounds[1].width,
      0.0,
      widths[0] + bounds[1].width,
      0.0,
    ];
    final allocated = [
      widths[0],
      bounds[1].width,
      widths[1],
      widths[0],
      widths[1],
      total,
    ];
    return await rubyGapPixels((canvas) {
      for (var i = 0; i < painters.length; i++) {
        final left = f.direction == TextDirection.ltr
            ? ltr[i]
            : total - ltr[i] - allocated[i];
        final relative = i < 3
            ? 0.0
            : i < 5
            ? -baseAscent - overDescent
            : baseDescent + baselines[5] - bounds[5].top;
        painters[i].paint(
          canvas,
          const Offset(20, 20) +
              Offset(
                left + (allocated[i] - bounds[i].width) / 2 - bounds[i].left,
                baseline + relative - baselines[i],
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
    for (final tight in [false, true]) {
      test(
        'actual styled gap uses native fonts, span widths, hits and exact RGBA $direction tight=$tight',
        () async {
          final f = RubyGapFixture(
            direction: direction,
            tight: tight,
            scaler: tight ? TextScaler.linear(1.27) : TextScaler.noScaling,
          );
          addTearDown(f.close);
          final metrics = f.measure(1);
          expect(f.cache.activeLeases, 0);
          expect(metrics.columns.length, 2);
          expect(metrics.gaps.single.input.beforeColumn, 1);
          final layout = f.prepare(metrics, 1);
          try {
            expect(layout.nativeLeases.length, 6);
            final gap = metrics.gaps.single;
            final boxes = layout.selectionBoxesForGap(
              gapIndex: 0,
              startUtf16: 0,
              endUtf16: 1,
            );
            expect(boxes, isNotEmpty);
            final hit = layout.sourceAt(
              Offset(
                boxes.single.left + .001,
                (boxes.single.top + boxes.single.bottom) / 2,
              ),
            );
            expect(hit.gapIndex, 0);
            expect(
              hit.position.sourceRune,
              f.request.gaps.single.request.content.projection
                  .sourceAtUtf16(0)
                  .sourceRune,
            );
            final span = metrics.spans.last;
            final under = layout.sourceAt(
              Offset(
                gap.left + gap.width / 2,
                (span.metrics.bandTop + span.metrics.bandBottom) / 2,
              ),
            );
            expect(under.spanIndex, 2);
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

  for (final q in [1, 7, 32]) {
    test(
      'row target keeps actual gap and span rectangles, without repeating width allocation q=$q',
      () {
        final f = RubyGapFixture(direction: TextDirection.rtl);
        final larger = RubyGapFixture(
          direction: TextDirection.rtl,
          gapSize: 60,
        );
        addTearDown(f.close);
        addTearDown(larger.close);
        final raw = f.measure(q);
        final target = larger.measure(q).level;
        final aligned = raw.alignedTo(target);
        expect(aligned.columnWidths, raw.columnWidths);
        expect(aligned.columnLefts, raw.columnLefts);
        expect(aligned.gaps.single.left, raw.gaps.single.left);
        expect(aligned.gaps.single.width, raw.gaps.single.width);
        expect(
          identical(aligned.gaps.single.input, raw.gaps.single.input),
          isTrue,
        );
        expect(aligned.size.height, greaterThan(raw.size.height));
        final layout = f.prepare(aligned, q);
        layout.close();
        expect(f.cache.activeLeases, 0);
      },
    );
  }

  test(
    'cancel while an actual gap is pinned releases only the pending component',
    () {
      final f = RubyGapFixture(direction: TextDirection.ltr);
      addTearDown(f.close);
      final metrics = f.measure(1);
      final content = f.request.gaps.single.request.content;
      final foreign = f.cache.acquire(content: content, width: 300);
      addTearDown(foreign.release);
      final job = ForumBodyRubySegmentPreparation(
        cache: f.cache,
        request: f.request,
        metrics: metrics,
        ensureOwner: () {},
      );
      try {
        var reachedGap = false;
        for (var i = 0; !reachedGap && i < 10000; i++) {
          job.advance(maxParts: 1);
          reachedGap = job.nativeLeases.whereType<ForumBodyTextLease>().any(
            (l) => identical(l.content, content),
          );
        }
        expect(reachedGap, isTrue);
        expect(f.cache.activeLeases, greaterThan(1));
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

  test(
    'gap requests reject out-of-range edges, duplicates and missing numeric members',
    () {
      final f = RubyGapFixture(direction: TextDirection.ltr);
      addTearDown(f.close);
      final r = f.request;
      for (final edge in [0, 2]) {
        expect(
          () => ForumBodyRubySegmentRequest(
            bases: r.bases,
            sides: r.sides,
            spans: r.spans,
            gaps: [(beforeColumn: edge, request: r.gaps.single.request)],
          ),
          throwsA(isA<ForumBodyRubyGroupException>()),
        );
      }
      expect(
        () => ForumBodyRubySegmentRequest(
          bases: r.bases,
          sides: r.sides,
          spans: r.spans,
          gaps: [...r.gaps, ...r.gaps],
        ),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      final metrics = f.measure(1);
      final missing = ForumBodyRubySegmentRequest(
        bases: r.bases,
        sides: r.sides,
        spans: r.spans,
      );
      expect(
        () => ForumBodyRubyAtomPlan.segment(request: missing, metrics: metrics),
        throwsArgumentError,
      );
      expect(f.cache.activeLeases, 0);
    },
  );
}
