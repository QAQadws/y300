import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_group_metrics.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_row_alignment.dart';

import 'test_support/ruby_soft_space_row_fixture.dart';

void _drive(ForumBodyRubyRowAlignment work, RubySoftSpaceRowFixture f, int q) {
  final native = (
    f.cache.layoutBuildCount,
    f.cache.pictureBuildCount,
    f.cache.activeLeases,
  );
  for (var i = 0; !work.isComplete && !work.needsRows && i < 30000; i++) {
    expect(work.advance(maxParts: q), inInclusiveRange(1, q));
    expect((
      f.cache.layoutBuildCount,
      f.cache.pictureBuildCount,
      f.cache.activeLeases,
    ), native);
  }
  expect(work.isComplete || work.needsRows, isTrue);
}

ForumBodyRubyRowAlignment _work(RubySoftSpaceRowFixture f) =>
    ForumBodyRubyRowAlignment.atoms(
      atoms: f.atoms,
      levelIds: [0, 0, 0],
      atomOffsets: f.offsets,
    );

Future<List<int>> _pixels(void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder)..scale(3));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(360, 360);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List().toList();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

Rect _bounds(ForumBodyTextLease lease) => lease.layout
    .selectionBoxes(0, lease.content.projection.text.length)
    .fold(
      Rect.fromLTWH(0, 0, lease.layout.width, lease.layout.height),
      (bounds, box) => bounds.expandToInclude(box.toRect()),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 1.27]) {
      test(
        'independent native stack matches final glyph pixels DPR3 $direction scale=$scale',
        () async {
          final f = RubySoftSpaceRowFixture(
            direction: direction,
            textScaler: TextScaler.linear(scale),
          );
          addTearDown(f.close);
          final work = _work(f);
          _drive(work, f, 7);
          final width = f.atoms.fold<double>(0, (v, a) => v + a.size.width);
          final probe = f.parent(width, work.provisionalDimensions);
          work.attachRows(probe.layout.lines);
          _drive(work, f, 7);
          probe.releaseProvisional();
          final parent = f.parent(width, work.dimensions);
          final bases = [for (final parts in f.columnParts) f.native(parts[0])];
          final rt = [for (final parts in f.columnParts) f.native(parts[1])];
          final gap = f.native(f.softSpace.nativeRequests.single.content);
          ui.Paragraph? reference;
          try {
            final baseBounds = bases.map(_bounds).toList();
            final rtBounds = rt.map(_bounds).toList();
            final gapBounds = _bounds(gap);
            // Control geometry uses only independent native child font boxes,
            // original rank semantics and a directly built native SPACE parent.
            final baseAscent = List.generate(
              2,
              (i) => bases[i].layout.alphabeticBaseline - baseBounds[i].top,
            ).reduce(math.max);
            final baseDescent = List.generate(
              2,
              (i) => baseBounds[i].bottom - bases[i].layout.alphabeticBaseline,
            ).reduce(math.max);
            final annotationAscent = [
              gap.layout.alphabeticBaseline - gapBounds.top,
              for (var i = 0; i < 2; i++)
                rt[i].layout.alphabeticBaseline - rtBounds[i].top,
            ].reduce(math.max);
            final annotationDescent = [
              gapBounds.bottom - gap.layout.alphabeticBaseline,
              for (var i = 0; i < 2; i++)
                rtBounds[i].bottom - rt[i].layout.alphabeticBaseline,
            ].reduce(math.max);
            final over = baseAscent + annotationAscent + annotationDescent;
            final height = over + baseDescent;
            final widths = List.generate(
              2,
              (i) => math.max(baseBounds[i].width, rtBounds[i].width),
            );
            final builder = ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textDirection: direction,
                fontFamily: 'Ahem',
                fontSize: 20 * scale,
                height: 1,
              ),
            );
            builder.addPlaceholder(
              widths[0],
              height,
              PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              baselineOffset: over,
            );
            builder.pushStyle(
              ui.TextStyle(
                fontFamily: 'Ahem',
                fontSize: gapBounds.width,
                height: 0,
              ),
            );
            builder.addText(' ');
            builder.pop();
            builder.addPlaceholder(
              widths[1],
              height,
              PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              baselineOffset: over,
            );
            reference = builder.build()
              ..layout(ui.ParagraphConstraints(width: width));
            final slots = reference.getBoxesForPlaceholders();
            final space = reference.getBoxesForRange(1, 2).single;
            final origin = math.min(
              0.0,
              slots.map((b) => b.top).reduce(math.min),
            );
            // Native paragraph alphabeticBaseline and its fractional physical
            // line baseline round independently. Paint against the real row.
            final baseline =
                reference.computeLineMetrics().single.baseline - origin;
            final actual = await _pixels((c) {
              parent.layout.paintParent(c, Offset.zero);
              for (var i = 0; i < 3; i++) {
                final box = parent.layout.atomBoxes[i];
                final start = Offset(box.left, box.top);
                if (i == 1) {
                  final metrics =
                      (work.results[i] as ForumBodyRubySpaceMetrics).value;
                  gap.layout.paint(c, start + metrics.members.single.offset);
                } else {
                  final col =
                      (work.results[i] as ForumBodyRubyColumnMetrics).value;
                  bases[i ~/ 2].layout.paint(c, start + col.baseOffset);
                  rt[i ~/ 2].layout.paint(
                    c,
                    start + col.annotations.single.offset,
                  );
                }
              }
            });
            final expected = await _pixels((c) {
              for (var i = 0; i < 3; i++) {
                if (i == 1) {
                  gap.layout.paint(
                    c,
                    Offset(
                      space.left - gapBounds.left,
                      baseline -
                          baseAscent -
                          annotationDescent -
                          gap.layout.alphabeticBaseline,
                    ),
                  );
                } else {
                  final index = i ~/ 2;
                  bases[index].layout.paint(
                    c,
                    Offset(
                      slots[index].left +
                          (widths[index] - baseBounds[index].width) / 2 -
                          baseBounds[index].left,
                      baseline - bases[index].layout.alphabeticBaseline,
                    ),
                  );
                  rt[index].layout.paint(
                    c,
                    Offset(
                      slots[index].left +
                          (widths[index] - rtBounds[index].width) / 2 -
                          rtBounds[index].left,
                      baseline -
                          baseAscent -
                          annotationDescent -
                          rt[index].layout.alphabeticBaseline,
                    ),
                  );
                }
              }
            });
            var differences = 0;
            for (var i = 0; i < actual.length; i++) {
              if (actual[i] != expected[i]) differences++;
            }
            expect(
              differences,
              0,
              reason:
                  'Full RGBA comparison against independent native font stack',
            );
          } finally {
            reference?.dispose();
            for (final l in [...bases, ...rt, gap]) {
              l.release();
            }
            parent.release();
          }
        },
      );
    }
  }
  for (final direction in TextDirection.values) {
    for (final q in [1, 7, 32]) {
      for (final trimmed in [false, true]) {
        test(
          'actual gap fonts follow native rows and trimming $direction q=$q trimmed=$trimmed',
          () {
            final f = RubySoftSpaceRowFixture(
              direction: direction,
              gapSize: trimmed ? 300 : 40,
              textScaler: const TextScaler.linear(1.27),
            );
            addTearDown(f.close);
            final work = _work(f);
            _drive(work, f, q);
            expect(work.needsRows, isTrue);
            expect(work.hasSoftSpaces, isTrue);
            expect(
              work.provisionalDimensions[1].size,
              Size(f.spaceMetrics.size.width, 0),
            );
            expect(work.provisionalDimensions[1].baselineOffset, 0);
            expect(work.dimensions[1].size, f.spaceMetrics.size);
            expect(work.dimensions[1].baselineOffset, f.spaceMetrics.baseline);
            final width = trimmed
                ? f.columnMetrics.first.size.width
                : f.atoms.fold<double>(0, (v, a) => v + a.size.width);
            final before = f.cache.layoutBuildCount;
            final probe = f.parent(width, work.provisionalDimensions);
            expect(probe.layout.lines.length, trimmed ? 2 : 1);
            final mask = probe.layout.trimmedAtomIndices.toSet();
            expect(mask, trimmed ? {1} : isEmpty);
            work.attachRows(probe.layout.lines, trimmedAtomIndices: mask);
            mask.clear(); // The native snapshot must survive caller mutation.
            _drive(work, f, q);
            expect(work.isComplete, isTrue);
            expect(work.hasChanges, !trimmed);
            expect(work.requiresFinalParent, isTrue);
            if (trimmed) {
              expect(work.targets, [null, null, null]);
              expect(
                (work.results[0] as ForumBodyRubyColumnMetrics).value,
                same(f.columnMetrics[0]),
              );
              expect(
                (work.results[1] as ForumBodyRubySpaceMetrics).value,
                same(f.spaceMetrics),
              );
              expect(
                (work.results[2] as ForumBodyRubyColumnMetrics).value,
                same(f.columnMetrics[1]),
              );
            } else {
              final target = work.targets[0]!;
              expect(target.baseAscent, f.columnMetrics.first.baseAscent);
              expect(target.baseDescent, f.columnMetrics.first.baseDescent);
              expect(
                target.annotations.single.ascent,
                f.spaceMetrics.level.annotations.single.ascent,
              );
              expect(
                target.annotations.single.descent,
                f.spaceMetrics.level.annotations.single.descent,
              );
              for (final atom in work.results) {
                expect(atom.size.height, work.results.first.size.height);
                expect(atom.baseline, work.results.first.baseline);
              }
            }
            final probeHeight = probe.layout.height;
            probe.releaseProvisional();
            final parent = f.parent(width, work.dimensions);
            try {
              final finalMask = parent.layout.trimmedAtomIndices.toSet();
              while (!work.isVerified) {
                expect(
                  work.verifyRows(
                    parent.layout.lines,
                    maxParts: q,
                    trimmedAtomIndices: finalMask,
                  ),
                  inInclusiveRange(1, q),
                );
              }
              expect(
                parent.layout
                    .fragment(0, parent.layout.lines.length)
                    .atomIndices,
                trimmed ? [0, 2] : [0, 1, 2],
              );
              if (trimmed) expect(parent.layout.height, probeHeight);
              expect(f.cache.layoutBuildCount, before + 2);
              final actualBuilds = f.cache.layoutBuildCount;
              final warm = f.parent(width, work.dimensions);
              expect(identical(warm.layout, parent.layout), isTrue);
              expect(f.cache.layoutBuildCount, actualBuilds);
              warm.release();
            } finally {
              parent.release();
            }
            f.close();
          },
        );
      }
    }
  }

  test(
    'a visible base-only font reserves neighbours even without any RT glyph',
    () {
      final f = RubySoftSpaceRowFixture(
        baseGap: true,
        annotationGap: false,
        emptyAnnotations: true,
        gapSize: 80,
      );
      addTearDown(f.close);
      final work = _work(f);
      _drive(work, f, 1);
      final probe = f.parent(120, work.provisionalDimensions);
      expect(probe.layout.lines.length, 1);
      work.attachRows(probe.layout.lines);
      _drive(work, f, 1);
      expect(work.hasChanges, isTrue);
      expect(
        work.targets.every(
          (t) => t!.baseAscent == f.spaceMetrics.level.baseAscent,
        ),
        isTrue,
      );
      expect(work.results.every((m) => m.size.height == 80), isTrue);
      expect(
        work.results.whereType<ForumBodyRubyColumnMetrics>().every(
          (m) => !m.value.hasAnnotation,
        ),
        isTrue,
      );
      probe.releaseProvisional();
      final parent = f.parent(120, work.dimensions);
      expect(parent.layout.height, 80);
      expect(work.verifyRows(parent.layout.lines, maxParts: 7), 3);
      parent.release();
    },
  );

  for (final q in [1, 7, 32]) {
    test(
      'dense actual ranks keep numeric work bounded and exclude trimmed fonts q=$q',
      () {
        // 80 actual RTCs/160 RTs/80 gaps fit the unchanged raw structure limit.
        final f = RubySoftSpaceRowFixture(ranks: 80, gapSize: 1);
        addTearDown(f.close);
        final work = _work(f);
        _drive(work, f, q);
        final probe = f.parent(41, work.provisionalDimensions);
        work.attachRows(probe.layout.lines);
        _drive(work, f, q);
        expect(work.results.length, 3);
        final result = (work.results[1] as ForumBodyRubySpaceMetrics).value;
        expect(result.members.length, 80);
        expect(
          result.members.map((m) => m.input),
          f.spaceMetrics.members.map((m) => m.input),
        );
        expect(
          result.members.map((m) => m.offset.dx),
          f.spaceMetrics.members.map((m) => m.offset.dx),
        );
        expect(result.level.baseAscent, f.columnMetrics.first.baseAscent);
        probe.releaseProvisional();
        final parent = f.parent(41, work.dimensions);
        while (!work.isVerified) {
          work.verifyRows(parent.layout.lines, maxParts: q);
        }
        parent.release();
      },
    );
  }

  for (var bad = 0; bad < 5; bad++) {
    test(
      'trim masks cannot omit opaque fonts or change final coverage mode=$bad',
      () {
        final f = RubySoftSpaceRowFixture(gapSize: 300);
        addTearDown(f.close);
        final work = _work(f);
        _drive(work, f, 7);
        final probe = f.parent(20, work.provisionalDimensions);
        work.attachRows(
          probe.layout.lines,
          trimmedAtomIndices: bad == 0
              ? {0, 1}
              : bad == 1
              ? {1, 5}
              : {1},
        );
        if (bad < 2) {
          expect(
            () => _drive(work, f, 1),
            throwsA(isA<ForumBodyParagraphLayoutException>()),
          );
        } else {
          _drive(work, f, 7);
          final parent = f.parent(20, work.dimensions);
          expect(
            () => work.verifyRows(
              bad == 4
                  ? parent.layout.lines.take(1).toList()
                  : parent.layout.lines,
              maxParts: 7,
              trimmedAtomIndices: bad == 2
                  ? {}
                  : bad == 3
                  ? {0}
                  : {1},
            ),
            throwsA(isA<ForumBodyParagraphLayoutException>()),
          );
          parent.release();
        }
        probe.releaseProvisional();
      },
    );
  }

  test('even equal columns and a tiny gap force real row discovery', () {
    final f = RubySoftSpaceRowFixture(gapSize: 1);
    addTearDown(f.close);
    final work = _work(f);
    _drive(work, f, 32);
    expect(work.needsRows, isTrue);
    final parent = f.parent(20, work.provisionalDimensions);
    work.attachRows(parent.layout.lines, trimmedAtomIndices: {1});
    _drive(work, f, 1);
    expect(work.hasChanges, isFalse);
    expect(work.requiresFinalParent, isTrue);
    expect(() => work.columns, throwsStateError);
    parent.releaseProvisional();
  });

  test('gap alignment validates every original rank before any result', () {
    final f = RubySoftSpaceRowFixture(ranks: 3, gapSize: 1);
    final other = RubySoftSpaceRowFixture(ranks: 3, gapSize: 2);
    addTearDown(f.close);
    addTearDown(other.close);
    final target = other.spaceMetrics.level;
    final job = ForumBodyRubySoftSpaceAlignment(
      softSpace: f.spaceMetrics,
      level: target,
      prepareResult: true,
    );
    final before = (f.cache.layoutBuildCount, f.cache.pictureBuildCount);
    while (!job.isComplete) {
      expect(job.advance(maxParts: 1), 1);
    }
    expect(job.hasChanges, isTrue);
    expect(
      job.result.members.map((m) => m.input),
      f.spaceMetrics.members.map((m) => m.input),
    );
    expect(job.result.size.width, f.spaceMetrics.size.width);
    expect((f.cache.layoutBuildCount, f.cache.pictureBuildCount), before);
    expect(() => job.advance(maxParts: 1), throwsStateError);
    final bad = RubySoftSpaceRowFixture(
      ranks: 3,
      gapSize: 2,
      flipLastSide: true,
    );
    addTearDown(bad.close);
    final invalid = ForumBodyRubySoftSpaceAlignment(
      softSpace: f.spaceMetrics,
      level: bad.spaceMetrics.level,
      prepareResult: true,
    );
    expect(invalid.advance(maxParts: 1), 1);
    expect(invalid.advance(maxParts: 1), 1);
    expect(
      () => invalid.advance(maxParts: 1),
      throwsA(isA<ForumBodyRubyGroupException>()),
    );
    expect(() => invalid.result, throwsStateError);
    expect(() => invalid.advance(maxParts: 1), throwsStateError);
  });

  test('zero-height admission belongs only to the mechanical soft slot', () {
    final f = RubySoftSpaceRowFixture();
    addTearDown(f.close);
    final work = _work(f);
    _drive(work, f, 7);
    final dims = work.provisionalDimensions.toList();
    dims[0] = const PlaceholderDimensions(
      size: Size(20, 0),
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      baselineOffset: 0,
    );
    final before = f.cache.layoutBuildCount;
    expect(() => f.parent(80, dims), throwsArgumentError);
    expect(f.cache.layoutBuildCount, before);
    final wrong = work.provisionalDimensions.toList();
    wrong[1] = PlaceholderDimensions(
      size: wrong[1].size,
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      baselineOffset: 1,
    );
    expect(() => f.parent(80, wrong), throwsArgumentError);
    expect(f.cache.layoutBuildCount, before);
  });

  for (var bad = 0; bad < 4; bad++) {
    test(
      'a soft gap must have real adjacent same-root opaque atoms mode=$bad',
      () {
        final f = RubySoftSpaceRowFixture();
        addTearDown(f.close);
        final work = ForumBodyRubyRowAlignment.atoms(
          atoms: bad == 0
              ? f.atoms.sublist(1)
              : bad == 1
              ? [f.atoms[0], f.atoms[1], f.atoms[1], f.atoms[2]]
              : f.atoms,
          levelIds: bad == 0
              ? [0, 0]
              : bad == 1
              ? [0, 0, 0, 0]
              : bad == 2
              ? [0, 1, 0]
              : [0, 0, 0],
          atomOffsets: bad == 0
              ? [0, 1]
              : bad == 1
              ? [0, 1, 2, 3]
              : bad == 3
              ? [0, 1, 3]
              : f.offsets,
        );
        expect(
          () => _drive(work, f, 1),
          throwsA(isA<ForumBodyParagraphLayoutException>()),
        );
      },
    );
  }
}
