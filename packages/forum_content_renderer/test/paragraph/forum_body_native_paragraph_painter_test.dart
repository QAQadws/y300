import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/src/paragraph/forum_body_native_paragraph_painter.dart';
import 'package:forum_content_renderer/src/paragraph/forum_body_paragraph_geometry.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

const _style = TextStyle(
  fontFamily: 'Ahem',
  fontSize: 20,
  height: .4,
  color: Color(0xff123456),
);

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
List<Object> _line(ForumBodyParagraphLine row) => [
  row.top,
  row.bottom,
  row.baseline,
  row.left,
  row.width,
  row.startUtf16,
  row.endUtf16,
  row.coverageStartUtf16,
  row.coverageEndUtf16,
  row.engineStartUtf16,
  row.engineEndUtf16,
  row.canBreakBefore,
  row.canBreakAfter,
  row.unpaintedTrailingSpaceStartUtf16,
];

HtmlDisplayTextProjection _display(String text) =>
    HtmlDisplayTextProjection.build([
      HtmlDisplayTextRun(
        text: text,
        sourceRuneStart: 7,
        whiteSpace: HtmlDisplayWhiteSpace.preWrap,
      ),
    ]);

Future<List<int>> _pixels(
  void Function(Canvas) draw,
  int width,
  int height,
  int dpr,
) async {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec)..scale(dpr.toDouble()));
  final pic = rec.endRecording();
  try {
    final image = await pic.toImage(width * dpr, height * dpr);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List().toList(growable: false);
    } finally {
      image.dispose();
    }
  } finally {
    pic.dispose();
  }
}

final class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double size) => size < 25 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

