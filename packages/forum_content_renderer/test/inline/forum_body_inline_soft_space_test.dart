import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_native_space_span.dart';

ForumBodyInlineSpanContent _input({
  TextDirection direction = TextDirection.ltr,
  TextAlign align = TextAlign.start,
  bool soft = true,
  String suffix = '',
}) {
  final doc = const ForumBodyParser().parse(
    html:
        '<p dir="${direction.name}" style="text-align:${align.name}">A B$suffix</p>',
    sourceId: 'actual-soft-space',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    doc,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        height: 1,
        color: Color(0xff000000),
      ),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  final text = const ForumBodyParagraphContentBuilder().build(
    document: doc,
    styles: styles,
    path: '0',
  );
  return ForumBodyInlineSpanContent.compose(
    identity: doc.identity,
    path: '0',
    fontRevision: styles.fontRevision,
    styleRevision: styles.resolverRevision,
    style: text.style,
    contexts: [text],
    atomicRanges: [
      for (var i = 0; i < 3; i++) (startUtf16: i, endUtf16: i + 1),
    ],
    softSpaceAtoms: soft ? {1} : {},
  );
}

List<PlaceholderDimensions> _dimensions(double gap, {double gapHeight = 30}) =>
    [
      for (var i = 0; i < 3; i++)
        PlaceholderDimensions(
          size: Size(i == 1 ? gap : 20, i == 1 ? gapHeight : 30),
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          baselineOffset: i == 1 && gapHeight != 30 ? gapHeight / 2 : 26,
        ),
    ];

