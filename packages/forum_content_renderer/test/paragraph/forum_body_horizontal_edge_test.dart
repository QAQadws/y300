import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import '../inline/test_support/mixed_inline_fixture.dart';

const _text = 'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz';

ForumBodyReaderStyle _reader(double spacing, TextDirection direction) =>
    ForumBodyReaderStyle(
      textStyle: TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        height: 2,
        letterSpacing: spacing,
        color: const Color(0xff000000),
      ),
      fontRevision: 'edge-ahem',
      linkColor: const Color(0xff000000),
      textDirection: direction,
    );

ForumBodyParagraphContent _input(
  double spacing,
  TextDirection direction, {
  String html = '<p>$_text</p>',
  ForumBodyParagraphLayoutMode mode = ForumBodyParagraphLayoutMode.wrap,
}) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'horizontal-edge',
    conversionIdentity: 'none',
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: document,
    styles: const ForumBodyStyleResolver().resolve(
      document,
      _reader(spacing, direction),
    ),
    path: '0',
    layoutMode: mode,
  );
}

Future<Uint8List> _raster(
  double width,
  double height,
  double dpr,
  void Function(Canvas) paint, {
  bool clipped = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(dpr)
    ..translate(20, 20);
  if (clipped) {
    canvas.clipRect(Rect.fromLTWH(0, 0, width, height), doAntiAlias: false);
  }
  paint(canvas);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      ((width + 40) * dpr).ceil(),
      ((height + 40) * dpr).ceil(),
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

void _samePixels(Uint8List actual, Uint8List expected) {
  expect(actual.length, expected.length);
  var different = 0;
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) {
      different++;
    }
  }
  expect(different, 0);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final direction in TextDirection.values) {
    for (final scale in [1.0, 2.0]) {
      test(
        'positive tracking keeps terminal glyph boxes inside fractional widths ($direction, $scale)',
        () {
          final text = List.filled(52, '漢').join();
          final content = _input(
            .25,
            direction,
            html: '<p style="font-size:18.5px">$text</p>',
          );
          for (final pair in [
            for (final count in [3, 6, 19])
              for (final gap in [0.0, .125]) (count, gap),
          ]) {
            final width = pair.$1 * (18.5 * scale + .25) + pair.$2;
            final layout = ForumBodyParagraphLayout.create(
              content: content,
              width: width,
              textScaler: TextScaler.linear(scale),
            );
            try {
              for (var i = 0; i < text.length; i++) {
                for (final box in layout.selectionBoxes(i, i + 1)) {
                  expect(
                    box.left,
                    greaterThanOrEqualTo(-.001),
                    reason: 'width=$width, offset=$i',
                  );
                  expect(
                    box.right,
                    lessThanOrEqualTo(width + .001),
                    reason: 'width=$width, offset=$i',
                  );
                }
              }
            } finally {
              layout.dispose();
            }
          }
        },
      );
    }
  }
  for (final direction in TextDirection.values) {
    for (final spacing in [-2.0, -1.25, 0.0, .5]) {
      for (final scale in [1.0, 2.0]) {
        test(
          'wrapped native geometry shares one inset ($direction, $spacing, $scale)',
          () {
            final content = _input(spacing, direction);
            final layout = ForumBodyParagraphLayout.create(
              content: content,
              width: 120,
              textScaler: TextScaler.linear(scale),
            );
            addTearDown(layout.dispose);
            final inset = spacing.abs();
            expect(layout.horizontalInset, inset);
            expect(layout.firstLineIndent.layoutPasses, 1);
            expect(layout.lines.length, greaterThan(1));
            final control = TextPainter(
              text: TextSpan(text: _text, style: content.style.textStyle),
              textDirection: direction,
              textScaler: TextScaler.linear(scale),
            )..layout(minWidth: 120 - 2 * inset, maxWidth: 120 - 2 * inset);
            addTearDown(control.dispose);
            for (var i = 0; i < _text.length; i++) {
              final actual = layout.selectionBoxes(i, i + 1).single;
              final expected = control
                  .getBoxesForSelection(
                    TextSelection(baseOffset: i, extentOffset: i + 1),
                  )
                  .single;
              expect(
                actual.toRect(),
                expected.toRect().shift(Offset(inset, 0)),
              );
              expect(actual.left, greaterThanOrEqualTo(-.001));
              expect(actual.right, lessThanOrEqualTo(120.001));
              final point = Offset(
                actual.left + actual.toRect().width / 4,
                actual.toRect().center.dy,
              );
              expect(layout.sourceAt(point).sourceRune, i);
            }
            expect(layout.projection.text, _text);
          },
        );
      }
    }
    for (final dpr in [1.0, 3.0]) {
      for (final spacing in [-1.25, .25]) {
        test(
          'tracking loses no pixels at either clip edge ($direction, $dpr, $spacing)',
          () async {
            final content = _input(spacing, direction);
            final inset = spacing.abs();
            final layout = ForumBodyParagraphLayout.create(
              content: content,
              width: 120,
            );
            addTearDown(layout.dispose);
            final control = TextPainter(
              text: TextSpan(text: _text, style: content.style.textStyle),
              textDirection: direction,
            )..layout(minWidth: 120 - 2 * inset, maxWidth: 120 - 2 * inset);
            addTearDown(control.dispose);
            final expected = await _raster(
              120,
              layout.height,
              dpr,
              (canvas) => control.paint(canvas, Offset(inset, 0)),
            );
            final actual = await _raster(
              120,
              layout.height,
              dpr,
              (canvas) => layout.paint(canvas, Offset.zero),
              clipped: true,
            );
            _samePixels(actual, expected);
          },
        );
      }
    }
  }
  for (final mode in [
    ForumBodyParagraphLayoutMode.intrinsicSingleLine,
    ForumBodyParagraphLayoutMode.fitSingleLine,
  ]) {
    test('only a constrained single-line layout reserves its edge ($mode)', () {
      final content = _input(
        -2,
        TextDirection.ltr,
        html: '<p>abcdef</p>',
        mode: mode,
      );
      final layout = ForumBodyParagraphLayout.create(
        content: content,
        width: 80,
      );
      addTearDown(layout.dispose);
      final scale = mode == ForumBodyParagraphLayoutMode.fitSingleLine
          ? 80 / 112
          : 1.0;
      expect(
        layout.width,
        mode == ForumBodyParagraphLayoutMode.fitSingleLine ? 80 : 108,
      );
      expect(
        layout.horizontalInset,
        closeTo(
          mode == ForumBodyParagraphLayoutMode.fitSingleLine ? 2 * scale : 0,
          .001,
        ),
      );
      expect(
        layout.selectionBoxes(0, 1).single.left,
        closeTo(
          mode == ForumBodyParagraphLayoutMode.fitSingleLine ? scale : -1,
          .001,
        ),
      );
      expect(
        layout.selectionBoxes(5, 6).single.right,
        lessThanOrEqualTo(layout.width),
      );
      expect(
        layout
            .sourceAt(
              layout.selectionBoxes(5, 6).single.toRect().centerLeft +
                  Offset(2 * scale, 0),
            )
            .sourceRune,
        5,
      );
    });
  }
  test('effective inline runs determine the reserve and cached admission', () {
    final content = _input(
      .5,
      TextDirection.ltr,
      html: '<p>a<span style="letter-spacing:-6px">b</span>c</p>',
    );
    final cache = ForumBodyParagraphCache(
      maxEntries: 2,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final lease = cache.acquire(content: content, width: 120);
    expect(lease.layout.horizontalInset, 6);
    final layout = lease.layout;
    lease.release();
    final warm = cache.tryAcquireCached(content: content, width: 120)!;
    expect(warm.layout, same(layout));
    expect(cache.layoutBuildCount, 1);
    warm.release();
    expect(
      () => cache.acquire(content: content, width: 6),
      throwsA(isA<ForumBodyParagraphLayoutException>()),
    );
    expect(cache.activeLeases, 0);
    expect(cache.layoutBuildCount, 1);
  });
  test('an empty font strut keeps zero width despite negative tracking', () {
    final ordinary = _input(-2, TextDirection.ltr);
    final strut = ForumBodyParagraphContent.anonymousInline(
      identity: ordinary.identity,
      fontRevision: ordinary.fontRevision,
      styleRevision: ordinary.styleRevision,
      style: ordinary.style,
    );
    final layout = ForumBodyParagraphLayout.create(content: strut, width: 1);
    addTearDown(layout.dispose);
    expect(layout.horizontalInset, 0);
    expect(layout.width, 0);
    expect(layout.height, greaterThan(0));
    expect(layout.selectionBoxes(0, 0), isEmpty);
  });
  test(
    'an all-atomic parent reserves the viewport without padding intrinsic children',
    () {
      final input = mixedInlineInput(
        prefix: '',
        suffix: '',
        reader: _reader(-2, TextDirection.ltr),
      );
      expect(input.content.parentRuns, isEmpty);
      const dimension = PlaceholderDimensions(
        size: Size(116, 40),
        alignment: ui.PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        baselineOffset: 32,
      );
      final layout = ForumBodyInlineParagraphLayout.create(
        content: input.content,
        width: 120,
        dimensions: [dimension],
      );
      addTearDown(layout.dispose);
      expect(layout.horizontalInset, 2);
      expect(layout.atomBoxes.single.toRect().left, 2);
      expect(layout.atomBoxes.single.toRect().right, 118);
      final intrinsic = ForumBodyInlineParagraphLayout.create(
        content: input.content,
        width: 120,
        dimensions: [dimension],
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
      addTearDown(intrinsic.dispose);
      expect(intrinsic.horizontalInset, 0);
      expect(intrinsic.width, 116);
    },
  );
  for (final direction in TextDirection.values) {
    test(
      'mixed parent inset shifts atoms, parent boxes and hit routing ($direction)',
      () {
        final input = mixedInlineInput(
          prefix: 'ABCDEFGHIJ',
          suffix: 'KLMNOPQRST',
          direction: direction.name,
          reader: _reader(-1.25, direction),
        );
        const dimension = PlaceholderDimensions(
          size: Size(40, 40),
          alignment: ui.PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          baselineOffset: 32,
        );
        final layout = ForumBodyInlineParagraphLayout.create(
          content: input.content,
          width: 120,
          dimensions: [dimension],
        );
        addTearDown(layout.dispose);
        expect(layout.horizontalInset, 1.25);
        final atom = layout.atomBoxes.single.toRect();
        expect(atom.left, greaterThanOrEqualTo(1.25));
        expect(atom.right, lessThanOrEqualTo(118.75));
        final hit =
            layout.hitAt(atom.topLeft + const Offset(1, 1))
                as ForumBodyInlineAtomHit;
        expect(hit.offset, const Offset(1, 1));
        final boxes = layout.selection(0, 10).textBoxes;
        expect(boxes, isNotEmpty);
        expect(
          boxes.every((box) => box.left >= -.001 && box.right <= 120.001),
          isTrue,
        );
        final first = layout.selection(0, 1).textBoxes.single;
        final textHit =
            layout.hitAt(first.toRect().centerLeft + const Offset(2, 0))
                as ForumBodyInlineTextHit;
        expect(
          textHit.position.sourceRune,
          input.contexts.first.projection.sourceAtUtf16(0).sourceRune,
        );
      },
    );
  }
}