final class _CallbackScaler extends TextScaler {
  const _CallbackScaler(this.callback);
  final double Function(double) callback;
  @override
  double scale(double size) => callback(size);
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final direction in TextDirection.values) {
    for (final align in TextAlign.values) {
      for (final mode in ['wrap', 'intrinsic', 'fit']) {
        for (final scaler in [TextScaler.noScaling, const _Nonlinear()]) {
          test(
            'native paragraph matches Flutter $direction/$align/$mode/$scaler',
            () async {
              const text = TextSpan(
                style: _style,
                children: [
                  TextSpan(text: 'ffi é 中 العربية '),
                  TextSpan(
                    text: 'AB ',
                    style: TextStyle(fontSize: 31, color: Color(0xffff0000)),
                  ),
                  TextSpan(text: '👩‍👩‍👧‍👦 中 end'),
                ],
              );
              final native = ForumBodyNativeParagraphPainter(
                text: text,
                textAlign: align,
                textDirection: direction,
                textScaler: scaler,
              );
              final flutter = TextPainter(
                text: text,
                textAlign: align,
                textDirection: direction,
                textScaler: scaler,
              );
              addTearDown(native.dispose);
              addTearDown(flutter.dispose);
              final min = mode == 'intrinsic' ? 0.0 : 140.0;
              final max = mode == 'wrap' ? 140.0 : double.infinity;
              native.layout(minWidth: min, maxWidth: max);
              flutter.layout(minWidth: min, maxWidth: max);
              expect(native.width, flutter.width);
              expect(native.height, flutter.height);
              for (final baseline in TextBaseline.values) {
                expect(
                  native.computeDistanceToActualBaseline(baseline),
                  flutter.computeDistanceToActualBaseline(baseline),
                );
              }
              expect(
                native.computeLineMetrics().map(_metrics),
                flutter.computeLineMetrics().map(_metrics),
              );
              final display = _display(
                text.toPlainText(includeSemanticsLabels: false),
              );
              final expected = forumBodyParagraphLines(
                painter: flutter,
                display: display,
              );
              final actual = forumBodyParagraphLinesWithPainter(
                painter: native,
                display: display,
              );
              expect(actual.map(_line), expected.map(_line));
              final boxes = native.getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: display.text.length),
              );
              expect(
                boxes,
                flutter.getBoxesForSelection(
                  TextSelection(
                    baseOffset: 0,
                    extentOffset: display.text.length,
                  ),
                ),
              );
              for (final box in boxes) {
                final point = box.toRect().center;
                expect(
                  native.getPositionForOffset(point),
                  flutter.getPositionForOffset(point),
                );
              }
              for (final dpr in [1, 3]) {
                final w = native.width.ceil() + 40,
                    h = native.height.ceil() + 60;
                expect(
                  await _pixels(
                    (canvas) => native.paint(canvas, const Offset(20, 30)),
                    w,
                    h,
                    dpr,
                  ),
                  await _pixels(
                    (canvas) => flutter.paint(canvas, const Offset(20, 30)),
                    w,
                    h,
                    dpr,
                  ),
                );
              }
              expect(
                () => native.computeLineMetrics().clear(),
                throwsUnsupportedError,
              );
            },
          );
        }
      }
    }
  }

  for (final text in [
    '',
    '\n',
    '\n\n',
    'A\n\nB\n',
    'A\u2028B\u2029',
    'A\u00adB\u00ad',
    '\u2060A B\u200d',
    'A  \nB   ',
    '👩‍👩‍👧‍👦é👩‍👩‍👧‍👦',
    'אבג abc אבג',
  ]) {
    for (final width in [1.0, 35.0, 140.0]) {
      test(
        'native logical ranges retain breaks/clusters ${text.codeUnits}/$width',
        () {
          final display = _display(text);
          final span = TextSpan(text: display.text, style: _style);
          final native = ForumBodyNativeParagraphPainter(
            text: span,
            textAlign: TextAlign.start,
            textDirection: TextDirection.rtl,
            textScaler: TextScaler.noScaling,
          )..layout(minWidth: width, maxWidth: width);
          final flutter = TextPainter(
            text: span,
            textDirection: TextDirection.rtl,
          )..layout(minWidth: width, maxWidth: width);
          addTearDown(native.dispose);
          addTearDown(flutter.dispose);
          final actual = forumBodyParagraphLinesWithPainter(
            painter: native,
            display: display,
          );
          expect(
            native.computeLineMetrics().map(_metrics),
            flutter.computeLineMetrics().map(_metrics),
          );
          final legacyRejectsNarrow =
              width == 1 &&
              {
                'A\n\nB\n',
                '\u2060A B\u200d',
                'A  \nB   ',
                'אבג abc אבג',
              }.contains(display.text);
          if (legacyRejectsNarrow) {
            expect(
              () => forumBodyParagraphLines(painter: flutter, display: display),
              throwsA(isA<ForumBodyParagraphLayoutException>()),
            );
          } else {
            expect(
              actual.map(_line),
              forumBodyParagraphLines(
                painter: flutter,
                display: display,
              ).map(_line),
            );
          }
          // The old wrapper rejects some one-pixel columns. Check every native
          // logical code unit independently of the indexed binary lookup.
          expect(
            actual.isEmpty ? 0 : actual.last.coverageEndUtf16,
            display.text.length,
          );
          for (var i = 0; i < actual.length; i++) {
            for (
              var unit = actual[i].coverageStartUtf16;
              unit < actual[i].coverageEndUtf16;
              unit++
            ) {
              expect(native.getLineNumberAt(unit), i);
            }
          }
        },
      );
    }
  }

  test(
    'engine coordinates ignore semantics labels and reset with new text',
    () {
      const text = TextSpan(
        style: _style,
        children: [
          TextSpan(
            text: 'ABC DEF GHI',
            semanticsLabel: 'different semantic label',
          ),
        ],
      );
      final native = ForumBodyNativeParagraphPainter(
        text: text,
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout(minWidth: 60, maxWidth: 60);
      addTearDown(native.dispose);
      final rows = forumBodyParagraphLinesWithPainter(
        painter: native,
        display: _display('ABC DEF GHI'),
      );
      expect(rows.last.coverageEndUtf16, 11);
      native.text = const TextSpan(text: 'Z', style: _style);
      expect(() => native.height, throwsStateError);
      native.layout(minWidth: 60, maxWidth: 60);
      expect(
        forumBodyParagraphLinesWithPainter(
          painter: native,
          display: _display('Z'),
        ),
        hasLength(1),
      );
      expect(
        native.lineBoundaryForRow(0, 0).range,
        const TextRange(start: 0, end: 1),
      );
      expect(
        () => native.lineBoundaryForRow(0, 1),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
      native.dispose();
      expect(() => native.width, throwsStateError);
      expect(() => native.computeLineMetrics(), throwsStateError);
    },
  );

  test(
    'repeated widths relayout the same native input with correct origins',
    () {
      const span = TextSpan(text: 'ABC DEF GHI JKL', style: _style);
      final native = ForumBodyNativeParagraphPainter(
        text: span,
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        textScaler: TextScaler.noScaling,
      );
      final flutter = TextPainter(
        text: span,
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
      );
      addTearDown(native.dispose);
      addTearDown(flutter.dispose);
      for (final width in [140.0, 70.0, double.infinity, 30.0]) {
        native.layout(maxWidth: width);
        flutter.layout(maxWidth: width);
        expect(native.width, flutter.width);
        expect(native.height, flutter.height);
        expect(
          native.computeLineMetrics().map(_metrics),
          flutter.computeLineMetrics().map(_metrics),
        );
        expect(
          forumBodyParagraphLinesWithPainter(
            painter: native,
            display: _display(span.text!),
          ).map(_line),
          forumBodyParagraphLines(
            painter: flutter,
            display: _display(span.text!),
          ).map(_line),
        );
      }
    },
  );

  test(
    'scaler retirement during native building cannot publish a paragraph',
    () {
      late ForumBodyNativeParagraphPainter native;
      native = ForumBodyNativeParagraphPainter(
        text: const TextSpan(text: 'ABC', style: _style),
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr,
        textScaler: _CallbackScaler((size) {
          native.dispose();
          return size;
        }),
      );
      expect(() => native.layout(maxWidth: 100), throwsStateError);
      expect(() => native.width, throwsStateError);
      native.dispose();
    },
  );
}
