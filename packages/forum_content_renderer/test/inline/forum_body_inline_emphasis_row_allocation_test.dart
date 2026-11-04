import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

typedef _Input = ({
  ForumBodyInlineEmphasisIsolationMetrics input,
  ForumBodyInlineParagraphLease natural,
  ForumBodyInlineParagraphLease isolated,
});

ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 512,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(cache.close);
  return cache;
}

_Input _isolate(
  ForumBodyInlineEmphasisParentPreparation parent,
  ForumBodyParagraphCache cache, {
  double pitch = 256,
}) {
  try {
    while (!parent.isReady) {
      parent.advance(maxParts: 32);
    }
    final natural = parent.takeMeasurement();
    addTearDown(natural.parent.release);
    final job = ForumBodyInlineEmphasisIsolationPreparation(
      metrics: natural.metrics,
      natural: natural.parent,
      cache: cache,
      ensureOwner: () {},
      rowIsolationPitch: pitch,
    );
    try {
      while (!job.isReady) {
        job.advance(maxParts: 32);
      }
      final isolated = job.takeMeasurement();
      addTearDown(isolated.parent.release);
      return (
        input: isolated.metrics,
        natural: natural.parent,
        isolated: isolated.parent,
      );
    } finally {
      job.close();
    }
  } finally {
    parent.close();
  }
}

_Input _input(
  ForumBodyParagraphCache cache, {
  String? child,
  String side = 'over',
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  double width = 70,
  double pitch = 256,
}) {
  final fixture = MixedEmphasisParentFixture(
    child ?? mixedEmphasisChildren[1],
    width: width,
    direction: direction,
    prefix: '<span style="font-size:120px;text-emphasis:none">W</span>PP',
    suffix: 'QQ',
    parentStyle:
        'text-emphasis:circle;text-emphasis-position:$side;line-height:.4',
  );
  return _isolate(
    ForumBodyInlineEmphasisParentPreparation(
      input: fixture.input,
      cache: cache,
      textScaler: scaler,
      ensureOwner: () {},
    ),
    cache,
    pitch: pitch,
  );
}

_Input _html(
  ForumBodyParagraphCache cache,
  String body, {
  double width = 300,
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  double fontSize = 20,
  double pitch = 256,
  bool intrinsic = false,
  TextStyle? textStyle,
}) {
  final doc = const ForumBodyParser().parse(
    html:
        '<p dir="${direction.name}" style="white-space:pre-wrap;text-emphasis:circle;line-height:.4">$body</p>',
    sourceId: 'mixed-allocation',
    conversionIdentity: 'none',
  );
  final cursor = ForumBodyTextFlowCursor(
    document: doc,
    reader: ForumBodyReaderStyle(
      textStyle:
          textStyle ??
          TextStyle(
            fontFamily: 'Ahem',
            fontSize: fontSize,
            color: const Color(0xff123456),
          ),
      textDirection: direction,
      fontRevision: 'mixed-allocation',
      linkColor: const Color(0xff0000ff),
    ),
  );
  ForumBodyInlineFlowContent? flow;
  try {
    while (!cursor.isComplete) {
      cursor.advance(maxEvents: 1);
      if (cursor.current case ForumBodyTextFlowInline(:final content)) {
        flow = content;
        break;
      }
    }
  } finally {
    cursor.close();
  }
  if (intrinsic) {
    final f = flow!;
    flow = ForumBodyInlineFlowContent(
      identity: f.identity,
      path: f.path,
      fontRevision: f.fontRevision,
      styleRevision: f.styleRevision,
      style: f.style,
      layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      parts: f.parts,
      ignored: f.ignored,
      issues: f.issues,
    );
  }
  return _isolate(
    ForumBodyInlineEmphasisParentPreparation.fromFlow(
      input: flow!,
      width: width,
      cache: cache,
      textScaler: scaler,
      ensureOwner: () {},
    ),
    cache,
    pitch: pitch,
  );
}

