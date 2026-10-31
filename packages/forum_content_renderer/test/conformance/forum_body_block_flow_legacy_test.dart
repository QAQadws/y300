import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _textStyle = TextStyle(
  fontFamily: 'Ahem',
  fontSize: 10,
  height: 1,
  letterSpacing: 0,
  wordSpacing: 0,
);

void main() {
  for (final html in [
    '<p style="margin:10px 0 20px">a</p><p style="margin:30px 0 40px">b</p>',
    '<div style="margin:5px 0 7px"><p style="margin:10px 0 20px">a</p></div>',
    '<div style="margin:5px;padding:2px"><p style="margin:10px">a</p></div>',
  ]) {
    testWidgets('continuous native block glyph positions match legacy: $html', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 200,
                child: HtmlWidget(html, textStyle: _textStyle),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(find.byType(HtmlWidget));
      final legacy = find.byType(RichText);
      final positions = [
        for (var i = 0; i < legacy.evaluate().length; i++)
          tester.getTopLeft(legacy.at(i)) - origin,
      ];
      final sizes = [
        for (var i = 0; i < legacy.evaluate().length; i++)
          tester.getSize(legacy.at(i)),
      ];
      final document = const ForumBodyParser().parse(
        html: html,
        sourceId: 'synthetic-flow-comparison',
        conversionIdentity: 'none',
      );
      final cursor = ForumBodyBlockFlowCursor(
        document: document,
        reader: ForumBodyReaderStyle(
          textStyle: _textStyle,
          fontRevision: 'ahem',
          linkColor: const Color(0xff0000ff),
        ),
        width: 200,
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      var y = 0.0;
      final nativePositions = <Offset>[];
      final nativeSizes = <Size>[];
      try {
        while (!cursor.isComplete) {
          cursor.advance(maxEvents: 1);
          final unit = cursor.current;
          if (unit is ForumBodyBlockFlowSpace) {
            y += unit.extent;
          } else if (unit is ForumBodyBlockFlowParagraph) {
            final lease = cache.acquire(
              content: unit.paragraph.content,
              width: unit.contentWidth,
            );
            try {
              final range = lease.layout.lineWindow(unit.paragraph.window);
              final height = lease.layout
                  .fragment(range.startLine, range.endLine)
                  .height;
              nativePositions.add(Offset(unit.contentLeft, y));
              nativeSizes.add(Size(unit.contentWidth, height));
              y += height;
            } finally {
              lease.release();
            }
          }
        }
        expect(nativePositions, positions);
        expect(nativeSizes, sizes);
        expect(y, tester.getSize(find.byType(HtmlWidget)).height);
        expect(cache.activeLeases, 0);
        expect(tester.takeException(), isNull);
      } finally {
        cursor.close();
        cache.close();
      }
    });
  }
}
