import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'render_test_support.dart';

void main() {
  Widget app(String html, {required bool decorate}) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(
          width: 180,
          child: ForumHtmlRenderer(
            preparedDocument: prepareRenderTestDocument(html),
            theme: forumHtmlTestTheme,
            options: renderTestOptions,
            labels: renderTestLabels,
            buildAsync: false,
            blockDecorator: decorate ? (_, child) => child : null,
          ),
        ),
      ),
    ),
  );

  testWidgets('BR paragraphs preserve shaping, blank lines, links and layout', (
    tester,
  ) async {
    const html =
        '<div class="message"><br>Alpha 😀<br><br>'
        '<font color="red"><b>Beta wraps into several real shaped lines at this width.</b></font><br>'
        '<a href="https://example.com/">Gamma 你好</a><br><br></div>';
    await tester.pumpWidget(app(html, decorate: false));
    await tester.pumpAndSettle();
    final text = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains('Alpha'),
    );
    final baseline = tester.getRect(text);
    final baselineSpan = tester.widget<RichText>(text).text;
    await tester.pumpWidget(app(html, decorate: true));
    await tester.pumpAndSettle();
    expect(tester.getRect(text), baseline);
    expect(
      tester.widget<RichText>(text).text.toPlainText(),
      baselineSpan.toPlainText(),
    );
    final metrics = tester.renderObject<RenderForumHtmlParagraphMetrics>(
      find.byType(ForumHtmlParagraphMetrics),
    );
    expect(metrics.paragraphs, hasLength(3));
    expect(
      metrics.paragraphs[1].height,
      greaterThan(metrics.paragraphs[0].height),
    );
    for (var i = 1; i < metrics.paragraphs.length; i++) {
      expect(
        metrics.paragraphs[i].top,
        greaterThan(metrics.paragraphs[i - 1].top),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('atomic boxes keep their paragraphs together', (tester) async {
    await tester.pumpWidget(
      app(
        '<blockquote>Quote A<br>Quote B</blockquote>'
        '<table><tr><td>Cell A<br>Cell B</td></tr></table>'
        '<div style="border:1px solid red">Box A<br>Box B</div>'
        '<div><div align="left">Independent A</div><div align="left">Independent B</div></div>',
        decorate: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ForumHtmlParagraphMetrics), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
