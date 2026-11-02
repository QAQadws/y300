import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyParagraphContent content(
  String html, {
  ForumBodyParagraphLayoutMode layoutMode = ForumBodyParagraphLayoutMode.wrap,
}) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'layout',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontSize: 20,
        height: 1.5,
        fontFamily: 'Ahem',
        color: Color(0xff000000),
      ),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: document,
    styles: styles,
    path: '0',
    layoutMode: layoutMode,
  );
}

Future<List<int>> raster(
  ForumBodyParagraphLayout layout, {
  bool fragments = false,
  ForumBodyParagraphFragment? window,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (window != null) {
    window.paint(canvas, Offset.zero);
  } else if (fragments) {
    var start = 0;
    for (var i = 0; i < layout.lines.length; i++) {
      if (!layout.lines[i].canBreakAfter) continue;
      final fragment = layout.fragment(start, i + 1);
      expect(identical(fragment.layout, layout), isTrue);
      fragment.paint(canvas, Offset(0, fragment.top));
      start = i + 1;
    }
    expect(start, layout.lines.length);
  } else {
    layout.paint(canvas, Offset.zero);
  }
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      layout.width.ceil(),
      (window?.height ?? layout.height).ceil(),
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
    'repeated input admission reads current values in original size order',
    () {
      final input = content(
        '<p>A<span style="font-size:10px">B</span>'
        '<b>C</b><span style="font-size:30px">D</span></p>',
      );
      final seen = <double>[];
      var ratio = 1.0;
      final scaler = _AdmissionScaler((size) {
        seen.add(size);
        return size * ratio;
      });
      Map<double, double> resolve() => ForumBodyParagraphLayout.validateInputs(
        content: input,
        width: 200,
        textScaler: scaler,
      );
      expect(resolve(), {20: 20, 10: 10, 30: 30});
      expect(seen, [20, 10, 30]);
      seen.clear();
      ratio = 1.5;
      expect(resolve(), {20: 30, 10: 15, 30: 45});
      expect(seen, [20, 10, 30]);
      ratio = double.nan;
      expect(
        resolve,
        throwsA(_admissionFailure(ForumBodyParagraphLayoutFailure.scale)),
      );
    },
  );

  test(
    'a later invalid style keeps preceding scaler calls and failure order',
    () {
      final input = content(
        '<p>A<span style="font-size:10px">B</span>'
        '<span dir="rtl">C</span></p>',
      );
      final seen = <double>[];
      var valid = true;
      final scaler = _AdmissionScaler((size) {
        seen.add(size);
        return valid ? size : double.nan;
      });
      void resolve() => ForumBodyParagraphLayout.validateInputs(
        content: input,
        width: 200,
        textScaler: scaler,
      );
      for (var repeat = 0; repeat < 2; repeat++) {
        seen.clear();
        expect(
          resolve,
          throwsA(_admissionFailure(ForumBodyParagraphLayoutFailure.direction)),
        );
        expect(seen, [20, 10]);
      }
      valid = false;
      seen.clear();
      expect(
        resolve,
        throwsA(_admissionFailure(ForumBodyParagraphLayoutFailure.scale)),
      );
      expect(seen, [20]);
    },
  );

  test('width and immutable preconditions precede all scaler calls', () {
    final scaler = _AdmissionScaler((size) => fail('Preflight must run first'));
    for (final (html, mode, failure) in [
      (
        '<p style="text-indent:-2em">a</p>',
        ForumBodyParagraphLayoutMode.wrap,
        ForumBodyParagraphLayoutFailure.indent,
      ),
      (
        '<p>a<br>b</p>',
        ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        ForumBodyParagraphLayoutFailure.singleLine,
      ),
      (
        '<p style="white-space:pre">a</p>',
        ForumBodyParagraphLayoutMode.wrap,
        ForumBodyParagraphLayoutFailure.noWrap,
      ),
    ]) {
      final input = content(html, layoutMode: mode);
      for (var repeat = 0; repeat < 2; repeat++) {
        expect(
          () => ForumBodyParagraphLayout.validateInputs(
            content: input,
            width: 200,
            textScaler: scaler,
          ),
          throwsA(_admissionFailure(failure)),
        );
        expect(
          () => ForumBodyParagraphLayout.validateInputs(
            content: input,
            width: 0,
            textScaler: scaler,
          ),
          throwsA(_admissionFailure(ForumBodyParagraphLayoutFailure.width)),
        );
      }
    }
  });

  test(
    'display slices validate their own hard breaks, not their old input',
    () {
      final input = content(
        '<p>ab<br>cd</p>',
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
      Map<double, double> resolve(ForumBodyParagraphContent value) =>
          ForumBodyParagraphLayout.validateInputs(
            content: value,
            width: 200,
            textScaler: TextScaler.noScaling,
          );
      expect(
        () => resolve(input),
        throwsA(_admissionFailure(ForumBodyParagraphLayoutFailure.singleLine)),
      );
      final slice = input.displayWindow(startUtf16: 0, endUtf16: 2);
      expect(resolve(slice), {20: 20});
      expect(resolve(slice), {20: 20});
      expect(
        () => resolve(input),
        throwsA(_admissionFailure(ForumBodyParagraphLayoutFailure.singleLine)),
      );
    },
  );

  test(
    'empty native font baseline does not fabricate text rows or pixels',
    () async {
      final input = content('<p></p>');
      final layout = ForumBodyParagraphLayout.create(
        content: input,
        width: 100,
      );
      addTearDown(layout.dispose);
      final native = TextPainter(
        text: input.textSpan,
        textDirection: input.style.textDirection,
      )..layout(minWidth: 100, maxWidth: 100);
      addTearDown(native.dispose);
      expect(layout.lines, isEmpty);
      expect(layout.height, native.height);
      expect(
        layout.alphabeticBaseline,
        native.computeDistanceToActualBaseline(TextBaseline.alphabetic),
      );
      expect(layout.alphabeticBaseline, greaterThan(0));
      expect(layout.selectionBoxes(0, 0), isEmpty);
      expect(layout.sourceAt(const Offset(1, 1)).isExact, isFalse);
      final pixels = await raster(layout);
      expect(pixels.every((value) => value == 0), isTrue);
    },
  );

  test(
    'a terminal empty native row cannot paint the previous tight-line glyph',
    () async {
      final layout = ForumBodyParagraphLayout.create(
        content: content(
          '<p style="white-space:pre-wrap;line-height:.25">A\n</p>',
        ),
        width: 100,
      );
      addTearDown(layout.dispose);
      final last = layout.lines.length - 1;
      final empty = layout.fragment(last, last + 1);
      expect(empty.height, greaterThan(0));
      expect(empty.coverageStartUtf16, empty.coverageEndUtf16);
      final visible = await raster(layout, window: layout.fragment(0, last));
      expect(visible.any((value) => value != 0), isTrue);
      final pixels = await raster(layout, window: empty);
      expect(pixels.every((value) => value == 0), isTrue);
      layout.dispose();
      final recorder = ui.PictureRecorder();
      expect(
        () => empty.paint(Canvas(recorder), Offset.zero),
        throwsStateError,
      );
      recorder.endRecording().dispose();
    },
  );

  test(
    'intrinsic inline glyphs leave inherited indentation to their containing block',
    () {
      final inline = ForumBodyParagraphLayout.create(
        content: content(
          '<p style="text-indent:2em">abc</p>',
          layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        ),
        width: 20,
      );
      addTearDown(inline.dispose);
      expect(inline.width, 60);
      expect(inline.lines.single.left, 0);
      expect(inline.selectionBoxes(0, 1).single.left, 0);
      for (final mode in [ForumBodyParagraphLayoutMode.fitSingleLine]) {
        expect(
          () => ForumBodyParagraphLayout.create(
            content: content(
              '<p style="text-indent:2em">abc</p>',
              layoutMode: mode,
            ),
            width: 100,
          ),
          throwsA(
            isA<ForumBodyParagraphLayoutException>().having(
              (error) => error.failure,
              'failure',
              ForumBodyParagraphLayoutFailure.indent,
            ),
          ),
        );
      }
    },
  );

  test(
    'intrinsic single line preserves natural glyph metrics beyond the request width',
    () {
      final input = content(
        '<p>abcdefghij</p>',
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
      final layout = ForumBodyParagraphLayout.create(content: input, width: 40);
      addTearDown(layout.dispose);
      final reference = TextPainter(
        text: input.textSpan,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: double.infinity);
      addTearDown(reference.dispose);
      expect(layout.width, 200);
      expect(layout.width, reference.width);
      expect(layout.height, reference.height);
      expect(layout.lines.single.width, 200);
      expect(layout.selectionBoxes(9, 10).single.right, 200);
      expect(
        layout.sourceAt(Offset(190, layout.lines.single.baseline)).sourceRune,
        inInclusiveRange(9, 10),
      );
    },
  );

  test(
    'intrinsic mixed sizes use the nonlinear scaler once and paint the same line',
    () async {
      final input = content(
        '<p>a<span style="font-size:40px">b</span>c</p>',
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
      const scaler = _NonlinearScaler();
      final layout = ForumBodyParagraphLayout.create(
        content: input,
        width: 20,
        textScaler: scaler,
      );
      addTearDown(layout.dispose);
      final reference = TextPainter(
        text: input.textSpan,
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: double.infinity);
      addTearDown(reference.dispose);
      expect(layout.width, reference.width);
      expect(layout.height, reference.height);
      expect(
        layout.selectionBoxes(0, 3).map((box) => box.toRect()),
        reference
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 3),
            )
            .map((box) => box.toRect()),
      );
      expect(await raster(layout, fragments: true), await raster(layout));
    },
  );

  test(
    'intrinsic preformatted spaces survive but hard lines and oversized widths fail',
    () {
      final pre = ForumBodyParagraphLayout.create(
        content: content(
          '<p style="white-space:pre">a  b</p>',
          layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        ),
        width: 20,
      );
      addTearDown(pre.dispose);
      expect(pre.width, 80);
      for (final (html, failure) in [
        ('<p>a<br>b</p>', ForumBodyParagraphLayoutFailure.singleLine),
        (
          '<p style="white-space:pre">a\nb</p>',
          ForumBodyParagraphLayoutFailure.singleLine,
        ),
        ('<p>${'a' * 820}</p>', ForumBodyParagraphLayoutFailure.width),
      ]) {
        expect(
          () => ForumBodyParagraphLayout.create(
            content: content(
              html,
              layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
            ),
            width: 20,
          ),
          throwsA(
            isA<ForumBodyParagraphLayoutException>().having(
              (error) => error.failure,
              'failure',
              failure,
            ),
          ),
        );
      }
    },
  );

  test(
    'fitted single line keeps every glyph and scales actual line geometry',
    () {
      const html = '<p>abcdefghijklmnopqrst</p>';
      final natural = ForumBodyParagraphLayout.create(
        content: content(html),
        width: 400,
      );
      final fitted = ForumBodyParagraphLayout.create(
        content: content(
          html,
          layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
        ),
        width: 100,
      );
      addTearDown(natural.dispose);
      addTearDown(fitted.dispose);
      expect(natural.lines.single.width, 400);
      expect(natural.paintScale, 1);
      expect(fitted.paintScale, .25);
      expect(fitted.lines, hasLength(1));
      expect(fitted.width, 100);
      expect(fitted.height, closeTo(natural.height / 4, 1e-6));
      expect(fitted.lines.single.width, closeTo(100, 1e-6));
      expect(
        fitted.lines.single.baseline,
        closeTo(natural.lines.single.baseline / 4, 1e-6),
      );
      expect(fitted.projection.text, 'abcdefghijklmnopqrst');
      expect(fitted.lines.single.coverageEndUtf16, 20);
      expect(fitted.selectionBoxes(19, 20).single.right, closeTo(100, 1e-6));
    },
  );

  test(
    'fitted selection and hits use the same transformed source coordinates',
    () {
      const html = '<p>abcdefghijklmnopqrst</p>';
      final natural = ForumBodyParagraphLayout.create(
        content: content(html),
        width: 400,
      );
      final fitted = ForumBodyParagraphLayout.create(
        content: content(
          html,
          layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
        ),
        width: 100,
      );
      addTearDown(natural.dispose);
      addTearDown(fitted.dispose);
      final naturalBox = natural.selectionBoxes(3, 6).single;
      final fittedBox = fitted.selectionBoxes(3, 6).single;
      expect(
        fittedBox.toRect(),
        Rect.fromLTRB(
          naturalBox.left / 4,
          naturalBox.top / 4,
          naturalBox.right / 4,
          naturalBox.bottom / 4,
        ),
      );
      for (var index = 0; index < 20; index++) {
        final box = fitted.selectionBoxes(index, index + 1).single.toRect();
        final probe = Offset(box.left + box.width * .1, box.center.dy);
        expect(
          fitted.sourceAt(probe).sourceRune,
          natural.sourceAt(probe * 4).sourceRune,
        );
        expect(
          fitted.fragment(0, 1).sourceAt(probe).sourceRune,
          fitted.sourceAt(probe).sourceRune,
        );
      }
    },
  );

  for (final direction in ['ltr', 'rtl']) {
    test(
      'short fitted text is never enlarged and preserves $direction alignment',
      () {
        final html = '<p dir="$direction">ab</p>';
        final ordinary = ForumBodyParagraphLayout.create(
          content: content(html),
          width: 200,
        );
        final fitted = ForumBodyParagraphLayout.create(
          content: content(
            html,
            layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
          ),
          width: 200,
        );
        addTearDown(ordinary.dispose);
        addTearDown(fitted.dispose);
        expect(fitted.height, ordinary.height);
        expect(fitted.lines.single.width, ordinary.lines.single.width);
        expect(
          fitted.selectionBoxes(0, 2).map((box) => box.toRect()),
          ordinary.selectionBoxes(0, 2).map((box) => box.toRect()),
        );
      },
    );
  }

  test('single-line fitting follows actual mixed nonlinear font scaling', () {
    const html = '<p>aaa<span style="font-size:40px">bbb</span>ccc</p>';
    final natural = ForumBodyParagraphLayout.create(
      content: content(html),
      width: 1000,
      textScaler: const _NonlinearScaler(),
    );
    final fitted = ForumBodyParagraphLayout.create(
      content: content(
        html,
        layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
      ),
      width: 100,
      textScaler: const _NonlinearScaler(),
    );
    addTearDown(natural.dispose);
    addTearDown(fitted.dispose);
    final ratio = 100 / natural.lines.single.width;
    expect(ratio, lessThan(1));
    expect(fitted.height, closeTo(natural.height * ratio, 1e-6));
    expect(fitted.lines.single.width, closeTo(100, 1e-6));
    final fullBox = natural.selectionBoxes(3, 6).single;
    final fittedBox = fitted.selectionBoxes(3, 6).single;
    expect(fittedBox.left, closeTo(fullBox.left * ratio, 1e-6));
    expect(fittedBox.right, closeTo(fullBox.right * ratio, 1e-6));
  });

  test('fitted fragment pixels match the complete single-line paint', () async {
    final layout = ForumBodyParagraphLayout.create(
      content: content(
        '<p>abcdefghijklmnopqrst</p>',
        layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
      ),
      width: 100,
    );
    addTearDown(layout.dispose);
    final full = await raster(layout);
    expect(full.where((channel) => channel != 0), isNotEmpty);
    expect(await raster(layout, fragments: true), full);
  });

  test(
    'fitting rejects hard lines instead of clipping or dropping their text',
    () {
      for (final html in [
        '<p>a<br>b</p>',
        '<p style="white-space:pre">a\r\nb</p>',
        '<p>a\u2028b</p>',
        '<p>a\u2029b</p>',
        '<p>a\u0085b</p>',
      ]) {
        expect(
          () => ForumBodyParagraphLayout.create(
            content: content(
              html,
              layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
            ),
            width: 100,
          ),
          throwsA(
            isA<ForumBodyParagraphLayoutException>().having(
              (error) => error.failure,
              'failure',
              ForumBodyParagraphLayoutFailure.singleLine,
            ),
          ),
        );
      }
      final pre = ForumBodyParagraphLayout.create(
        content: content(
          '<p style="white-space:pre">a  b</p>',
          layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
        ),
        width: 20,
      );
      addTearDown(pre.dispose);
      expect(pre.projection.text, 'a  b');
      expect(pre.lines, hasLength(1));
    },
  );

  test(
    'display coverage includes hard breaks, blank lines and trailing newline',
    () {
      final layout = ForumBodyParagraphLayout.create(
        content: content('<p>a<br><br>b<br></p>'),
        width: 200,
      );
      addTearDown(layout.dispose);
      expect(layout.projection.text, 'a\n\nb\n');
      expect(layout.lines.map((line) => (line.startUtf16, line.endUtf16)), [
        (0, 1),
        (2, 2),
        (3, 4),
        (5, 5),
      ]);
      expect(
        layout.lines.map(
          (line) => (line.coverageStartUtf16, line.coverageEndUtf16),
        ),
        [(0, 2), (2, 3), (3, 5), (5, 5)],
      );
      final firstPage = layout.fragment(0, 2);
      final secondPage = layout.fragment(2, 4);
      expect(firstPage.coverageStartUtf16, 0);
      expect(firstPage.coverageEndUtf16, secondPage.coverageStartUtf16);
      expect(secondPage.coverageEndUtf16, layout.projection.text.length);
    },
  );

  test(
    'line coverage partitions Unicode display text without proving source gaps',
    () {
      for (final html in [
        '<p>中文日文かな 👨‍👩‍👧‍👦 é abc def</p>',
        '<p dir="rtl">אבג 123 abc דהו</p>',
        '<p dir="rtl">אבג<br><br></p>',
        '<p style="white-space:pre-wrap"> \n 甲 é\n</p>',
        '<p>甲\u2028乙\u2029</p>',
        '<p>\u2028\u2028</p>',
        '<p><br><br></p>',
        '<p></p>',
        '<p>a<span hidden>secret</span>b<br></p>',
      ]) {
        final input = content(html);
        for (final width in [60.0, 120.0, 500.0]) {
          late final ForumBodyParagraphLayout layout;
          expect(
            () => layout = ForumBodyParagraphLayout.create(
              content: input,
              width: width,
            ),
            returnsNormally,
            reason: 'Input $html at width $width',
          );
          try {
            final text = input.projection.text;
            final covered = StringBuffer();
            var previous = 0;
            for (var index = 0; index < layout.lines.length; index++) {
              final line = layout.lines[index];
              expect(line.coverageStartUtf16, previous);
              expect(
                line.coverageEndUtf16,
                greaterThanOrEqualTo(line.endUtf16),
              );
              expect(
                line.canBreakAfter,
                input.projection
                        .sourceAtUtf16(line.coverageEndUtf16)
                        .displayUtf16 ==
                    line.coverageEndUtf16,
              );
              if (line.canBreakBefore && line.canBreakAfter) {
                final fragment = layout.fragment(index, index + 1);
                expect(fragment.coverageStartUtf16, line.coverageStartUtf16);
                expect(fragment.coverageEndUtf16, line.coverageEndUtf16);
              } else {
                expect(
                  () => layout.fragment(index, index + 1),
                  throwsA(isA<ForumBodyParagraphLayoutException>()),
                );
              }
              covered.write(
                text.substring(line.coverageStartUtf16, line.coverageEndUtf16),
              );
              previous = line.coverageEndUtf16;
            }
            expect(previous, text.length);
            expect(covered.toString(), text);
          } finally {
            layout.dispose();
          }
        }
      }
      final gap = content('<p>a<span hidden>secret</span>b</p>');
      expect(gap.projection.sourceAtUtf16(1).isExact, isFalse);
    },
  );

  test(
    'narrow fallback cluster lines stay together in painted fragments',
    () async {
      final layout = ForumBodyParagraphLayout.create(
        content: content('<p>中文日文かな 👨‍👩‍👧‍👦 é abc def</p>'),
        width: 60,
      );
      addTearDown(layout.dispose);
      expect(layout.lines.any((line) => !line.canBreakAfter), isTrue);
      expect(await raster(layout, fragments: true), await raster(layout));
    },
  );

  test(
    'one actual layout serves metrics, repeated paint, hit-test and boxes',
    () async {
      final input = content('<p>abc def ghi jkl mno pqr stu vwx yz</p>');
      final layout = ForumBodyParagraphLayout.create(
        content: input,
        width: 120,
      );
      addTearDown(layout.dispose);
      expect(layout.lines.length, greaterThan(2));
      expect(layout.lines.first.top, closeTo(0, .001));
      expect(layout.lines.last.bottom, closeTo(layout.height, .001));
      final before = layout.lines;
      final pixels = await raster(layout);
      expect(pixels, await raster(layout, fragments: true));
      expect(pixels, await raster(layout));
      expect(identical(before, layout.lines), isTrue);
      final box = layout.selectionBoxes(0, 1).single;
      final position = layout.sourceAt(
        Offset(box.left + 1, (box.top + box.bottom) / 2),
      );
      expect(position.sourceRune, input.projection.sourceAtUtf16(0).sourceRune);
      final fragment = layout.fragment(1, 2);
      final sample = Offset(1, fragment.height / 2);
      expect(
        fragment.sourceAt(sample).sourceRune,
        layout.sourceAt(sample + Offset(0, fragment.top)).sourceRune,
      );
    },
  );

  test('mixed sizes use the actual nonlinear scaler exactly once', () {
    final input = content('<p>a<span style="font-size:40px">b</span>c</p>');
    const scaler = _NonlinearScaler();
    final layout = ForumBodyParagraphLayout.create(
      content: input,
      width: 200,
      textScaler: scaler,
    );
    addTearDown(layout.dispose);
    final reference = TextPainter(
      text: input.textSpan,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout(minWidth: 200, maxWidth: 200);
    addTearDown(reference.dispose);
    expect(layout.height, reference.height);
    expect(
      layout.selectionBoxes(0, 3).map((box) => box.toRect()),
      reference
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 3),
          )
          .map((box) => box.toRect()),
    );
  });

  test(
    'CJK, emoji, RTL and long URLs retain ranges and paint coverage',
    () async {
      for (final html in [
        '<p>中文日文かな 👨‍👩‍👧‍👦 é 123 abc</p>',
        '<p dir="rtl">אבג 123 abc דהו</p>',
        '<p>https://example.invalid/very/long/continuous/path?foo=bar</p>',
        '<p>a<br><br>b<br>c</p>',
      ]) {
        final layout = ForumBodyParagraphLayout.create(
          content: content(html),
          width: 120,
        );
        try {
          expect(
            layout.lines.every(
              (line) =>
                  line.startUtf16 >= 0 &&
                  line.endUtf16 <= layout.projection.text.length,
            ),
            isTrue,
          );
          expect(await raster(layout, fragments: true), await raster(layout));
        } finally {
          layout.dispose();
        }
      }
    },
  );

  test('partial UTF-16 selections expand to whole display graphemes', () {
    final layout = ForumBodyParagraphLayout.create(
      content: content('<p>👨‍👩‍👧‍👦x</p>'),
      width: 400,
    );
    addTearDown(layout.dispose);
    expect(
      layout.selectionBoxes(1, 2).map((box) => box.toRect()),
      layout.selectionBoxes(0, 11).map((box) => box.toRect()),
    );
  });

  test('views stop before touching a disposed engine resource', () {
    final layout = ForumBodyParagraphLayout.create(
      content: content('<p>abc</p>'),
      width: 200,
    );
    final fragment = layout.fragment(0, 1);
    layout.dispose();
    layout.dispose();
    expect(layout.isDisposed, isTrue);
    expect(() => fragment.sourceAt(Offset.zero), throwsStateError);
    expect(() => layout.selectionBoxes(0, 1), throwsStateError);
  });

  test('unsupported constraints are explicit rather than silently ignored', () {
    for (final (html, reason) in [
      (
        '<p style="text-indent:-2em">text</p>',
        ForumBodyParagraphLayoutFailure.indent,
      ),
      (
        '<p>abc<span dir="rtl">def</span></p>',
        ForumBodyParagraphLayoutFailure.direction,
      ),
      (
        '<p style="white-space:pre">text</p>',
        ForumBodyParagraphLayoutFailure.noWrap,
      ),
    ]) {
      expect(
        () =>
            ForumBodyParagraphLayout.create(content: content(html), width: 200),
        throwsA(
          isA<ForumBodyParagraphLayoutException>().having(
            (e) => e.failure,
            'failure',
            reason,
          ),
        ),
      );
    }
    expect(
      () => ForumBodyParagraphLayout.create(
        content: content('<p>x</p>'),
        width: double.infinity,
      ),
      throwsA(isA<ForumBodyParagraphLayoutException>()),
    );
  });
}

final class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double size) => size <= 20 ? size * 2 : size * 1.25;
  @override
  double get textScaleFactor => 2;
}

Matcher _admissionFailure(ForumBodyParagraphLayoutFailure failure) =>
    isA<ForumBodyParagraphLayoutException>().having(
      (error) => error.failure,
      'failure',
      failure,
    );

final class _AdmissionScaler extends TextScaler {
  const _AdmissionScaler(this.resolve);
  final double Function(double) resolve;
  @override
  double scale(double size) => resolve(size);
  @override
  double get textScaleFactor => 1;
}
