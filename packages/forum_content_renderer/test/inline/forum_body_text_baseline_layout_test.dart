import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

({ForumBodyParagraphContent child, ForumBodyInlineSpanContent parent}) _input({
  String text = 'xy',
  String direction = 'ltr',
  double height = 1,
}) {
  final document = const ForumBodyParser().parse(
    html:
        '<p dir="$direction"><span>P</span>'
        '<span style="font-size:12px;line-height:$height">$text</span>'
        '<span>S</span></p>',
    sourceId: 'baseline-text',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        height: 1,
        color: Color(0xff000000),
      ),
      fontRevision: 'baseline-ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  final contexts = [
    for (final path in ['0/0', '0/1', '0/2'])
      const ForumBodyParagraphContentBuilder().build(
        document: document,
        styles: styles,
        path: path,
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      ),
  ];
  return (
    child: contexts[1],
    parent: ForumBodyInlineSpanContent.compose(
      identity: document.identity,
      path: '0',
      fontRevision: styles.fontRevision,
      styleRevision: styles.resolverRevision,
      style: styles.byPath['0']!,
      contexts: contexts,
      atomicRanges: [(startUtf16: 1, endUtf16: 1 + text.length)],
    ),
  );
}

Future<List<int>> _pixels(void Function(Canvas) paint, Size size) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(size.width.ceil(), size.height.ceil());
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

final class _Curve extends TextScaler {
  const _Curve();
  @override
  double scale(double fontSize) => fontSize * (fontSize < 15 ? 1.8 : 1.2);
  @override
  double get textScaleFactor => 1.2;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ForumBodyParagraphCache cache;
  setUp(
    () => cache = ForumBodyParagraphCache(
      maxEntries: 8,
      maxEstimatedBytes: 1 << 22,
    ),
  );
  tearDown(() => cache.close());