Future<List<int>> _pixels(void Function(Canvas) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder)..scale(3));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(180, 210);
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
  setUpAll(() async {
    await (FontLoader(
      ForumBodyNativeSpaceSpan.fontFamily,
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final fractional in [false, true]) {
      for (final wrapped in [false, true]) {
        test(
          'independent native SPACE has the same rows and DPR3 pixels $direction fractional=$fractional wrapped=$wrapped',
          () async {
            final gap = fractional ? 10.375 : 10.0;
            final width = 40 + gap - (wrapped ? .125 : 0);
            final input = _input(direction: direction, align: TextAlign.center);
            final layout = ForumBodyInlineParagraphLayout.create(
              content: input,
              width: width,
              dimensions: _dimensions(gap),
            );
            final builder = ui.ParagraphBuilder(
              ui.ParagraphStyle(
                textDirection: direction,
                textAlign: TextAlign.center,
                fontFamily: 'Ahem',
                fontSize: 20,
                height: 1,
              ),
            );
            builder.pushStyle(
              ui.TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
            );
            builder.addPlaceholder(
              20,
              30,
              PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              baselineOffset: 26,
            );
            builder.pushStyle(
              ui.TextStyle(fontFamily: 'Ahem', fontSize: gap, height: 0),
            );
            builder.addText(' ');
            builder.pop();
            builder.addPlaceholder(
              20,
              30,
              PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              baselineOffset: 26,
            );
            final reference = builder.build()
              ..layout(ui.ParagraphConstraints(width: width));
            try {
              final actual = await _pixels((c) {
                layout.paintParent(c, Offset.zero);
                for (final index
                    in layout.fragment(0, layout.lines.length).atomIndices) {
                  c.drawRect(
                    layout.atomBoxes[index].toRect(),
                    Paint()
                      ..color = index == 0
                          ? const Color(0xffff0000)
                          : index == 2
                          ? const Color(0xff0000ff)
                          : const Color(0xff00ff00),
                  );
                }
              });
              final boxes = reference.getBoxesForPlaceholders();
              final expected = await _pixels((c) {
                c.drawRect(
                  boxes[0].toRect(),
                  Paint()..color = const Color(0xffff0000),
                );
                if (!wrapped) {
                  final left = boxes[0].right < boxes[1].right
                      ? boxes[0].right
                      : boxes[1].right;
                  c.drawRect(
                    Rect.fromLTWH(left, boxes[0].top, gap, 30),
                    Paint()..color = const Color(0xff00ff00),
                  );
                }
                c.drawRect(
                  boxes[1].toRect(),
                  Paint()..color = const Color(0xff0000ff),
                );
              });
              expect(actual, expected);
            } finally {
              reference.dispose();
              layout.dispose();
            }
          },
        );
      }
    }
  }
  test(
    'already scaled fractional glue is not scaled again by the native parent',
    () {
      for (final scaler in [
        const TextScaler.linear(1.27),
        _NonlinearScaler(),
      ]) {
        final layout = ForumBodyInlineParagraphLayout.create(
          content: _input(),
          width: 50.375,
          dimensions: _dimensions(10.375),
          textScaler: scaler,
        );
        try {
          expect(layout.lines.length, 1);
          expect(layout.height, 30);
          expect(layout.atomBoxes[1].right - layout.atomBoxes[1].left, 10.375);
        } finally {
          layout.dispose();
        }
      }
    },
  );
  test('justification allocates padding around the original measured glue', () {
    final layout = ForumBodyInlineParagraphLayout.create(
      content: _input(align: TextAlign.justify, suffix: ' C'),
      width: 60,
      dimensions: _dimensions(10),
    );
    try {
      expect(layout.lines.length, 2);
      expect(layout.isAtomTrimmed(1), isFalse);
      final gap = layout.atomBoxes[1].toRect();
      expect(gap.width, 10);
      expect(gap.left, 25);
      final hit =
          layout.hitAt(Offset(22, gap.center.dy)) as ForumBodyInlineAtomHit;
      expect(hit.index, 1);
      expect(hit.offset.dx, -3);
    } finally {
      layout.dispose();
    }
  });
  for (final direction in TextDirection.values) {
    for (final width in [50.0, 49.0, 20.0]) {
      test(
        'actual native glue retains or trims by neighbour rows $direction width=$width',
        () async {
          final input = _input(direction: direction);
          final dims = _dimensions(10);
          expect(() => input.textSpan, throwsStateError);
          final layout = ForumBodyInlineParagraphLayout.create(
            content: input,
            width: width,
            dimensions: dims,
          );
          try {
            final wrapped = width < 50;
            expect(layout.lines.length, wrapped ? 2 : 1);
            expect(layout.height, wrapped ? 60 : 30);
            expect(layout.isAtomTrimmed(1), wrapped);
            expect(
              layout.fragment(0, layout.lines.length).atomIndices.toList(),
              wrapped ? [0, 2] : [0, 1, 2],
            );
            expect(
              layout.selection(1, 2).atoms.map((a) => a.index),
              wrapped ? [] : [1],
            );
            expect(layout.atomBoxes[0].right - layout.atomBoxes[0].left, 20);
            if (wrapped) {
              expect(layout.fragment(0, 1).atomIndices, [0]);
              expect(layout.fragment(1, 2).atomIndices, [2]);
              expect(layout.atomBoxes[1].toRect().isEmpty, isTrue);
            } else {
              final gap = layout.atomBoxes[1].toRect();
              expect(gap.width, 10);
              final hit = layout.hitAt(gap.center) as ForumBodyInlineAtomHit;
              expect(hit.index, 1);
              expect(hit.offset, const Offset(5, 15));
            }
            final ink = await _pixels(
              (c) => layout.paintParent(c, Offset.zero),
            );
            expect(ink.every((v) => v == 0), isTrue);
          } finally {
            layout.dispose();
          }
          expect(() => layout.isAtomTrimmed(1), throwsStateError);
        },
      );
    }
    test(
      'a huge trimmed glue cannot create an extra row or inflate the frame $direction',
      () {
        final layout = ForumBodyInlineParagraphLayout.create(
          content: _input(direction: direction),
          width: 20,
          dimensions: _dimensions(1000, gapHeight: 1000),
        );
        try {
          expect(layout.lines.length, 2);
          expect(layout.height, 60);
          expect(layout.trimmedAtomIndices, [1]);
        } finally {
          layout.dispose();
        }
      },
    );
  }
  test(
    'same-row actual gap height must fit the native neighbour baseline envelope',
    () {
      expect(
        () => ForumBodyInlineParagraphLayout.create(
          content: _input(),
          width: 50,
          dimensions: _dimensions(10, gapHeight: 1000),
        ),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
    },
  );
  for (final advance in [0.0, 9.90234375, 12.571334838867188, 16000.375]) {
    test(
      'native glue keeps an exact zero or large fractional advance $advance',
      () {
        final layout = ForumBodyInlineParagraphLayout.create(
          content: _input(),
          width: 40 + advance,
          dimensions: _dimensions(advance),
        );
        try {
          expect(layout.lines.length, 1);
          expect(layout.height, 30);
          expect(layout.isAtomTrimmed(1), isFalse);
          expect(layout.atomBoxes[1].right - layout.atomBoxes[1].left, advance);
        } finally {
          layout.dispose();
        }
      },
    );
  }
  test(
    'soft glue cache identity, warm reuse, frame budget and owner retirement',
    () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      final input = _input();
      final dims = _dimensions(10);
      final lease = cache.acquireInline(
        content: input,
        width: 50,
        dimensions: dims,
      );
      final parent = lease.layout;
      expect(cache.layoutBuildCount, 1);
      expect(parent.fragmentFrameBytes, 16 + 3 + 6 * 8);
      lease.release();
      final warm = cache.tryAcquireInlineCached(
        content: input,
        width: 50,
        dimensions: dims,
      )!;
      expect(identical(warm.layout, parent), isTrue);
      expect(cache.layoutBuildCount, 1);
      final opaque = cache.acquireInline(
        content: _input(soft: false),
        width: 50,
        dimensions: dims,
      );
      expect(identical(opaque.layout, parent), isFalse);
      opaque.release();
      cache.close();
      expect(parent.isDisposed, isTrue);
      expect(cache.activeLeases, 0);
      expect(cache.estimatedRetainedBytes, 0);
      warm.release();
    },
  );
}

class _NonlinearScaler extends TextScaler {
  @override
  double scale(double fontSize) =>
      fontSize < 24 ? fontSize * 2 : fontSize * 1.3;
  @override
  double get textScaleFactor => 2;
}
