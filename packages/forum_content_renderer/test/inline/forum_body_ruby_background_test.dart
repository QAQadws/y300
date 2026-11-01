import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyRubyGroupContent _input(ForumBodyStyleScope scope, {String? html}) {
  final document = const ForumBodyParser().parse(
    html:
        html ??
        '<ruby style="background:#ffe000">AB<rt style="background:inherit">x y</rt></ruby>',
    sourceId: 'rt-background',
    conversionIdentity: 'none',
  );
  final flow = ForumBodyStyledFlowCursor(
    document: document,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        height: 1,
        color: Color(0xff000000),
      ),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
      policy: ForumBodyStylePolicy({ForumBodyStyleProperty.background: scope}),
    ),
  );
  try {
    expect(flow.moveNext(), true);
    final cursor = ForumBodyRubyContentCursor.openCurrent(flow);
    ForumBodyRubyGroupContent? group;
    try {
      while (!cursor.isComplete) {
        final step = cursor.advance(maxEvents: 1);
        if (step.hasOutput) group = cursor.current;
      }
      return group!;
    } finally {
      cursor.close();
    }
  } finally {
    flow.close();
  }
}

Future<List<List<int>>> _samplePixels(
  ForumBodyRubyGroupLayout group,
  int ratio,
  List<Offset> samples,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(ratio.toDouble());
  canvas.drawColor(const Color(0xffffffff), BlendMode.src);
  group.paint(canvas, Offset.zero);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      (group.size.width * ratio).ceil(),
      (group.size.height * ratio).ceil(),
    );
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return [
        for (final point in samples)
          bytes.buffer
              .asUint8List(
                bytes.offsetInBytes +
                    ((point.dy * ratio).floor() * image.width +
                            (point.dx * ratio).floor()) *
                        4,
                4,
              )
              .toList(),
      ];
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scope in ForumBodyStyleScope.values) {
    for (final ratio in [1, 3]) {
      test(
        'RB native background and annotation are independently scoped ($scope,DPR$ratio)',
        () async {
          final input = _input(
            scope,
            html:
                '<ruby><rb style="background:#ffbb00">A B</rb><rt style="background:#00ffff">x y</rt></ruby>',
          );
          final base =
              ((input.base.single as ForumBodyRubyBaseContent).parts.single
                      as ForumBodyRubyTextContent)
                  .content;
          final annotation =
              (input.annotations.single.parts.single
                      as ForumBodyRubyTextContent)
                  .content;
          final cache = ForumBodyParagraphCache(
            maxEntries: 8,
            maxEstimatedBytes: 1 << 20,
          );
          final group = ForumBodyRubyGroupLayout.create(
            cache: cache,
            base: base,
            annotation: annotation,
            gap: 2,
          );
          try {
            // SPACE interiors expose paint independently of opaque Ahem glyphs.
            final samples = await _samplePixels(group, ratio, [
              group.baseOffset + const Offset(30, 10),
              group.annotationOffset + const Offset(15, 5),
            ]);
            expect(
              samples[0],
              scope == ForumBodyStyleScope.asDefault
                  ? [255, 187, 0, 255]
                  : [255, 255, 255, 255],
            );
            expect(
              samples[1],
              scope == ForumBodyStyleScope.forceAll
                  ? [255, 255, 255, 255]
                  : [0, 255, 255, 255],
            );
            expect(base.style.boxBackground, isNull);
            expect(base.projection.text, 'A B');
            expect(annotation.projection.text, 'x y');
          } finally {
            group.close();
            expect(cache.activeLeases, 0);
            cache.close();
          }
        },
      );
      test(
        'RT inherited highlight reaches actual native paint and respects policy ($scope,DPR$ratio)',
        () async {
          final input = _input(scope);
          final base = (input.base.single as ForumBodyRubyTextContent).content;
          final annotation =
              (input.annotations.single.parts.single
                      as ForumBodyRubyTextContent)
                  .content;
          final cleared = scope == ForumBodyStyleScope.forceAll;
          expect(
            annotation.style.textStyle.backgroundColor,
            cleared ? const Color(0x00000000) : const Color(0xffffe000),
          );
          expect(annotation.style.boxBackground, isNull);
          final cache = ForumBodyParagraphCache(
            maxEntries: 8,
            maxEstimatedBytes: 1 << 20,
          );
          final group = ForumBodyRubyGroupLayout.create(
            cache: cache,
            base: base,
            annotation: annotation,
            gap: 2,
          );
          try {
            final samples = await _samplePixels(group, ratio, [
              group.annotationOffset + const Offset(15, 5),
            ]);
            expect(
              samples.single,
              cleared ? [255, 255, 255, 255] : [255, 224, 0, 255],
            );
          } finally {
            group.close();
            expect(cache.activeLeases, 0);
            cache.close();
          }
        },
      );
    }
  }
}