  for (final shift in [-30.0, -4.0, 0.0, 8.0, 30.0]) {
    test(
      'baseline geometry encloses glyphs and reference baseline ($shift)',
      () {
        final metrics = ForumBodyTextBaselineMetrics(
          childBounds: const Rect.fromLTRB(-2, -3, 18, 15),
          childBaseline: 9,
          baselineShift: shift,
        );
        expect(metrics.size.width, 20);
        expect(metrics.baseline, inInclusiveRange(0, metrics.size.height));
        final bounds = metrics.childBounds.shift(metrics.childOffset);
        expect(bounds.left, 0);
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.bottom, lessThanOrEqualTo(metrics.size.height));
        expect(
          metrics.childBaseline + metrics.childOffset.dy,
          metrics.baseline - shift,
        );
        expect(metrics.placeholderDimensions.baselineOffset, metrics.baseline);
      },
    );
  }

  for (final direction in ['ltr', 'rtl']) {
    for (final scale in [TextScaler.noScaling, const _Curve()]) {
      for (final shift in [-40.0, 8.0, 40.0]) {
        test(
          'same native glyphs, source and parent baseline: $direction/$scale/$shift',
          () async {
            final input = _input(
              text: direction == 'rtl' ? 'אב' : 'xy',
              direction: direction,
              height: .2,
            );
            final original = cache.acquire(
              content: input.child,
              width: 200,
              textScaler: scale,
            );
            final owned = cache.acquire(
              content: input.child,
              width: 200,
              textScaler: scale,
            );
            cache.prepareTextPaint(owned);
            final builds = cache.layoutBuildCount;
            final pictures = cache.pictureBuildCount;
            final layout = ForumBodyTextBaselineLayout.adopt(
              cache: cache,
              lease: owned,
              baselineShift: shift,
            );
            try {
              expect(identical(layout.content, input.child), isTrue);
              expect(
                identical(layout.projection, input.child.projection),
                isTrue,
              );
              expect(
                layout.metrics.childBounds,
                forumBodyTextLayoutBounds(original.layout),
              );
              final localBox = original.layout.selectionBoxes(0, 1).single;
              final box = layout.selectionBoxes(0, 1).single;
              expect(
                box.toRect(),
                localBox.toRect().shift(layout.metrics.childOffset),
              );
              expect(box.direction, localBox.direction);
              final hit = layout.sourceAt(
                Offset(
                  box.left + (box.right - box.left) * .25,
                  (box.top + box.bottom) * .5,
                ),
              );
              expect(hit.isExact, isTrue);
              expect(
                hit.sourceRune,
                input.child.projection
                    .sourceAtUtf16(direction == 'rtl' ? 1 : 0)
                    .sourceRune,
              );
              final canvasSize = Size(layout.width + 8, layout.height + 8);
              final actual = await _pixels(
                (c) => layout.paint(c, const Offset(4, 4)),
                canvasSize,
              );
              final expected = await _pixels(
                (c) => original.layout.paint(
                  c,
                  const Offset(4, 4) + layout.metrics.childOffset,
                ),
                canvasSize,
              );
              expect(actual, expected);
              expect(cache.layoutBuildCount, builds);
              expect(cache.pictureBuildCount, pictures);

              final parent = cache.acquireInline(
                content: input.parent,
                width: 200,
                textScaler: scale,
                dimensions: [layout.metrics.placeholderDimensions],
              );
              try {
                final slot = parent.layout.atomBoxes.single;
                final parentBaseline = parent.layout.lines.single.baseline;
                expect(
                  slot.top + layout.alphabeticBaseline,
                  closeTo(parentBaseline, 1e-3),
                );
                expect(
                  slot.top +
                      layout.metrics.childOffset.dy +
                      original.layout.alphabeticBaseline,
                  closeTo(parentBaseline - shift, 1e-3),
                );
                expect(
                  parent.layout.projection.display.text,
                  'P${input.child.projection.text}S',
                );
              } finally {
                parent.release();
              }
              if (shift.abs() > layout.metrics.childBounds.height) {
                final reservedY = shift > 0 ? layout.height - .1 : .1;
                expect(
                  layout.sourceAt(Offset(layout.width / 2, reservedY)).isExact,
                  isFalse,
                );
              }
            } finally {
              layout.close();
              original.release();
            }
            expect(cache.activeLeases, 0);
            expect(layout.isDisposed, isTrue);
            expect(layout.isPaintPrepared, isFalse);
            expect(() => layout.sourceAt(Offset.zero), throwsStateError);
            expect(() => layout.selectionBoxes(0, 1), throwsStateError);
          },
        );
      }
    }
  }

  test('adoption failure releases only the transferred handle', () {
    final input = _input();
    final first = cache.acquire(content: input.child, width: 100);
    final alias = cache.acquire(content: input.child, width: 100);
    expect(
      () => ForumBodyTextBaselineLayout.adopt(
        cache: cache,
        lease: first,
        baselineShift: double.nan,
      ),
      throwsArgumentError,
    );
    expect(first.isActive, isFalse);
    expect(alias.isActive, isTrue);
    expect(cache.activeLeases, 1);
    final other = ForumBodyParagraphCache(
      maxEntries: 2,
      maxEstimatedBytes: 1 << 20,
    );
    try {
      expect(
        () => ForumBodyTextBaselineLayout.adopt(
          cache: other,
          lease: alias,
          baselineShift: 4,
        ),
        throwsStateError,
      );
      expect(alias.isActive, isFalse);
      expect(cache.activeLeases, 0);
    } finally {
      other.close();
    }
  });

  test(
    'closed owner retires paint, source and copy while metrics remain pure',
    () {
      final input = _input(text: 'e\u0301😀');
      final owned = cache.acquire(content: input.child, width: 100);
      final layout = ForumBodyTextBaselineLayout.adopt(
        cache: cache,
        lease: owned,
        baselineShift: 4,
      );
      final metrics = layout.metrics;
      cache.close();
      expect(layout.isDisposed, isTrue);
      expect(layout.isPaintPrepared, isFalse);
      final recorder = ui.PictureRecorder();
      expect(
        () => layout.paint(Canvas(recorder), Offset.zero),
        throwsStateError,
      );
      recorder.endRecording().dispose();
      expect(() => layout.content, throwsStateError);
      expect(() => layout.selectionBoxes(0, 1), throwsStateError);
      expect(() => layout.sourceAt(Offset.zero), throwsStateError);
      expect(metrics.size.isEmpty, isFalse);
      layout.close();
      layout.close();
      expect(cache.activeLeases, 0);
    },
  );
}
