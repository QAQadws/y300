import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyParagraphContent content(String html) {
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
  );
}

Future<List<int>> raster(
  ForumBodyParagraphLayout layout, {
  bool fragments = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (fragments) {
    for (var i = 0; i < layout.lines.length; i++) {
      final fragment = layout.fragment(i, i + 1);
      expect(identical(fragment.layout, layout), isTrue);
      fragment.paint(canvas, Offset(0, fragment.top));
    }
  } else {
    layout.paint(canvas, Offset.zero);
  }
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      layout.width.ceil(),
      layout.height.ceil(),
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
        '<p style="text-indent:2em">text</p>',
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