ForumBodyInlineEmphasisRowAllocationPreparation _work(
  _Input input, {
  void Function()? guard,
}) => ForumBodyInlineEmphasisRowAllocationPreparation(
  input: input.input,
  natural: input.natural,
  isolated: input.isolated,
  ensureOwner: guard ?? () {},
);
({ForumBodyInlineEmphasisRowAllocation value, int parts}) _finish(
  ForumBodyInlineEmphasisRowAllocationPreparation job,
  ForumBodyParagraphCache cache, {
  int quantum = 1,
}) {
  final before = (
    cache.layoutBuildCount,
    cache.pictureBuildCount,
    cache.activeLeases,
  );
  var parts = 0;
  try {
    for (var n = 0; !job.isReady; n++) {
      expect(n, lessThan(200000));
      final used = job.advance(maxParts: quantum);
      expect(used, inInclusiveRange(1, quantum));
      parts += used;
    }
    expect(job.advance(maxParts: 1), 0);
    final value = job.takeAllocation();
    expect((
      cache.layoutBuildCount,
      cache.pictureBuildCount,
      cache.activeLeases,
    ), before);
    return (value: value, parts: parts);
  } finally {
    job.close();
  }
}

void _verify(ForumBodyInlineEmphasisRowAllocation value, _Input input) {
  expect(value.input, same(input.input));
  expect(value.rows.length, input.natural.layout.lineCount);
  expect(value.marks.length, input.input.natural.text.units.length);
  expect(value.children.length, input.input.natural.page.rubyAtoms.length);
  var end = 0.0;
  for (final (i, row) in value.rows.indexed) {
    final original = input.natural.layout.lines[i], actual = row.line;
    expect(actual.top, end);
    expect(actual.bottom, greaterThanOrEqualTo(actual.top));
    end = actual.bottom;
    expect(actual.baseline, original.baseline + row.naturalOffset.dy);
    expect(
      actual.baseline,
      input.isolated.layout.lines[i].baseline + row.logicalOffset.dy,
    );
    expect(actual.baseline, row.isolatedGlyphBaseline + row.glyphOffset.dy);
    expect(actual.startUtf16, original.startUtf16);
    expect(actual.endUtf16, original.endUtf16);
    expect(actual.coverageStartUtf16, original.coverageStartUtf16);
    expect(actual.coverageEndUtf16, original.coverageEndUtf16);
    expect(actual.engineCoverageStartUtf16, original.engineCoverageStartUtf16);
    expect(actual.engineCoverageEndUtf16, original.engineCoverageEndUtf16);
    expect(actual.engineStartUtf16, original.engineStartUtf16);
    expect(actual.engineEndUtf16, original.engineEndUtf16);
    expect(
      actual.unpaintedTrailingSpaceStartUtf16,
      original.unpaintedTrailingSpaceStartUtf16,
    );
    expect(
      actual.engineUnpaintedTrailingSpaceStartUtf16,
      original.engineUnpaintedTrailingSpaceStartUtf16,
    );
    expect(actual.canBreakBefore, original.canBreakBefore);
    expect(actual.canBreakAfter, original.canBreakAfter);
    expect((actual.left, actual.width), (original.left, original.width));
    expect(row.authoredAdvance, greaterThanOrEqualTo(0));
    final bounds = row.bounds;
    if (bounds != null) {
      expect(bounds.top, greaterThanOrEqualTo(actual.top - 1e-7));
      expect(bounds.bottom, lessThanOrEqualTo(actual.bottom + 1e-7));
    }
  }
  expect(value.height, end);
  for (final mark in value.marks) {
    final row = value.rows[mark.lineIndex];
    final original =
        input.input.natural.reflow.children.placement.marks[mark.unitIndex];
    final shift =
        Offset(0, input.input.natural.reflow.baselineDeltas[mark.lineIndex]) +
        row.naturalOffset;
    expect(mark.fontBounds, original.fontBounds.shift(shift));
    expect(mark.offset, original.baselineOrigin + original.fontOffset + shift);
    expect(mark.fontBounds.top, greaterThanOrEqualTo(row.line.top - 1e-7));
    expect(mark.fontBounds.bottom, lessThanOrEqualTo(row.line.bottom + 1e-7));
  }
  for (final (i, child) in value.children.indexed) {
    expect(
      child == null,
      input.input.natural.page.trimmedAtomIndices.contains(i),
    );
    if (child != null) {
      final row = value.rows[child.lineIndex],
          size = input.input.natural.page.dimensions[i];
      expect(child.atomIndex, i);
      expect(
        child.offset,
        input.natural.layout.atomBoxes[i].toRect().topLeft + row.naturalOffset,
      );
      expect(child.bounds.height, greaterThanOrEqualTo(size.size.height));
      expect(child.bounds.top, greaterThanOrEqualTo(row.line.top - 1e-7));
      expect(child.bounds.bottom, lessThanOrEqualTo(row.line.bottom + 1e-7));
      expect(
        child.offset.dy + size.baselineOffset!,
        closeTo(row.line.baseline, 1e-3),
      );
    }
  }
}

