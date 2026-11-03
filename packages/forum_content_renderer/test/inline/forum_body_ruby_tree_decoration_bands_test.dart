import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_metrics_preparation.dart'
    show ForumBodyRubyTreeContainerMetrics;
import 'package:forum_content_renderer/src/inline/forum_body_ruby_tree_input.dart'
    show ForumBodyRubyTreeSegment;

import 'test_support/ruby_glyph_tree_fixture.dart';

ForumBodyRubyTreeDecorationBands _finish(
  ForumBodyRubyTreeDecorationBandsPreparation work, {
  int quantum = 1,
}) {
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(200000));
      expect(work.advance(maxParts: quantum), inInclusiveRange(1, quantum));
    }
    return work.takeBands();
  } finally {
    work.close();
  }
}

ForumBodyRubyTreeDecorationBands _compose(
  ForumBodyRubyTreeEmphasisMetrics input,
) => _finish(
  ForumBodyRubyTreeDecorationBandsPreparation(input: input, ensureOwner: () {}),
);

const _nested =
    '<ruby style="text-emphasis:circle"><rb><ruby>'
    '<rb>A</rb><rt style="font-size:24px"></rt></ruby></rb>'
    '<rt style="text-emphasis:sesame"><ruby><rb>X</rb><rt>x</rt></ruby></rt></ruby>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ForumBodyParagraphCache cache;
  setUp(() {
    cache = ForumBodyParagraphCache(
      maxEntries: 1024,
      maxEstimatedBytes: 1 << 26,
    );
  });
  tearDown(() {
    expect(cache.activeLeases, 0);
    cache.close();
  });

  for (final direction in TextDirection.values) {
    for (final side in ['over', 'under']) {
      for (final matches in [true, false]) {
        for (final scale in [1.0, 1.3]) {
          test(
            'empty RT clearance $direction $side match=$matches scale=$scale',
            () {
              final markSide = matches
                  ? side
                  : (side == 'over' ? 'under' : 'over');
              final input = rubyTreeEmphasisMetricsFixture(
                '<ruby style="ruby-position:$side;text-emphasis:circle;'
                'text-emphasis-position:$markSide;line-height:.4">'
                '<rb>A</rb><rt style="font-size:24px;line-height:4"></rt></ruby>',
                cache,
                direction: direction,
                scaler: TextScaler.linear(scale),
              );
              final glyph = input.geometry.metrics, actual = glyph.root.group!;
              final positions = input.geometry.nodes
                  .map((n) => (n.id, n.origin, n.contentOrigin))
                  .toList();
              final counters = (
                cache.layoutBuildCount,
                cache.hitCount,
                cache.pictureBuildCount,
              );
              final value = _compose(input), root = value.nodes.last;
              expect(root.rows.single.usesEmptyFont, matches);
              expect(root.rows.single.isReserved, matches);
              final y = glyph.root.frame.childOffset.dy;
              if (matches) {
                final font = input.emptyFonts.fonts.single;
                expect(
                  root.rows.single.bottom - root.rows.single.top,
                  closeTo(font.bounds.height, 1e-8),
                );
                if (side == 'over') {
                  expect(
                    root.rows.single.bottom,
                    closeTo(y + actual.baseBandTop - actual.gap, 1e-8),
                  );
                  expect(
                    value.bounds.top,
                    lessThanOrEqualTo(root.rows.single.top),
                  );
                } else {
                  expect(
                    root.rows.single.top,
                    closeTo(y + actual.baseBandBottom + actual.gap, 1e-8),
                  );
                  expect(
                    value.bounds.bottom,
                    greaterThanOrEqualTo(root.rows.single.bottom),
                  );
                }
                expect(
                  root.box!.alphabeticBaseline,
                  glyph.box.alphabeticBaseline,
                );
              } else {
                expect(root.box, same(glyph.box));
                expect(
                  root.rows.single.baseline,
                  y + actual.annotations.single.bandBaseline,
                );
              }
              final empty = value.sourceForId(
                input.emptyFonts.fonts.single.source.source.id,
              );
              expect(empty.node.isFontOnly, isTrue);
              expect(
                empty.node.box!.bounds,
                input.emptyFonts.fonts.single.bounds,
              );
              expect(
                input.geometry.nodes.map(
                  (n) => (n.id, n.origin, n.contentOrigin),
                ),
                positions,
              );
              for (final source in input.sources) {
                final id = source.source.source.id;
                expect(value.nodes[id].box, same(glyph.nodes[id].box));
                expect(
                  input.geometry.metrics.input.requestForSource(id),
                  same(source.line.baseRequest),
                );
              }
              expect((
                cache.layoutBuildCount,
                cache.hitCount,
                cache.pictureBuildCount,
              ), counters);
            },
          );
        }
      }
    }
  }
  test('no marked base preserves every actual box and row exactly', () {
    final input = rubyTreeEmphasisMetricsFixture(
      '<ruby><rb><ruby>A<rt></rt></ruby></rb><rt>x</rt></ruby>',
      cache,
    );
    final value = _compose(input);
    for (final context in value.contexts) {
      final numeric = input.geometry.metrics.nodes[context.position.id];
      if (!context.node.isFontOnly) expect(context.node.box, same(numeric.box));
      if (numeric is ForumBodyRubyTreeContainerMetrics) {
        final column = numeric.group ?? numeric.segment?.columns.first;
        for (final band in context.node.rows) {
          final row = column!.annotations[band.rank],
              y = numeric.frame.childOffset.dy;
          expect(
            (band.top, band.bottom, band.baseline),
            (y + row.bandTop, y + row.bandBottom, y + row.bandBaseline),
          );
        }
      }
    }
  });
  for (final direction in TextDirection.values) {
    test(
      'segment empty font only affects the actual covered marked span $direction',
      () {
        for (final markA in [true, false]) {
          final input = rubyTreeEmphasisMetricsFixture(
            '<ruby><rb style="text-emphasis:${markA ? 'circle' : 'none'}">A</rb>'
            '<rb style="text-emphasis:circle">B</rb>'
            '<rtc><rt style="font-size:80px"></rt><rt style="font-size:8px">b</rt></rtc></ruby>',
            cache,
            direction: direction,
          );
          final value = _compose(input), root = value.nodes.last;
          final actual = input.geometry.metrics.root.segment!;
          expect(root.rows.single.usesEmptyFont, markA);
          if (markA) {
            expect(
              root.rows.single.bottom - root.rows.single.top,
              greaterThan(70),
            );
          } else {
            expect(root.box, same(input.geometry.metrics.box));
            expect(
              root.rows.single.bottom - root.rows.single.top,
              lessThan(20),
            );
          }
          // First column has no local RT glyph, but shares the actual row baseline.
          final row = actual.columns.first.annotations.single;
          expect(row.hasAnnotation, isFalse);
          final span = actual.spans.last;
          expect(row.bandBaseline, span.offset.dy + span.metrics.fontBaseline);
          final sources = input.geometry.sources.where(
            (s) => ['A', 'B'].contains(s.source.content.projection.text),
          );
          final rows = sources
              .map((s) => value.sourceForId(s.source.id).physicalRow)
              .toSet();
          expect(rows, hasLength(1));
        }
      },
    );
    test('explicit RT cannot widen its original paired interval $direction', () {
      final input = rubyTreeEmphasisMetricsFixture(
        '<ruby><rb>A</rb><rb style="text-emphasis:circle">B</rb><rb>C</rb>'
        '<rtc><rt rbspan="2" style="font-size:30px"></rt><rt>c</rt></rtc></ruby>',
        cache,
        direction: direction,
      );
      // The existing parser pairs explicit RTs one per column; it does not
      // implement rbspan. Clearance must follow the actual graph, not the HTML
      // attribute or the fact that another column has an emphasis mark.
      final spans =
          (input.geometry.metrics.input.sourceTree.nodes.last
                  as ForumBodyRubyTreeSegment)
              .spans;
      expect((spans.first.startColumn, spans.first.endColumn), (0, 1));
      expect(_compose(input).nodes.last.rows.single.usesEmptyFont, isFalse);
    });
    test(
      'actual anonymous span retains its shared physical row $direction',
      () {
        final input = rubyTreeEmphasisMetricsFixture(
          '<ruby><rb>A</rb><rb style="text-emphasis:circle">B</rb>'
          '<rtc style="font-size:30px">wide</rtc></ruby>',
          cache,
          direction: direction,
        );
        final value = _compose(input);
        final spans =
            (input.geometry.metrics.input.sourceTree.nodes.last
                    as ForumBodyRubyTreeSegment)
                .spans;
        expect((spans.single.startColumn, spans.single.endColumn), (0, 2));
        expect(value.nodes.last.box, same(input.geometry.metrics.box));
        expect(value.nodes.last.rows.single.isReserved, isTrue);
        final annotation = input.geometry.sources.last;
        final c = value.sourceForId(annotation.source.id);
        expect(c.physicalRow.rank, 0);
        expect(
          c.physicalBaseline,
          closeTo(
            c.position.origin.dy +
                input
                    .geometry
                    .metrics
                    .nodes[c.position.id]
                    .box!
                    .alphabeticBaseline,
            1e-8,
          ),
        );
      },
    );
  }
  test(
    'nested base limits propagate while annotations retain their own row',
    () {
      final input = rubyTreeEmphasisMetricsFixture(_nested, cache);
      final value = _compose(input), root = value.contexts.first;
      final a = input.geometry.sources.firstWhere(
        (s) => s.source.content.projection.text == 'A',
      );
      final x = input.geometry.sources.firstWhere(
        (s) => s.source.content.projection.text == 'X',
      );
      final ca = value.sourceForId(a.source.id),
          cx = value.sourceForId(x.source.id);
      expect(ca.physicalRow, root.physicalRow);
      expect(cx.physicalRow, isNot(root.physicalRow));
      expect(
        ca.baseAncestorOverEdge,
        lessThanOrEqualTo(root.node.localOverEdge! + root.position.origin.dy),
      );
      // X belongs to the inner ruby base: its own containing row is relevant,
      // while the outer RT's row is not an annotation on X.
      final inner = cx.position.parent!;
      expect(
        cx.baseAncestorOverEdge,
        value.nodeForId(inner.id).node.localOverEdge! + inner.origin.dy,
      );
      for (final source in input.sources) {
        final context = value.sourceForId(source.source.source.id);
        final box = input.geometry.metrics.nodes[context.position.id].box!;
        expect(
          context.physicalBaseline,
          closeTo(context.position.origin.dy + box.alphabeticBaseline, 1e-8),
        );
      }
      expect(
        value.bounds.top,
        lessThanOrEqualTo(input.geometry.metrics.box.bounds.top),
      );
    },
  );
  test(
    'numeric publication retains no owner and every collection is readonly',
    () {
      final input = rubyTreeEmphasisMetricsFixture(_nested, cache);
      var active = true, calls = 0;
      final value = _finish(
        ForumBodyRubyTreeDecorationBandsPreparation(
          input: input,
          ensureOwner: () {
            calls++;
            if (!active) throw StateError('retired');
          },
        ),
      );
      final before = calls;
      active = false;
      cache.close();
      expect(value.input, same(input));
      expect(value.bounds.isFinite, isTrue);
      expect(calls, before);
      expect(() => value.nodes.clear(), throwsUnsupportedError);
      expect(() => value.contexts.clear(), throwsUnsupportedError);
      expect(() => value.nodes.last.rows.clear(), throwsUnsupportedError);
      expect(() => value.nodeForId(-99999), throwsArgumentError);
      expect(() => value.sourceForId(99999), throwsArgumentError);
    },
  );
  test(
    'each work boundary and final publication retire without native work',
    () {
      final input = rubyTreeEmphasisMetricsFixture(_nested, cache);
      final count = ForumBodyRubyTreeDecorationBandsPreparation(
        input: input,
        ensureOwner: () {},
      );
      var parts = 0;
      while (!count.isReady) {
        parts += count.advance(maxParts: 1);
      }
      count.close();
      final counters = (
        cache.layoutBuildCount,
        cache.hitCount,
        cache.pictureBuildCount,
      );
      for (var stop = 0; stop <= parts; stop++) {
        var active = true;
        final work = ForumBodyRubyTreeDecorationBandsPreparation(
          input: input,
          ensureOwner: () {
            if (!active) throw StateError('retired');
          },
        );
        for (var n = 0; n < stop; n++) {
          work.advance(maxParts: 1);
        }
        active = false;
        expect(work.advance, throwsStateError);
        expect(work.takeBands, throwsStateError);
        work.close();
      }
      ForumBodyRubyTreeDecorationBandsPreparation? work;
      work = ForumBodyRubyTreeDecorationBandsPreparation(
        input: input,
        ensureOwner: () {
          if (work?.isReady == true) work!.close();
        },
      );
      expect(() => _finish(work!), throwsStateError);
      expect((
        cache.layoutBuildCount,
        cache.hitCount,
        cache.pictureBuildCount,
      ), counters);
    },
  );
  test('caught reentry does not retire the outer operation', () {
    final input = rubyTreeEmphasisMetricsFixture(_nested, cache);
    ForumBodyRubyTreeDecorationBandsPreparation? work;
    work = ForumBodyRubyTreeDecorationBandsPreparation(
      input: input,
      ensureOwner: () {
        if (work == null) return;
        expect(work.advance, throwsStateError);
        expect(work.takeBands, throwsStateError);
      },
    );
    expect(_finish(work).nodes.last.rows, isNotEmpty);
  });
  test(
    'wide spans use bounded linear prefix work with identical quantum results',
    () {
      const columns = 48;
      final input = rubyTreeEmphasisMetricsFixture(
        '<ruby style="font-size:4px">${List.generate(columns, (i) => '<rb style="text-emphasis:circle">A</rb>').join()}'
        '<rtc>${List.generate(columns, (i) => '<rt></rt>').join()}</rtc></ruby>',
        cache,
      );
      final work = ForumBodyRubyTreeDecorationBandsPreparation(
        input: input,
        ensureOwner: () {},
      );
      var parts = 0;
      while (!work.isReady) {
        parts += work.advance(maxParts: 1);
      }
      final value = work.takeBands();
      work.close();
      expect(parts, lessThan(columns * 40));
      final other = _finish(
        ForumBodyRubyTreeDecorationBandsPreparation(
          input: input,
          ensureOwner: () {},
        ),
        quantum: 32,
      );
      expect(other.bounds, value.bounds);
      expect(
        other.contexts.map((c) => (c.physicalRow, c.physicalBaseline)),
        value.contexts.map((c) => (c.physicalRow, c.physicalBaseline)),
      );
    },
  );
}
