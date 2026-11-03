import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_glyph_tree_fixture.dart';

ForumBodyRubyTreeDecorationBands _bands(
  String html,
  ForumBodyParagraphCache cache, {
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
}) {
  final metrics = rubyTreeEmphasisMetricsFixture(
    html,
    cache,
    direction: direction,
    scaler: scaler,
  );
  final work = ForumBodyRubyTreeDecorationBandsPreparation(
    input: metrics,
    ensureOwner: () {},
  );
  try {
    while (!work.isReady) {
      work.advance(maxParts: 1);
    }
    return work.takeBands();
  } finally {
    work.close();
  }
}

ForumBodyRubyTreeEmphasisPlacement _finish(
  ForumBodyRubyTreeEmphasisPlacementPreparation work, {
  int quantum = 1,
}) {
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(200000));
      expect(work.advance(maxParts: quantum), inInclusiveRange(1, quantum));
    }
    return work.takePlacement();
  } finally {
    work.close();
  }
}

ForumBodyRubyTreeEmphasisPlacement _place(
  ForumBodyRubyTreeDecorationBands input,
) => _finish(
  ForumBodyRubyTreeEmphasisPlacementPreparation(
    input: input,
    ensureOwner: () {},
  ),
);

const _nested =
    '<ruby style="text-emphasis:circle"><rb><ruby><rb>A é</rb>'
    '<rt style="font-size:18px"></rt></ruby></rb>'
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
      for (final scale in [1.0, 1.3]) {
        test(
          'shared $side marker baseline outside real/empty RT $direction scale=$scale',
          () {
            final input = _bands(
              '<ruby style="ruby-position:$side;text-emphasis:circle;text-emphasis-position:$side">'
              '<rb style="font-size:24px">A</rb><rb>B</rb>'
              '<rtc><rt style="font-size:32px"></rt><rt>b</rt></rtc></ruby>',
              cache,
              direction: direction,
              scaler: TextScaler.linear(scale),
            );
            final counters = (
              cache.layoutBuildCount,
              cache.hitCount,
              cache.pictureBuildCount,
            );
            final value = _place(input);
            expect(value.marks, hasLength(2));
            expect(
              value.marks.map((m) => m.baselineOrigin.dy).toSet(),
              hasLength(1),
            );
            final edge = side == 'over'
                ? input.nodes.last.localOverEdge!
                : input.nodes.last.localUnderEdge!;
            for (final mark in value.marks) {
              expect(
                mark.fontBounds,
                mark.mark.scaledFontBounds
                    .shift(mark.fontOffset)
                    .shift(mark.baselineOrigin),
              );
              expect(mark.fontOffset.dy, -mark.mark.scaledAlphabeticBaseline);
              expect(mark.baselineOrigin.dx, mark.source.source.node.origin.dx);
              if (side == 'over') {
                expect(mark.fontBounds.bottom, lessThanOrEqualTo(edge + 1e-8));
              } else {
                expect(mark.fontBounds.top, greaterThanOrEqualTo(edge - 1e-8));
              }
              expect(
                value.bounds.expandToInclude(mark.fontBounds),
                value.bounds,
              );
            }
            expect(value.bounds.expandToInclude(input.bounds), value.bounds);
            expect((
              cache.layoutBuildCount,
              cache.hitCount,
              cache.pictureBuildCount,
            ), counters);
            expect(
              value.marks.map(
                (m) => m.source.source.source.content.projection.text,
              ),
              ['A', 'B'],
            );
          },
        );
      }
    }
  }
  for (final side in ['over', 'under']) {
    test('opposite-side annotation keeps natural marker placement $side', () {
      final other = side == 'over' ? 'under' : 'over';
      final input = _bands(
        '<ruby style="ruby-position:$other;text-emphasis:circle;text-emphasis-position:$side">A<rt>x</rt></ruby>',
        cache,
      );
      final value = _place(input), source = input.input.sources.single;
      expect(
        value.marks.single.baselineOrigin.dy,
        source.source.node.origin.dy +
            source.line.marks.single.baseRelativeAlphabeticBaseline,
      );
    });
  }
  test('real single-column path agrees with existing base placement', () {
    final input = _bands(
      '<ruby style="text-emphasis:circle">ABC<rt>xy</rt></ruby>',
      cache,
    );
    final value = _place(input), glyph = input.input.geometry.metrics;
    final old = ForumBodyRubyBaseEmphasisPreparation(
      line: input.input.sources.single.line,
      group: glyph.root.group!,
      ensureOwner: () {},
    );
    try {
      while (!old.isReady) {
        old.advance(maxParts: 1);
      }
      final previous = old.takeGeometry();
      for (var i = 0; i < value.marks.length; i++) {
        final a = value.marks[i],
            b = previous.marks[i],
            frame = glyph.root.frame.childOffset;
        expect(a.fontOffset, b.fontOffset);
        expect(a.baselineOrigin, b.baselineOrigin + frame);
        expect(a.fontBounds, b.fontBounds.shift(frame));
      }
    } finally {
      old.close();
    }
  });
  test('two marker sides share their own baseline without merging sides or rows', () {
    final input = _bands(
      '<ruby><rb><span style="text-emphasis:circle;text-emphasis-position:over;font-size:24px">A</span>'
      '<span style="text-emphasis:sesame;text-emphasis-position:under">B</span>'
      '<span style="text-emphasis:circle;text-emphasis-position:over;font-size:32px">C</span></rb>'
      '<rt>x</rt></ruby>',
      cache,
    );
    final value = _place(input),
        a = value.marks[0],
        b = value.marks[1],
        c = value.marks[2];
    expect(a.row, b.row);
    expect(a.baselineOrigin.dy, c.baselineOrigin.dy);
    expect(a.baselineOrigin.dy, isNot(b.baselineOrigin.dy));
    final row = value.rowForId(a.row);
    expect(row.overBaseline, a.baselineOrigin.dy);
    expect(row.underBaseline, b.baselineOrigin.dy);
  });
  test(
    'unmarked intermediate row propagates deep annotation marker clearance',
    () {
      final input = _bands(
        '<ruby style="text-emphasis:circle">A<rt><ruby>X'
        '<rt style="text-emphasis:sesame">Y</rt></ruby></rt></ruby>',
        cache,
      );
      final value = _place(input), a = value.marks.first, y = value.marks.last;
      expect(
        value.marks.map((m) => m.source.source.source.content.projection.text),
        ['A', 'Y'],
      );
      final yr = value.rowForId(y.row),
          intermediate = value.rowForId(yr.parent!);
      expect(intermediate.overBaseline, isNull);
      expect(intermediate.underBaseline, isNull);
      expect(intermediate.parent, a.row);
      expect(a.fontBounds.bottom, lessThanOrEqualTo(y.fontBounds.top + 1e-8));
    },
  );
  for (final side in ['over', 'under']) {
    test('annotation decorations solve before marked ancestor $side', () {
      final input = _bands(
        '<ruby style="ruby-position:$side;text-emphasis:circle;text-emphasis-position:$side">'
        '<rb>A</rb><rt style="text-emphasis:sesame;text-emphasis-position:$side">'
        '<ruby style="ruby-position:$side"><rb>X</rb><rt>x</rt></ruby></rt></ruby>',
        cache,
      );
      final value = _place(input), a = value.marks.first, x = value.marks.last;
      expect(a.row, isNot(x.row));
      final outer = value.rowForId(a.row), inner = value.rowForId(x.row);
      expect(inner.parent, outer.id);
      expect(value.rows.indexOf(inner), lessThan(value.rows.indexOf(outer)));
      if (side == 'over') {
        expect(a.fontBounds.bottom, lessThanOrEqualTo(x.fontBounds.top + 1e-8));
      } else {
        expect(
          a.fontBounds.top,
          greaterThanOrEqualTo(x.fontBounds.bottom - 1e-8),
        );
      }
      expect(
        outer.subtreeMarkerBounds!.expandToInclude(x.fontBounds),
        outer.subtreeMarkerBounds,
      );
      expect(input.nodes.last.box, same(input.input.geometry.metrics.box));
    });
  }
  test(
    'original grapheme/style/source identity and order survive hierarchy solving',
    () {
      final input = _bands(_nested, cache), value = _place(input);
      final expected = [
        for (final source in input.input.sources)
          for (final mark in source.line.marks) (source, mark),
      ];
      expect(value.marks, hasLength(expected.length));
      for (var i = 0; i < expected.length; i++) {
        expect(value.marks[i].source, same(expected[i].$1));
        expect(value.marks[i].mark, same(expected[i].$2));
      }
      final combined = value.marks.where(
        (m) =>
            m.source.line.input.units[m.mark.unitIndex].endUtf16 -
                m.source.line.input.units[m.mark.unitIndex].startUtf16 ==
            2,
      );
      expect(combined, hasLength(1));
      expect(
        value.marks
            .where((m) => m.source.source.source.content.projection.text == 'X')
            .single
            .mark
            .input
            .mark,
        '﹅',
      );
    },
  );
  test('plain and opaque contexts create no independent marker authority', () {
    for (final html in [
      '<ruby>A<rt></rt></ruby>',
      '<ruby><rb>L<ruby>A<rt>x</rt></ruby>R</rb><rt>y</rt></ruby>',
    ]) {
      final input = _bands(html, cache), value = _place(input);
      expect(value.marks, isEmpty);
      expect(value.bounds, input.bounds);
      expect(value.rows.every((r) => r.subtreeMarkerBounds == null), isTrue);
    }
  });
  test(
    'numeric publication is readonly, native-free and independent of retired owner',
    () {
      final input = _bands(_nested, cache);
      final before = (
        cache.layoutBuildCount,
        cache.hitCount,
        cache.pictureBuildCount,
      );
      var active = true, calls = 0;
      final value = _finish(
        ForumBodyRubyTreeEmphasisPlacementPreparation(
          input: input,
          ensureOwner: () {
            calls++;
            if (!active) throw StateError('retired');
          },
        ),
      );
      expect((
        cache.layoutBuildCount,
        cache.hitCount,
        cache.pictureBuildCount,
      ), before);
      final guards = calls;
      active = false;
      cache.close();
      expect(value.bounds.isFinite, isTrue);
      expect(value.marks, isNotEmpty);
      expect(calls, guards);
      expect(() => value.marks.clear(), throwsUnsupportedError);
      expect(() => value.rows.clear(), throwsUnsupportedError);
      expect(
        () => value.rowForId((owner: -9999, rank: null)),
        throwsArgumentError,
      );
    },
  );
  test(
    'all work boundaries, final publication and caught reentry preserve owner rules',
    () {
      final input = _bands(_nested, cache);
      final counter = ForumBodyRubyTreeEmphasisPlacementPreparation(
        input: input,
        ensureOwner: () {},
      );
      var parts = 0;
      while (!counter.isReady) {
        parts += counter.advance(maxParts: 1);
      }
      counter.close();
      for (var stop = 0; stop <= parts; stop++) {
        var active = true;
        final work = ForumBodyRubyTreeEmphasisPlacementPreparation(
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
        expect(work.takePlacement, throwsStateError);
        work.close();
      }
      ForumBodyRubyTreeEmphasisPlacementPreparation? publish;
      publish = ForumBodyRubyTreeEmphasisPlacementPreparation(
        input: input,
        ensureOwner: () {
          if (publish?.isReady == true) publish!.close();
        },
      );
      expect(() => _finish(publish!), throwsStateError);
      ForumBodyRubyTreeEmphasisPlacementPreparation? reentry;
      reentry = ForumBodyRubyTreeEmphasisPlacementPreparation(
        input: input,
        ensureOwner: () {
          if (reentry == null) return;
          expect(reentry.advance, throwsStateError);
          expect(reentry.takePlacement, throwsStateError);
        },
      );
      expect(_finish(reentry).marks, isNotEmpty);
    },
  );
  test(
    'wide source collection and publication stay linear across work quanta',
    () {
      const columns = 48;
      final input = _bands(
        '<ruby style="font-size:4px;text-emphasis:circle">'
        '${List.filled(columns, '<rb>A</rb>').join()}'
        '<rtc>${List.filled(columns, '<rt></rt>').join()}</rtc></ruby>',
        cache,
      );
      final work = ForumBodyRubyTreeEmphasisPlacementPreparation(
        input: input,
        ensureOwner: () {},
      );
      var parts = 0;
      while (!work.isReady) {
        parts += work.advance(maxParts: 1);
      }
      final first = work.takePlacement();
      work.close();
      expect(parts, lessThan(columns * 10));
      final second = _finish(
        ForumBodyRubyTreeEmphasisPlacementPreparation(
          input: input,
          ensureOwner: () {},
        ),
        quantum: 32,
      );
      expect(second.bounds, first.bounds);
      expect(
        second.marks.map(
          (m) => (m.row, m.baselineOrigin, m.fontOffset, m.fontBounds),
        ),
        first.marks.map(
          (m) => (m.row, m.baselineOrigin, m.fontOffset, m.fontBounds),
        ),
      );
    },
  );
}
