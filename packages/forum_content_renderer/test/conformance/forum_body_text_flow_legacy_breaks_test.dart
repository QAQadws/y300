import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _style = TextStyle(
  fontSize: 10,
  height: 1,
  fontFamily: 'Ahem',
  letterSpacing: 0,
  wordSpacing: 0,
);

void main() {
  for (final html in [
    '<font>a</font>',
    '<font>a<br></font>',
    '<font>a<br><br></font>',
    '<span><br></span>',
    '<span><br><br></span>',
    '<span>a<br>b</span>',
    '<span>a<br></span><p>b</p>',
    '<pre>a<br></pre>',
    '<span>a<br> \t </span>',
    '<span> \t <br> \t </span>',
    '<span>a<span style="font-size:40px"><br></span></span>',
    '<span>a<span style="font-size:40px"><br></span>b</span>',
    '<p dir="rtl">אבג<br>דהו<br></p>',
    '<span>甲e<i>́</i><br><b>乙</b><br></span>',
  ]) {
    testWidgets('native text-flow glyph height matches legacy: $html', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 200,
                child: HtmlWidget(html, textStyle: _style),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rich = find.byType(RichText);
      final legacyHeight = [
        for (var index = 0; index < rich.evaluate().length; index++)
          tester.getSize(rich.at(index)).height,
      ].fold<double>(0, (sum, value) => sum + value);
      final document = const ForumBodyParser().parse(
        html: html,
        sourceId: 'synthetic-comparison',
        conversionIdentity: 'none',
      );
      final cursor = ForumBodyTextFlowCursor(
        document: document,
        reader: ForumBodyReaderStyle(
          textStyle: _style,
          fontRevision: 'ahem',
          linkColor: const Color(0xff0000ff),
        ),
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      var nativeHeight = 0.0;
      try {
        while (!cursor.isComplete) {
          cursor.advance(maxEvents: 2);
          final unit = cursor.current;
          if (unit is! ForumBodyTextFlowParagraph) continue;
          final lease = cache.acquire(content: unit.content, width: 200);
          try {
            final window = lease.layout.lineWindow(unit.window);
            nativeHeight += lease.layout.lines.isEmpty
                ? lease.layout.height
                : lease.layout
                      .fragment(window.startLine, window.endLine)
                      .height;
          } finally {
            lease.release();
          }
        }
        expect(nativeHeight, closeTo(legacyHeight, .001));
        expect(cache.activeLeases, 0);
        expect(tester.takeException(), isNull);
      } finally {
        cursor.close();
        cache.close();
      }
    });
  }
}
