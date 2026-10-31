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
  // Legacy behavior is measured separately, not used as the CSS oracle. Its
  // tight root constraint can swallow preferred width, percentage padding is
  // ignored, and its min/max conflict resolves differently. The native target
  // follows normal-flow content-box rules, with min-width winning the conflict.
  for (final (css, legacySize, legacyLeft, nativeSize, nativeLeft) in [
    (
      'margin:0 10px;padding:10px',
      const Size(160, 30),
      20.0,
      const Size(160, 30),
      20.0,
    ),
    ('margin:0', const Size(200, 30), 0.0, const Size(200, 30), 0.0),
    (
      'width:80px;margin:0 auto;padding:10px',
      const Size(180, 30),
      10.0,
      const Size(80, 60),
      60.0,
    ),
    (
      'width:60%;margin:0 auto;padding:5%',
      const Size(200, 30),
      0.0,
      const Size(120, 40),
      40.0,
    ),
    (
      'max-width:50%;margin:0 auto;padding:10px',
      const Size(90, 60),
      10.0,
      const Size(100, 50),
      50.0,
    ),
    (
      'width:180px;max-width:80px;min-width:100px;margin:0 auto',
      const Size(80, 60),
      0.0,
      const Size(100, 50),
      50.0,
    ),
    (
      'margin:0 10px;padding:10%',
      const Size(180, 30),
      10.0,
      const Size(140, 40),
      30.0,
    ),
  ]) {
    testWidgets('records legacy and native content-box geometry: $css', (
      tester,
    ) async {
      final html = '<div style="$css">${'abcdefghijklmnop' * 3}</div>';
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
      final richText = find.byType(RichText);
      expect(richText, findsOneWidget);
      final document = const ForumBodyParser().parse(
        html: html,
        sourceId: 'synthetic-box-legacy',
        conversionIdentity: 'none',
      );
      final styles = const ForumBodyStyleResolver().resolve(
        document,
        ForumBodyReaderStyle(
          textStyle: _textStyle,
          fontRevision: 'ahem',
          linkColor: const Color(0xff0000ff),
        ),
      );
      final box = ForumBodyBlockBox.resolve(
        style: styles.byPath['0']!,
        containingWidth: 200,
        containingDirection: TextDirection.ltr,
        rootFontSize: 10,
      );
      final content = const ForumBodyParagraphContentBuilder().build(
        document: document,
        styles: styles,
        path: '0',
      );
      final layout = ForumBodyParagraphLayout.create(
        content: content,
        width: box.contentWidth,
      );
      try {
        expect(tester.getSize(richText), legacySize);
        final outerLeft = tester.getTopLeft(find.byType(HtmlWidget)).dx;
        expect(tester.getTopLeft(richText).dx - outerLeft, legacyLeft);
        expect(Size(box.contentWidth, layout.height), nativeSize);
        expect(box.contentLeft, nativeLeft);
        expect(tester.takeException(), isNull);
      } finally {
        layout.dispose();
      }
    });
  }
}