Future<Uint8List> _raster(
  void Function(Canvas) paint,
  Size size,
  double dpr,
) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder)..scale(dpr));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      (size.width * dpr).ceil(),
      (size.height * dpr).ceil(),
    );
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final (i, child) in mixedEmphasisChildren.indexed) {
    for (final side in ['over', 'under']) {
      for (final direction in TextDirection.values) {
        for (final scaler in [
          TextScaler.noScaling,
          const MixedEmphasisCurve(),
        ]) {
          for (final width in [70.0, 300.0]) {
            test(
              'mixed physical allocation $i/$side/$direction/$scaler/$width',
              () {
                final cache = _cache(),
                    input = _input(
                      cache,
                      child: child,
                      side: side,
                      direction: direction,
                      scaler: scaler,
                      width: width,
                    );
                final value = _finish(
                  _work(input),
                  cache,
                  quantum: i.isEven ? 1 : 17,
                ).value;
                _verify(value, input);
                expect(() => value.rows.clear(), throwsUnsupportedError);
                expect(() => value.marks.clear(), throwsUnsupportedError);
                expect(() => value.children.clear(), throwsUnsupportedError);
                expect(
                  input.natural.isActive && input.isolated.isActive,
                  isTrue,
                );
              },
            );
          }
        }
      }
    }
  }
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
      test('intrinsic source allocation $direction/$scaler', () {
        final cache = _cache(),
            input = _html(
              cache,
              'P${mixedEmphasisChildren[1]}Q',
              direction: direction,
              scaler: scaler,
              intrinsic: true,
            );
        final value = _finish(_work(input), cache).value;
        _verify(value, input);
        expect(value.rows.length, 1);
        expect(value.width, input.natural.layout.width);
      });
    }
  }
  for (final body in [
    'P\n\n${mixedEmphasisChildren[1]}Q\n',
    'P${mixedEmphasisChildren[0]}Q\n',
    '👩‍👩‍👧‍👦é<ruby style="font-size:5px;text-emphasis:none">A<rt>x</rt></ruby>Q',
  ]) {
    test('actual empty/source row frames $body', () {
      final cache = _cache(),
          input = _html(cache, body, width: body.startsWith('👩') ? 10 : 300);
      final value = _finish(_work(input), cache).value;
      _verify(value, input);
      if (body.startsWith('👩')) {
        expect(
          value.rows.any(
            (r) => !r.line.canBreakBefore || !r.line.canBreakAfter,
          ),
          isTrue,
        );
      }
    });
  }
  test(
    'complete tall child reserve excludes native outer overhang from authored flow',
    () {
      final cache = _cache(),
          input = _html(
            cache,
            'P<ruby style="line-height:1000px;text-emphasis:none">A<rt>x</rt></ruby>Q\nP',
          );
      final value = _finish(_work(input), cache).value;
      _verify(value, input);
      expect(
        value.children
            .whereType<ForumBodyInlineEmphasisAllocatedChild>()
            .single
            .bounds
            .height,
        greaterThanOrEqualTo(1000),
      );
      expect(input.isolated.layout.nativeFlowTop, greaterThan(0));
    },
  );
  test('long actual paragraph retains every mark and source row', () {
    final cache = _cache(),
        input = _html(cache, '${'P' * 4200}${mixedEmphasisChildren[0]}Q');
    final value = _finish(_work(input), cache, quantum: 53).value;
    _verify(value, input);
    expect(value.marks.length, 4201);
  });
  test('trimmed real soft slots keep their indices without a visual child', () {
    final cache = _cache(),
        input = _input(cache, child: mixedEmphasisChildren[5], width: 40);
    final value = _finish(_work(input), cache).value;
    _verify(value, input);
    expect(input.input.natural.page.trimmedAtomIndices, isNotEmpty);
    for (final i in input.input.natural.page.trimmedAtomIndices) {
      expect(value.children[i], isNull);
    }
  });
  test(
    'fractional font rows retain stable glyph offsets at large native coordinates',
    () {
      final cache = _cache(),
          input = _html(
            cache,
            '${'P\n' * 300}${mixedEmphasisChildren[1]}Q',
            fontSize: 31.3,
          );
      final value = _finish(_work(input), cache, quantum: 31).value;
      _verify(value, input);
      expect(value.rows.length, 301);
      expect(value.rows.last.isolatedGlyphBaseline, greaterThan(76000));
    },
  );
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
      for (final pitch in [256.0, 256.3]) {
        test(
          'native glyph offsets match independent single-row pixels $direction/$scaler/$pitch',
          () async {
            final cache = _cache(),
                input = _html(
                  cache,
                  'P\nP\nP\n${mixedEmphasisChildren[0]}',
                  fontSize: 31.3,
                  direction: direction,
                  scaler: scaler,
                  pitch: pitch,
                );
            final allocation = _finish(_work(input), cache).value;
            final view = ForumBodyInlineEmphasisAllocatedParentView.bind(
              parent: input.isolated,
              allocation: allocation,
              ensureOwner: () {},
            );
            final recorder = ui.PictureRecorder();
            try {
              expect(
                () => view.paintParentRow(Canvas(recorder), Offset.zero, 0),
                throwsStateError,
              );
            } finally {
              recorder.endRecording().dispose();
            }
            cache.prepareInlineParentPaint(input.isolated);
            final single = TextPainter(
              text: TextSpan(
                text: 'P',
                style:
                    input.input.natural.text.glyphInput.glyphs.style.textStyle,
              ),
              textDirection: direction,
              textAlign: TextAlign.left,
              textScaler: scaler,
            )..layout(maxWidth: 300);
            try {
              final baseline = single
                  .computeDistanceToActualBaseline(TextBaseline.alphabetic)
                  .roundToDouble();
              final size = Size(500, allocation.height + 250);
              for (final dpr in [1.0, 3.0]) {
                final actual = await _raster(
                  (c) {
                    for (var i = 0; i < allocation.rows.length; i++) {
                      view.paintParentRow(c, const Offset(100, 100), i);
                    }
                  },
                  size,
                  dpr,
                );
                final expected = await _raster(
                  (c) {
                    for (final row in allocation.rows) {
                      if (row.parentFontBounds != null) {
                        single.paint(
                          c,
                          Offset(
                            100 + row.line.left,
                            100 + row.line.baseline - baseline,
                          ),
                        );
                      }
                    }
                  },
                  size,
                  dpr,
                );
                expect(actual, orderedEquals(expected));
                expect(
                  [
                    for (var i = 3; i < actual.length; i += 4) actual[i],
                  ].any((a) => a != 0),
                  isTrue,
                );
              }
            } finally {
              single.dispose();
            }
          },
        );
      }
    }
  }
  for (final style in [
    const TextStyle(
      fontFamily: 'Ahem',
      fontSize: 20,
      backgroundColor: Color(0xffff0000),
    ),
    const TextStyle(
      fontFamily: 'Ahem',
      fontSize: 20,
      decoration: TextDecoration.underline,
    ),
  ]) {
    for (final parentText in [true, false]) {
      test(
        'logical parent paint requires phase binding $style/$parentText',
        () {
          final cache = _cache(),
              input = _html(
                cache,
                parentText
                    ? 'P${mixedEmphasisChildren[0]}Q'
                    : mixedEmphasisChildren[0],
                textStyle: style,
              );
          final value = _finish(_work(input), cache).value;
          _verify(value, input);
          expect(value.requiresParentPaintPhases, isTrue);
          for (final (i, row) in value.rows.indexed) {
            final logical = input.input.logicalRows.rows[i].paintBounds?.shift(
              row.logicalOffset,
            );
            if (logical != null) {
              expect(row.paintBounds!.intersect(logical), logical);
              expect(value.paintBounds!.intersect(logical), logical);
            }
          }
          if (!parentText) {
            expect(value.rows.single.parentFontBounds, isNull);
            expect(value.rows.single.paintBounds, isNotNull);
          }
          expect(
            () => ForumBodyInlineEmphasisAllocatedParentView.bind(
              parent: input.isolated,
              allocation: value,
              ensureOwner: () {},
            ),
            throwsA(isA<ForumBodyEmphasisAllocationException>()),
          );
          expect(cache.activeLeases, 2);
        },
      );
    }
  }
  test(
    'every advance and guard retirement leaves both borrowed leases active',
    () {
      final cache = _cache(), input = _input(cache);
      final count = _finish(_work(input), cache).parts;
      for (var stop = 0; stop <= count; stop++) {
        var retired = false;
        final work = _work(
          input,
          guard: () {
            if (retired) throw StateError('retired');
          },
        );
        for (var n = 0; n < stop && !work.isReady; n++) {
          work.advance(maxParts: 1);
        }
        retired = true;
        expect(() => work.advance(maxParts: 1), throwsStateError);
        work.close();
        expect(cache.activeLeases, 2);
      }
      var total = 0;
      final work = _work(
        input,
        guard: () {
          total++;
        },
      );
      while (!work.isReady) {
        work.advance(maxParts: 17);
      }
      work.takeAllocation();
      for (var stop = 1; stop <= total; stop++) {
        var n = 0;
        ForumBodyInlineEmphasisRowAllocationPreparation? active;
        try {
          active = _work(
            input,
            guard: () {
              if (++n == stop) {
                active?.close();
                throw StateError('retired');
              }
            },
          );
          while (!active.isReady) {
            active.advance(maxParts: 17);
          }
          active.takeAllocation();
        } on StateError {
          /* Retired at the requested guard. */
        } finally {
          active?.close();
        }
        expect(cache.activeLeases, 2);
        expect(n, greaterThanOrEqualTo(stop));
      }
    },
  );
  for (final limit in ['lines', 'atoms', 'marks', 'boxes', 'height']) {
    test('$limit cap preserves borrowed resources', () {
      final cache = _cache(), input = _input(cache);
      expect(
        () {
          final work = ForumBodyInlineEmphasisRowAllocationPreparation(
            input: input.input,
            natural: input.natural,
            isolated: input.isolated,
            ensureOwner: () {},
            maxLines: limit == 'lines' ? 1 : 4096,
            maxAtoms: limit == 'atoms' ? 0 : 512,
            maxMarks: limit == 'marks' ? 0 : 32768,
            maxBoxes: limit == 'boxes' ? 0 : 32768,
            maxHeight: limit == 'height' ? 1 : 1048576,
          );
          try {
            while (!work.isReady) {
              work.advance(maxParts: 1);
            }
          } finally {
            work.close();
          }
        },
        throwsA(
          isA<ForumBodyEmphasisAllocationException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyEmphasisAllocationFailure.limit,
          ),
        ),
      );
      expect(cache.activeLeases, 2);
    });
  }
  test(
    'foreign/stale source and ready retirement never authorize parent drawing',
    () {
      final cache = _cache(),
          foreign = _cache(),
          input = _input(cache),
          other = _input(foreign);
      expect(
        () => ForumBodyInlineEmphasisRowAllocationPreparation(
          input: input.input,
          natural: other.natural,
          isolated: input.isolated,
          ensureOwner: () {},
        ),
        throwsA(isA<ForumBodyEmphasisAllocationException>()),
      );
      final value = _finish(_work(input), cache).value;
      expect(
        () => ForumBodyInlineEmphasisAllocatedParentView.bind(
          parent: other.isolated,
          allocation: value,
          ensureOwner: () {},
        ),
        throwsA(isA<ForumBodyEmphasisAllocationException>()),
      );
      final work = _work(input);
      while (!work.isReady) {
        work.advance(maxParts: 17);
      }
      input.natural.release();
      expect(work.takeAllocation, throwsStateError);
      final view = ForumBodyInlineEmphasisAllocatedParentView.bind(
        parent: input.isolated,
        allocation: value,
        ensureOwner: () {},
      );
      input.isolated.release();
      final recorder = ui.PictureRecorder();
      try {
        expect(
          () => view.paintParentRow(Canvas(recorder), Offset.zero, 0),
          throwsStateError,
        );
      } finally {
        recorder.endRecording().dispose();
      }
      expect(cache.activeLeases, 0);
    },
  );
}
