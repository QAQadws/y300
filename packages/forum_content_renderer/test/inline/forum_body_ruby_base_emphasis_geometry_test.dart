import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_emphasis_fixture.dart';

ForumBodyRubyBaseEmphasisGeometry _finish(
  ForumBodyRubyBaseEmphasisPreparation job, {
  int quantum = 1,
}) {
  var steps = 0;
  while (!job.isReady) {
    expect(job.advance(maxParts: quantum), inInclusiveRange(1, quantum));
    expect(++steps, lessThan(10000));
  }
  return job.takeGeometry();
}

ForumBodyEmphasisSide _side(
  ForumBodyEmphasisLineMetrics line,
  ForumBodyEmphasisLineMark mark,
) => line
    .input
    .content
    .runs[line.input.units[mark.unitIndex].runIndex]
    .style
    .textEmphasis
    .side;

void _checkPlacement(ForumBodyRubyBaseEmphasisGeometry geometry) {
  final line = geometry.line, group = geometry.group;
  expect(geometry.marks.length, line.marks.length);
  expect(geometry.bounds.left, lessThanOrEqualTo(0));
  expect(geometry.bounds.top, lessThanOrEqualTo(0));
  expect(geometry.bounds.right, greaterThanOrEqualTo(group.size.width));
  expect(geometry.bounds.bottom, greaterThanOrEqualTo(group.size.height));
  final baselines = <ForumBodyEmphasisSide, double>{};
  for (final (i, placed) in geometry.marks.indexed) {
    final mark = line.marks[i], side = _side(line, mark);
    expect(placed.mark, same(mark));
    expect(placed.baselineOrigin.dx, group.baseOffset.dx);
    expect(placed.fontOffset.dx, mark.baseRelativeOffset.dx);
    expect(placed.fontOffset.dy, -mark.scaledAlphabeticBaseline);
    expect(
      placed.fontBounds,
      mark.scaledFontBounds
          .shift(placed.fontOffset)
          .shift(placed.baselineOrigin),
    );
    expect(
      placed.fontBounds.center.dx,
      closeTo(mark.fontBounds.center.dx + group.baseOffset.dx, 1e-8),
    );
    if (baselines.containsKey(side)) {
      expect(placed.baselineOrigin.dy, baselines[side]);
    }
    baselines[side] = placed.baselineOrigin.dy;
    final levels = group.annotations.where(
      (a) =>
          (a.side == ForumBodyRubySide.over) ==
          (side == ForumBodyEmphasisSide.over),
    );
    if (levels.isEmpty) {
      expect(
        placed.baselineOrigin.dy,
        group.baseOffset.dy + mark.baseRelativeAlphabeticBaseline,
      );
    } else if (side == ForumBodyEmphasisSide.over) {
      final edge = levels.fold(
        group.baseBandTop,
        (v, a) => math.min(v, a.bandTop),
      );
      expect(placed.fontBounds.bottom, lessThanOrEqualTo(edge + 1e-8));
    } else {
      final edge = levels.fold(
        group.baseBandBottom,
        (v, a) => math.max(v, a.bandBottom),
      );
      expect(placed.fontBounds.top, greaterThanOrEqualTo(edge - 1e-8));
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ForumBodyParagraphCache cache;
  setUp(
    () => cache = ForumBodyParagraphCache(
      maxEntries: 32,
      maxEstimatedBytes: 1 << 24,
    ),
  );
  tearDown(() => cache.close());
  const topologies = [
    [ForumBodyRubySide.over],
    [ForumBodyRubySide.under],
    [ForumBodyRubySide.over, ForumBodyRubySide.under, ForumBodyRubySide.over],
  ];
  for (final direction in TextDirection.values) {
    for (final height in [.4, 1.6]) {
      for (final nonlinear in [false, true]) {
        for (final sides in topologies) {
          test('actual marks outside reserved bands $direction $height '
              'nonlinear=$nonlinear $sides', () {
            final fixture = rubyEmphasisFixture(
              direction: direction,
              height: height,
            );
            final line = measureRubyEmphasisLine(
              cache,
              content: fixture,
              scaler: nonlinear
                  ? const RubyEmphasisNonlinearScaler()
                  : TextScaler.noScaling,
            );
            final group = measureRubyEmphasisGroup(
              cache,
              line,
              fixture: fixture,
              sides: sides,
            );
            expect(group.baseFontBounds, line.baseFontBounds);
            expect(group.baseFontBaseline, line.baseAlphabeticBaseline);
            final before = (
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.hitCount,
              cache.activeLeases,
            );
            final geometry = _finish(
              ForumBodyRubyBaseEmphasisPreparation(
                line: line,
                group: group,
                ensureOwner: () {},
              ),
            );
            _checkPlacement(geometry);
            expect((
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.hitCount,
              cache.activeLeases,
            ), before);
            expect(cache.pictureBuildCount, 0);
            expect(cache.activeLeases, 0);
            expect(geometry.line.input.content, same(line.input.content));
            expect(() => geometry.marks.clear(), throwsUnsupportedError);
          });
        }
      }
    }
  }
  for (final side in ForumBodyRubySide.values) {
    test('empty local RT keeps populated shared $side band', () {
      final fixture = rubyEmphasisFixture();
      final line = measureRubyEmphasisLine(cache, content: fixture);
      final populated = measureRubyEmphasisGroup(
        cache,
        line,
        fixture: fixture,
        sides: [side, side],
      );
      final empty = measureRubyEmphasisGroup(
        cache,
        line,
        fixture: fixture,
        sides: [side, side],
        empty: true,
      );
      final aligned = empty.alignedTo(
        ForumBodyRubyLevelMetrics.single(populated),
      );
      expect(aligned.baseFontBounds, empty.baseFontBounds);
      expect(aligned.baseFontBaseline, empty.baseFontBaseline);
      expect(aligned.annotations.every((a) => !a.hasAnnotation), isTrue);
      expect(
        aligned.annotations.last.bandBottom - aligned.annotations.last.bandTop,
        greaterThan(0),
      );
      final geometry = _finish(
        ForumBodyRubyBaseEmphasisPreparation(
          line: line,
          group: aligned,
          ensureOwner: () {},
        ),
      );
      _checkPlacement(geometry);
    });
  }
  test('inactive emphasis adds no marks or invented height', () {
    final fixture = rubyEmphasisFixture(emphasis: 'none');
    final line = measureRubyEmphasisLine(cache, content: fixture);
    final group = measureRubyEmphasisGroup(cache, line, fixture: fixture);
    final geometry = _finish(
      ForumBodyRubyBaseEmphasisPreparation(
        line: line,
        group: group,
        ensureOwner: () {},
      ),
    );
    expect(geometry.marks, isEmpty);
    expect(geometry.bounds, Offset.zero & group.size);
  });
  test(
    'numeric placement survives native eviction and borrowed cache closure',
    () {
      final fixture = rubyEmphasisFixture();
      final line = measureRubyEmphasisLine(cache, content: fixture),
          group = measureRubyEmphasisGroup(cache, line, fixture: fixture);
      cache.close();
      final geometry = _finish(
        ForumBodyRubyBaseEmphasisPreparation(
          line: line,
          group: group,
          ensureOwner: () {},
        ),
        quantum: 32,
      );
      _checkPlacement(geometry);
    },
  );
  test('incompatible glyph geometry is rejected before publication', () {
    final line = measureRubyEmphasisLine(cache);
    final fixture = rubyEmphasisFixture(size: 30);
    final other = measureRubyEmphasisLine(cache, content: fixture);
    final group = measureRubyEmphasisGroup(cache, other, fixture: fixture);
    expect(
      () => ForumBodyRubyBaseEmphasisPreparation(
        line: line,
        group: group,
        ensureOwner: () {},
      ),
      throwsA(isA<ForumBodyEmphasisLineException>()),
    );
    expect(cache.activeLeases, 0);
  });
  for (final mode in [
    ForumBodyParagraphLayoutMode.fitSingleLine,
    ForumBodyParagraphLayoutMode.wrap,
  ]) {
    test(
      'other source formats do not borrow intrinsic qualification $mode',
      () {
        final line = measureRubyEmphasisLine(
          cache,
          content: rubyEmphasisFixture(text: 'A', mode: mode),
        );
        final fixture = rubyEmphasisFixture(text: 'A');
        final group = measureRubyEmphasisGroup(
          cache,
          measureRubyEmphasisLine(cache, content: fixture),
          fixture: fixture,
        );
        expect(
          () => ForumBodyRubyBaseEmphasisPreparation(
            line: line,
            group: group,
            ensureOwner: () {},
          ),
          throwsA(isA<ForumBodyEmphasisLineException>()),
        );
      },
    );
  }
  test('retirement at every work boundary prevents late delivery', () {
    final fixture = rubyEmphasisFixture();
    final line = measureRubyEmphasisLine(cache, content: fixture),
        group = measureRubyEmphasisGroup(cache, line, fixture: fixture);
    var steps = 0;
    final initial = ForumBodyRubyBaseEmphasisPreparation(
      line: line,
      group: group,
      ensureOwner: () {},
    );
    while (!initial.isReady) {
      steps += initial.advance(maxParts: 1);
    }
    initial.close();
    for (var boundary = 0; boundary <= steps; boundary++) {
      var alive = true;
      final job = ForumBodyRubyBaseEmphasisPreparation(
        line: line,
        group: group,
        ensureOwner: () {
          if (!alive) throw StateError('Reader retired');
        },
      );
      for (var i = 0; i < boundary; i++) {
        job.advance(maxParts: 1);
      }
      alive = false;
      expect(
        job.isReady ? job.takeGeometry : () => job.advance(maxParts: 1),
        throwsStateError,
      );
      expect(job.takeGeometry, throwsStateError);
      job.close();
    }
    expect(cache.activeLeases, 0);
  });
  test(
    'publication callback can retire the worker without mutating delivery',
    () {
      final fixture = rubyEmphasisFixture();
      final line = measureRubyEmphasisLine(cache, content: fixture),
          group = measureRubyEmphasisGroup(cache, line, fixture: fixture);
      ForumBodyRubyBaseEmphasisPreparation? work;
      work = ForumBodyRubyBaseEmphasisPreparation(
        line: line,
        group: group,
        ensureOwner: () {
          if (work?.isReady == true) work!.close();
        },
      );
      expect(() => work!.advance(maxParts: 10000), throwsStateError);
      expect(work.takeGeometry, throwsStateError);
      expect(work.advance, throwsStateError);
      work.close();
    },
  );
  test(
    'reader callback cannot reenter or consume partially published work',
    () {
      final fixture = rubyEmphasisFixture();
      final line = measureRubyEmphasisLine(cache, content: fixture),
          group = measureRubyEmphasisGroup(cache, line, fixture: fixture);
      ForumBodyRubyBaseEmphasisPreparation? work;
      var calls = 0;
      work = ForumBodyRubyBaseEmphasisPreparation(
        line: line,
        group: group,
        ensureOwner: () {
          if (work == null) return;
          calls++;
          expect(work.advance, throwsStateError);
          expect(work.takeGeometry, throwsStateError);
        },
      );
      final result = _finish(work);
      _checkPlacement(result);
      expect(calls, greaterThan(2));
      work.close();
      expect(result.marks.length, line.marks.length);
    },
  );
}
