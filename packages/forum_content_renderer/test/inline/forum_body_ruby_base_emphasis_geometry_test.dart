import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double size) => size < 20 ? size * 1.45 : size * 1.12;
  @override
  double get textScaleFactor => throw StateError('Use per-size values');
}

typedef _Fixture = ({
  ForumBodyParagraphContent base,
  List<ForumBodyParagraphContent> annotations,
  List<ForumBodyParagraphContent> emptyAnnotations,
});

_Fixture _content({
  String text =
      'ffi 中 é <span style="font-size:15px;text-emphasis-position:under">'
      'الع 👩‍👩‍👧‍👦</span>',
  String emphasis = "'X' red",
  double size = 20,
  double height = .4,
  TextDirection direction = TextDirection.ltr,
  ForumBodyParagraphLayoutMode mode =
      ForumBodyParagraphLayoutMode.intrinsicSingleLine,
}) {
  final annotationHtml = [
    for (final empty in [false, true])
      for (var i = 0; i < 3; i++)
        '<p style="font-size:${8 + i * 3}px;line-height:.4">'
            '${empty ? '' : '注音'}</p>',
  ].join();
  final document = const ForumBodyParser().parse(
    html:
        '<p style="font-size:${size}px;line-height:$height;'
        'text-emphasis:$emphasis">$text</p>$annotationHtml',
    sourceId: 'ruby-base-emphasis',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
    ),
  );
  ForumBodyParagraphContent build(
    String path,
    ForumBodyParagraphLayoutMode mode,
  ) => const ForumBodyParagraphContentBuilder().build(
    document: document,
    styles: styles,
    path: path,
    layoutMode: mode,
  );
  return (
    base: build('0', mode),
    annotations: [
      for (var i = 1; i <= 3; i++)
        build('$i', ForumBodyParagraphLayoutMode.intrinsicSingleLine),
    ],
    emptyAnnotations: [
      for (var i = 4; i <= 6; i++)
        build('$i', ForumBodyParagraphLayoutMode.intrinsicSingleLine),
    ],
  );
}

ForumBodyEmphasisLineMetrics _line(
  ForumBodyParagraphCache cache, {
  TextScaler scaler = TextScaler.noScaling,
  _Fixture? content,
}) {
  final source = ForumBodyEmphasisTextPreparation(
    content: (content ?? _content()).base,
  );
  while (!source.isReady) {
    source.advance(maxParts: 1);
  }
  final job = ForumBodyEmphasisLineMetricsPreparation(
    input: source.takeInput(),
    cache: cache,
    ensureOwner: () {},
    textScaler: scaler,
  );
  addTearDown(job.close);
  while (!job.isReady) {
    final step = job.advance(maxParts: 1);
    expect(step.partsPrepared, lessThanOrEqualTo(1));
    expect(step.picturesRecorded, 0);
    expect(step.nativeLayoutsBuilt, lessThanOrEqualTo(1));
    expect(step.waitingForLayoutBudget, isFalse);
  }
  return job.takeMetrics();
}

ForumBodyRubyGroupMetrics _group(
  ForumBodyParagraphCache cache,
  ForumBodyEmphasisLineMetrics line, {
  required _Fixture fixture,
  List<ForumBodyRubySide> sides = const [ForumBodyRubySide.over],
  bool empty = false,
}) {
  final base = line.baseRequest.acquire(
    cache,
    width: line.requestWidth,
    textScaler: line.textScaler,
    cachedOnly: false,
  )!;
  final inputs = (empty ? fixture.emptyAnnotations : fixture.annotations)
      .take(sides.length)
      .toList();
  final annotations = <ForumBodyTextLease?>[];
  try {
    for (final input in inputs) {
      annotations.add(
        empty ? null : cache.acquire(content: input, width: line.requestWidth),
      );
    }
    return ForumBodyRubyGroupMetrics.measureLayers(
      cache: cache,
      baseLease: base,
      annotations: [
        for (var i = 0; i < inputs.length; i++)
          (
            content: inputs[i],
            lease: annotations[i],
            side: sides[i],
            gap: (i + 1).toDouble(),
          ),
      ],
    );
  } finally {
    base.release();
    for (final annotation in annotations) {
      annotation?.release();
    }
  }
}

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
            final fixture = _content(direction: direction, height: height);
            final line = _line(
              cache,
              content: fixture,
              scaler: nonlinear ? const _Nonlinear() : TextScaler.noScaling,
            );
            final group = _group(cache, line, fixture: fixture, sides: sides);
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
      final fixture = _content();
      final line = _line(cache, content: fixture);
      final populated = _group(
        cache,
        line,
        fixture: fixture,
        sides: [side, side],
      );
      final empty = _group(
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
    final fixture = _content(emphasis: 'none');
    final line = _line(cache, content: fixture);
    final group = _group(cache, line, fixture: fixture);
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
      final fixture = _content();
      final line = _line(cache, content: fixture),
          group = _group(cache, line, fixture: fixture);
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
    final line = _line(cache);
    final fixture = _content(size: 30);
    final other = _line(cache, content: fixture);
    final group = _group(cache, other, fixture: fixture);
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
        final line = _line(
          cache,
          content: _content(text: 'A', mode: mode),
        );
        final fixture = _content(text: 'A');
        final group = _group(
          cache,
          _line(cache, content: fixture),
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
    final fixture = _content();
    final line = _line(cache, content: fixture),
        group = _group(cache, line, fixture: fixture);
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
      final fixture = _content();
      final line = _line(cache, content: fixture),
          group = _group(cache, line, fixture: fixture);
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
      final fixture = _content();
      final line = _line(cache, content: fixture),
          group = _group(cache, line, fixture: fixture);
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
