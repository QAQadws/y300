import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_row_alignment.dart';
import 'package:forum_content_renderer/src/paragraph/forum_body_native_paragraph_painter.dart';

import 'test_support/mixed_inline_fixture.dart';
import 'test_support/ruby_soft_space_row_fixture.dart';

const _dimensions = [
  PlaceholderDimensions(
    size: Size(45.25, 37.5),
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    baselineOffset: 27.125,
  ),
];

final class _Curve extends TextScaler {
  const _Curve();
  @override
  double scale(double size) => size * (size < 25 ? 1.4 : 1.1);
  @override
  double get textScaleFactor => throw StateError('Sample actual font sizes');
}

List<Object> _metrics(ui.LineMetrics row) => [
  row.hardBreak,
  row.ascent,
  row.descent,
  row.unscaledAscent,
  row.height,
  row.width,
  row.left,
  row.baseline,
  row.lineNumber,
];

Future<List<int>> _pixels(void Function(Canvas) draw, int dpr) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder)..scale(dpr.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(260 * dpr, 300 * dpr);
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
  for (final direction in TextDirection.values) {
    for (final align in TextAlign.values) {
      for (final scaler in [TextScaler.noScaling, const _Curve()]) {
        test(
          'owned mixed parent preserves Flutter geometry and DPR1/3 pixels $direction $align $scaler',
          () async {
            final f = mixedInlineInput(
              prefix:
                  '<span style="font-size:31px;text-decoration:underline">A é </span>',
              suffix: ' B 👩‍👩‍👧‍👦 中',
              direction: direction.name,
              paragraphStyle:
                  'line-height:.4;text-align:${align.name};text-shadow:1px 2px 2px red',
            );
            final content = f.content;
            for (final intrinsic in [false, true]) {
              final native = ForumBodyNativeParagraphPainter(
                text: content.textSpan,
                textAlign: content.style.textAlign,
                textDirection: direction,
                textScaler: scaler,
                placeholderDimensions: _dimensions,
              );
              final reference = TextPainter(
                text: content.textSpan,
                textAlign: content.style.textAlign,
                textDirection: direction,
                textScaler: scaler,
              )..setPlaceholderDimensions(_dimensions);
              try {
                final min = intrinsic ? 0.0 : 123.75,
                    max = intrinsic ? double.infinity : 123.75;
                native.layout(minWidth: min, maxWidth: max);
                reference.layout(minWidth: min, maxWidth: max);
                expect(native.width, reference.width);
                expect(native.height, reference.height);
                expect(
                  native.computeLineMetrics().map(_metrics),
                  reference.computeLineMetrics().map(_metrics),
                );
                expect(
                  native.placeholderBoxes,
                  reference.inlinePlaceholderBoxes,
                );
                // Child geometry is physical even under nonlinear scaling.
                expect(
                  native.placeholderBoxes.single.toRect().size,
                  _dimensions.single.size,
                );
                final selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: content.projection.engineText.length,
                );
                final boxes = native.getBoxesForSelection(selection);
                expect(boxes, reference.getBoxesForSelection(selection));
                for (final box in boxes) {
                  expect(
                    native.getPositionForOffset(box.toRect().center),
                    reference.getPositionForOffset(box.toRect().center),
                  );
                }
                for (final dpr in [1, 3]) {
                  final actual = await _pixels(
                    (c) => native.paint(c, const Offset(20.125, 30.375)),
                    dpr,
                  );
                  final expected = await _pixels(
                    (c) => reference.paint(c, const Offset(20.125, 30.375)),
                    dpr,
                  );
                  expect(expected.any((value) => value != 0), isTrue);
                  expect(
                    listEquals(actual, expected),
                    isTrue,
                    reason: 'intrinsic=$intrinsic DPR=$dpr',
                  );
                }
              } finally {
                native.dispose();
                reference.dispose();
              }
            }
          },
        );
      }
    }
    test(
      'mixed glyph and maximum frames use the actual native parent $direction',
      () {
        final content = mixedInlineInput(
          prefix: '\u0600A e<span style="font-size:31px">́</span> ',
          suffix: ' B 👩‍👩‍👧‍👦<br>C<br>',
          direction: direction.name,
          paragraphStyle: 'line-height:.4;text-indent:7.25px;text-align:center',
        ).content;
        final cache = ForumBodyParagraphCache(
          maxEntries: 8,
          maxEstimatedBytes: 1 << 22,
        );
        addTearDown(cache.close);
        final lease = cache.acquireInline(
          content: content,
          width: 123.75,
          dimensions: _dimensions,
        );
        addTearDown(lease.release);
        final layout = lease.layout, projection = layout.projection;
        final span = content.textSpanWithDimensions(
          _dimensions,
          firstLineIndent: layout.firstLineIndent.appliedAdvance,
        );
        final reference = TextPainter(
          text: span,
          textAlign: content.style.textAlign,
          textDirection: direction,
        )..setPlaceholderDimensions(_dimensions);
        addTearDown(reference.dispose);
        reference.layout(
          minWidth: 123.75 - 2 * content.horizontalInset,
          maxWidth: 123.75 - 2 * content.horizontalInset,
        );
        final builder = ui.ParagraphBuilder(
          content.style.textStyle.getParagraphStyle(
            textAlign: content.style.textAlign,
            textDirection: direction,
          ),
        );
        span.build(builder, dimensions: _dimensions);
        final raw = builder.build()
          ..layout(
            ui.ParagraphConstraints(
              width: 123.75 - 2 * content.horizontalInset,
            ),
          );
        addTearDown(raw.dispose);
        final origin = Offset(
          content.horizontalInset,
          layout.lines.first.baseline -
              reference.computeLineMetrics().first.baseline,
        );
        final before = (
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          cache.hitCount,
          cache.activeLeases,
        );
        var queried = 0;
        for (var offset = 0; offset < projection.engineText.length; offset++) {
          final actual = layout.glyphAtEngineUtf16(offset);
          if (offset < projection.enginePrefix.length ||
              projection.atoms.any(
                (a) => offset >= a.engineUtf16 && offset < a.engineEndUtf16,
              )) {
            expect(actual, isNull);
            continue;
          }
          final expected = raw.getGlyphInfoAt(offset);
          expect(actual == null, expected == null);
          if (actual != null) {
            expect(actual.lineIndex, raw.getLineNumberAt(offset));
            expect(
              actual.fontBounds,
              expected!.graphemeClusterLayoutBounds.shift(origin),
            );
            expect(
              actual.engineClusterRange,
              expected.graphemeClusterCodeUnitRange,
            );
            expect(actual.direction, expected.writingDirection);
            queried++;
          }
        }
        expect(queried, greaterThan(10));
        expect(layout.queryMaximumLineFrames(), [
          for (final b in reference.getBoxesForSelection(
            TextSelection(
              baseOffset: 0,
              extentOffset: projection.engineText.length,
            ),
            boxHeightStyle: ui.BoxHeightStyle.max,
          ))
            (top: b.top + origin.dy, bottom: b.bottom + origin.dy),
        ]);
        expect(
          () => layout.queryMaximumLineFrames().clear(),
          throwsUnsupportedError,
        );
        expect((
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          cache.hitCount,
          cache.activeLeases,
        ), before);
        expect(() => layout.glyphAtEngineUtf16(-1), throwsRangeError);
        expect(
          () => layout.glyphAtEngineUtf16(projection.engineText.length),
          throwsRangeError,
        );
        cache.close();
        expect(() => layout.glyphAtEngineUtf16(0), throwsStateError);
        expect(layout.queryMaximumLineFrames, throwsStateError);
      },
    );

    test(
      'real soft-space glue is excluded from parent glyph queries $direction',
      () {
        final f = RubySoftSpaceRowFixture(direction: direction);
        addTearDown(f.close);
        for (final width in [300.0, 45.0]) {
          // A large real gap's font is reserved by its neighbouring columns.
          // Raw unequal boxes do not yet qualify a visible parent frame.
          final alignment = ForumBodyRubyRowAlignment.atoms(
            atoms: f.atoms,
            levelIds: [0, 0, 0],
            atomOffsets: f.offsets,
          );
          while (!alignment.isComplete && !alignment.needsRows) {
            alignment.advance(maxParts: 1);
          }
          final probe = f.parent(width, alignment.provisionalDimensions);
          try {
            alignment.attachRows(probe.layout.lines);
            while (!alignment.isComplete) {
              alignment.advance(maxParts: 1);
            }
          } finally {
            probe.releaseProvisional();
          }
          final parent = f.parent(width, alignment.dimensions);
          try {
            final layout = parent.layout;
            for (final atom in layout.projection.atoms) {
              for (
                var offset = atom.engineUtf16;
                offset < atom.engineEndUtf16;
                offset++
              ) {
                expect(layout.glyphAtEngineUtf16(offset), isNull);
              }
            }
            expect(layout.isAtomTrimmed(1), width == 45);
            expect(layout.queryMaximumLineFrames(), isNotEmpty);
          } finally {
            parent.release();
          }
        }
      },
    );
  }
  test(
    'native placeholder dimensions are frozen and a text replacement releases the old paragraph',
    () {
      final content = mixedInlineInput().content, dimensions = [..._dimensions];
      final painter = ForumBodyNativeParagraphPainter(
        text: content.textSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(2),
        placeholderDimensions: dimensions,
      );
      addTearDown(painter.dispose);
      dimensions.clear();
      painter.layout(minWidth: 100, maxWidth: 100);
      expect(
        painter.placeholderBoxes.single.toRect().size,
        _dimensions.single.size,
      );
      expect(() => painter.placeholderBoxes.clear(), throwsUnsupportedError);
      painter.text = const TextSpan(
        text: 'Z',
        style: TextStyle(fontFamily: 'Ahem', fontSize: 20),
      );
      expect(() => painter.placeholderBoxes, throwsStateError);
      painter.layout(minWidth: 100, maxWidth: 100);
      expect(painter.placeholderBoxes, isEmpty);
      painter.dispose();
      expect(() => painter.placeholderBoxes, throwsStateError);
    },
  );
}
