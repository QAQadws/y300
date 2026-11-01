import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyRubyGroupContent _input(ForumBodyStyleScope scope) {
  final document = const ForumBodyParser().parse(
    html:
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scope in ForumBodyStyleScope.values) {
    for (final ratio in [1, 3]) {
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
              // The interior of the actual annotation's SPACE has no glyph ink.
              final x = ((group.annotationOffset.dx + 15) * ratio).floor();
              final y = ((group.annotationOffset.dy + 5) * ratio).floor();
              final offset = (y * image.width + x) * 4;
              expect(
                bytes.buffer.asUint8List(bytes.offsetInBytes + offset, 4),
                cleared ? [255, 255, 255, 255] : [255, 224, 0, 255],
              );
            } finally {
              image.dispose();
            }
          } finally {
            picture.dispose();
            group.close();
            expect(cache.activeLeases, 0);
            cache.close();
          }
        },
      );
    }
  }
}
