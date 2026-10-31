import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_inline_fixture.dart';

const _dimension = PlaceholderDimensions(
  size: Size(40, 30),
  alignment: ui.PlaceholderAlignment.baseline,
  baseline: TextBaseline.alphabetic,
  baselineOffset: 26,
);

Future<List<int>> _rasterParent(ForumBodyInlineParagraphFragment window) async {
  final recorder = ui.PictureRecorder();
  window.paintParent(Canvas(recorder), Offset.zero);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      window.layout.width.ceil(),
      window.height.ceil(),
    );
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a terminal empty mixed row cannot paint a previous ordinary glyph',
    () async {
      final input = mixedInlineInput(
        suffix: 'Y<br>',
        paragraphStyle: 'line-height:.25',
      );
      final layout = ForumBodyInlineParagraphLayout.create(
        content: input.content,
        width: 40,
        dimensions: [_dimension],
      );
      addTearDown(layout.dispose);
      final last = layout.lines.length - 1;
      final empty = layout.fragment(last, last + 1);
      expect(empty.height, greaterThan(0));
      expect(empty.coverageStartUtf16, empty.coverageEndUtf16);
      expect(empty.engineCoverageStartUtf16, empty.engineCoverageEndUtf16);
      expect(empty.atomIndices, isEmpty);
      final visible = await _rasterParent(layout.fragment(last - 1, last));
      expect(visible.any((value) => value != 0), isTrue);
      final pixels = await _rasterParent(empty);
      expect(pixels.every((value) => value == 0), isTrue);
      layout.dispose();
      final recorder = ui.PictureRecorder();
      expect(
        () => empty.paintParent(Canvas(recorder), Offset.zero),
        throwsStateError,
      );
      recorder.endRecording().dispose();
    },
  );

  test(
    'actual mixed lines and fragments preserve distinct display and engine ranges',
    () {
      final input = mixedInlineInput();
      final layout = ForumBodyInlineParagraphLayout.create(
        content: input.content,
        width: 60,
        dimensions: [_dimension],
      );
      addTearDown(layout.dispose);
      expect(layout.lines, hasLength(2));
      final first = layout.lines.first;
      final last = layout.lines.last;
      expect((first.coverageStartUtf16, first.coverageEndUtf16), (0, 5));
      expect(
        (first.engineCoverageStartUtf16, first.engineCoverageEndUtf16),
        (0, 2),
      );
      expect((last.coverageStartUtf16, last.coverageEndUtf16), (5, 6));
      expect(
        (last.engineCoverageStartUtf16, last.engineCoverageEndUtf16),
        (2, 3),
      );
      expect(layout.fragment(0, 1).atomIndices, [0]);
      expect(layout.fragment(1, 2).atomIndices, isEmpty);
      expect(layout.fragment(0, 1).coverageEndUtf16, 5);
      expect(layout.fragment(0, 1).engineCoverageEndUtf16, 2);
      expect(layout.atomBoxes.single.top + 26, closeTo(first.baseline, 1e-6));
      expect(() => layout.lines.clear(), throwsUnsupportedError);
      expect(() => layout.atomBoxes.clear(), throwsUnsupportedError);
    },
  );

  test(
    'ruby hits route to child-local geometry and ordinary suffix hits use display source',
    () {
      final input = mixedInlineInput();
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final group = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: input.base,
        annotation: input.annotation,
      );
      addTearDown(group.close);
      final layout = ForumBodyInlineParagraphLayout.create(
        content: input.content,
        width: 40,
        dimensions: [group.placeholderDimensions],
      );
      addTearDown(layout.dispose);
      expect(layout.lines, hasLength(3));
      final child = layout.atomBoxes.single.toRect();
      final localBox = group
          .selectionBoxes(
            part: ForumBodyRubyPart.annotation,
            startUtf16: 0,
            endUtf16: 1,
          )
          .single;
      final hit =
          layout.hitAt(
                child.topLeft +
                    Offset(
                      localBox.left + .1,
                      (localBox.top + localBox.bottom) / 2,
                    ),
              )
              as ForumBodyInlineAtomHit;
      expect(hit.index, 0);
      final exact = group.sourceAt(hit.offset);
      expect(exact.part, ForumBodyRubyPart.annotation);
      expect(exact.position.sourceRune, 4);
      final fragment = layout.fragment(1, 2);
      final same =
          fragment.hitAt(child.topLeft - Offset(0, fragment.top) + Offset(1, 1))
              as ForumBodyInlineAtomHit;
      expect(same.index, 0);
      expect(same.offset, const Offset(1, 1));
      final suffix = layout.selection(5, 6).textBoxes.single;
      final suffixHit =
          layout.hitAt(
                Offset(suffix.left + .1, (suffix.top + suffix.bottom) / 2),
              )
              as ForumBodyInlineTextHit;
      expect(suffixHit.position.sourceRune, 7);
      expect(suffixHit.position.displayUtf16, 5);
    },
  );

  test(
    'selection keeps actual child subranges separate from parent glyph boxes',
    () {
      final input = mixedInlineInput();
      final layout = ForumBodyInlineParagraphLayout.create(
        content: input.content,
        width: 100,
        dimensions: [_dimension],
      );
      addTearDown(layout.dispose);
      final full = layout.selection(0, 6);
      expect(full.textBoxes, hasLength(2));
      expect(
        full.atoms.map(
          (selection) =>
              (selection.index, selection.startUtf16, selection.endUtf16),
        ),
        [(0, 1, 5)],
      );
      final annotation = layout.selection(3, 4);
      expect(annotation.textBoxes, isEmpty);
      expect(
        annotation.atoms.map(
          (selection) => (selection.startUtf16, selection.endUtf16),
        ),
        [(3, 4)],
      );
      expect(layout.selection(3, 3).atoms, isEmpty);
      expect(() => full.textBoxes.clear(), throwsUnsupportedError);
      expect(() => full.atoms.clear(), throwsUnsupportedError);
      expect(() => layout.selection(0, 7), throwsRangeError);
    },
  );

  test(
    'ZWJ and combining fallback rows cannot become legal page boundaries',
    () {
      final input = mixedInlineInput(prefix: '👩‍💻e\u0301', suffix: 'Z');
      final layout = ForumBodyInlineParagraphLayout.create(
        content: input.content,
        width: 40,
        dimensions: [_dimension],
      );
      addTearDown(layout.dispose);
      expect(
        layout.lines.last.coverageEndUtf16,
        input.content.projection.display.text.length,
      );
      var engine = 0;
      var display = 0;
      for (var i = 0; i < layout.lines.length; i++) {
        final line = layout.lines[i];
        expect(line.engineCoverageStartUtf16, engine);
        expect(line.coverageStartUtf16, display);
        engine = line.engineCoverageEndUtf16;
        display = line.coverageEndUtf16;
        final legal = input.content.projection
            .displayAtEngineUtf16(engine)
            .isExact;
        expect(line.canBreakAfter, legal);
        if (!legal) {
          expect(
            () => layout.fragment(0, i + 1),
            throwsA(isA<ForumBodyParagraphLayoutException>()),
          );
        }
      }
      final full = layout.fragment(0, layout.lines.length);
      expect(
        full.coverageEndUtf16,
        input.content.projection.display.text.length,
      );
      expect(
        full.engineCoverageEndUtf16,
        input.content.projection.engineText.length,
      );
    },
  );

  test(
    'hard breaks after atoms keep separator coverage and terminal empty line',
    () {
      final input = mixedInlineInput(suffix: 'Y<br>');
      final layout = ForumBodyInlineParagraphLayout.create(
        content: input.content,
        width: 100,
        dimensions: [_dimension],
      );
      addTearDown(layout.dispose);
      expect(input.content.projection.engineText, 'X\uFFFCY\n');
      expect(layout.lines, hasLength(2));
      expect(layout.lines.first.endUtf16, 6);
      expect(layout.lines.first.coverageEndUtf16, 7);
      expect(layout.lines.first.engineEndUtf16, 3);
      expect(layout.lines.first.engineCoverageEndUtf16, 4);
      expect(layout.lines.last.coverageStartUtf16, 7);
      expect(layout.fragment(1, 2).atomIndices, isEmpty);
    },
  );

  test(
    'intrinsic native parent retains natural width and ignores containing block indent',
    () {
      final input = mixedInlineInput(
        reader: ForumBodyReaderStyle(
          textStyle: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            height: 1,
          ),
          fontRevision: 'ahem',
          linkColor: const Color(0xff0000ff),
          firstLineIndent: const ForumBodyLength(2, ForumBodyLengthUnit.em),
        ),
      );
      expect(
        () => ForumBodyInlineParagraphLayout.create(
          content: input.content,
          width: 100,
          dimensions: [_dimension],
        ),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
      final layout = ForumBodyInlineParagraphLayout.create(
        content: input.content,
        width: 10,
        dimensions: [_dimension],
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
      addTearDown(layout.dispose);
      expect(layout.width, 80);
      expect(layout.lines, hasLength(1));
      expect(layout.atomBoxes.single.left, 20);
    },
  );

  test(
    'parent scale and direction validation excludes independent atom child runs',
    () {
      final input = mixedInlineInput(annotation: '<span dir="rtl">אב</span>');
      expect(
        input.content.runs.any(
          (run) => run.style.textDirection == TextDirection.rtl,
        ),
        isTrue,
      );
      expect(
        input.content.parentRuns.map((run) => run.style.textStyle.fontSize),
        [20, 20],
      );
      final scales = ForumBodyInlineParagraphLayout.validateInputs(
        content: input.content,
        width: 100,
        dimensions: [_dimension],
        textScaler: const _ParentScaler(),
      );
      expect(scales, {20.0: 30.0});
      final layout = ForumBodyInlineParagraphLayout.create(
        content: input.content,
        width: 100,
        dimensions: [_dimension],
        textScaler: const _ParentScaler(),
      );
      addTearDown(layout.dispose);
      expect(layout.atomBoxes.single.toRect().size, _dimension.size);
      final mixedDirection = mixedInlineInput(
        prefix: '<span dir="rtl">אב</span>',
      );
      expect(
        () => ForumBodyInlineParagraphLayout.create(
          content: mixedDirection.content,
          width: 100,
          dimensions: [_dimension],
        ),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
    },
  );

  test(
    'bad width, fitting, geometry and oversize atoms fail before native access',
    () {
      final input = mixedInlineInput();
      for (final width in [
        0.0,
        -1.0,
        double.nan,
        double.infinity,
        16385.0,
        30.0,
      ]) {
        expect(
          () => ForumBodyInlineParagraphLayout.create(
            content: input.content,
            width: width,
            dimensions: [_dimension],
          ),
          throwsA(isA<ForumBodyParagraphLayoutException>()),
        );
      }
      expect(
        () => ForumBodyInlineParagraphLayout.create(
          content: input.content,
          width: 100,
          dimensions: [],
        ),
        throwsArgumentError,
      );
      expect(
        () => ForumBodyInlineParagraphLayout.create(
          content: input.content,
          width: 100,
          dimensions: [_dimension, _dimension],
        ),
        throwsArgumentError,
      );
      expect(
        () => ForumBodyInlineParagraphLayout.create(
          content: input.content,
          width: 100,
          dimensions: [_dimension],
          layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
        ),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
      final hardBreak = mixedInlineInput(suffix: 'Y<br>Z');
      expect(
        () => ForumBodyInlineParagraphLayout.create(
          content: hardBreak.content,
          width: 100,
          dimensions: [_dimension],
          layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        ),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
    },
  );

  test(
    'RTL native parent resolves actual child rectangle before projecting carets',
    () {
      final input = mixedInlineInput(
        prefix: 'א',
        suffix: 'ב',
        direction: 'rtl',
      );
      final layout = ForumBodyInlineParagraphLayout.create(
        content: input.content,
        width: 100,
        dimensions: [_dimension],
      );
      addTearDown(layout.dispose);
      final box = layout.atomBoxes.single.toRect();
      final hit = layout.hitAt(box.center) as ForumBodyInlineAtomHit;
      expect(hit.index, 0);
      expect(hit.offset, box.center - box.topLeft);
      expect(layout.selection(1, 5).textBoxes, isEmpty);
      final after = layout.selection(5, 6).textBoxes.single;
      expect(after.direction, TextDirection.rtl);
    },
  );

  test(
    'parent and line-window painting borrow one engine and clip other rows',
    () async {
      final input = mixedInlineInput();
      final layout = ForumBodyInlineParagraphLayout.create(
        content: input.content,
        width: 40,
        dimensions: [_dimension],
      );
      addTearDown(layout.dispose);
      final fragment = layout.fragment(2, 3);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      fragment.paintParent(canvas, const Offset(3, 3));
      final picture = recorder.endRecording();
      try {
        final image = await picture.toImage(50, 80);
        try {
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          var inside = 0;
          var outside = 0;
          for (var y = 0; y < 80; y++) {
            for (var x = 0; x < 50; x++) {
              if (pixels[(y * 50 + x) * 4 + 3] == 0) continue;
              if (x >= 3 && x < 43 && y >= 3 && y < 3 + fragment.height) {
                inside++;
              } else {
                outside++;
              }
            }
          }
          expect(inside, greaterThan(0));
          expect(outside, 0);
        } finally {
          image.dispose();
        }
      } finally {
        picture.dispose();
      }
      final selection = layout.selection(5, 6).textBoxes.single;
      final hit = fragment.hitAt(
        Offset(
          selection.left + .1,
          (selection.top + selection.bottom) / 2 - fragment.top,
        ),
      );
      expect((hit as ForumBodyInlineTextHit).position.sourceRune, 7);
    },
  );

  test(
    'retirement invalidates native operations and every borrowed fragment',
    () {
      final input = mixedInlineInput();
      final dimensions = [_dimension];
      final layout = ForumBodyInlineParagraphLayout.create(
        content: input.content,
        width: 60,
        dimensions: dimensions,
      );
      final fragment = layout.fragment(0, 1);
      dimensions.clear();
      expect(layout.dimensions, hasLength(1));
      expect(() => layout.dimensions.clear(), throwsUnsupportedError);
      expect(
        () => layout.hitAt(const Offset(double.nan, 0)),
        throwsArgumentError,
      );
      layout.dispose();
      layout.dispose();
      expect(layout.isDisposed, isTrue);
      expect(() => layout.selection(0, 1), throwsStateError);
      expect(() => layout.hitAt(Offset.zero), throwsStateError);
      expect(() => layout.fragment(0, 1), throwsStateError);
      expect(() => fragment.atomIndices.toList(), throwsStateError);
      expect(() => fragment.hitAt(Offset.zero), throwsStateError);
      final recorder = ui.PictureRecorder();
      expect(
        () => fragment.paintParent(Canvas(recorder), Offset.zero),
        throwsStateError,
      );
      recorder.endRecording().dispose();
    },
  );
}

final class _ParentScaler extends TextScaler {
  const _ParentScaler();
  @override
  double scale(double size) => size == 20 ? 30 : double.nan;
  @override
  double get textScaleFactor => 1.5;
}
