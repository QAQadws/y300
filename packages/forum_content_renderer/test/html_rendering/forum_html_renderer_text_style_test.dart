import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'render_test_support.dart';

void main() {
  testWidgets('resolved style is not scaled twice and author CSS still wins', (
    tester,
  ) async {
    const style = TextStyle(
      fontSize: 19.5,
      height: 1.7,
      fontFamily: 'serif',
      fontWeight: FontWeight.w700,
    );
    await tester.pumpWidget(_app(style: style, alignment: TextAlign.center));
    await tester.pumpAndSettle();

    final plain = _paragraph(tester, 'plain base');
    final plainStyle = _styleFor(plain.text, 'plain base')!;
    expect(plainStyle.fontSize, 19.5);
    expect(plainStyle.fontFamily, 'serif');
    expect(plainStyle.fontWeight, FontWeight.w700);
    expect(plain.textAlign, TextAlign.center);
    final authorStyle = _styleFor(plain.text, 'author size')!;
    expect(authorStyle.fontSize, 26);
    expect(authorStyle.fontWeight, FontWeight.w400);
    expect(_paragraph(tester, 'author paragraph').textAlign, TextAlign.left);
    expect(tester.takeException(), isNull);
  });

  testWidgets('null style keeps the original theme and options projection', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final plain = _paragraph(tester, 'plain base');
    expect(_styleFor(plain.text, 'plain base')!.fontSize, 20);
    expect(plain.textAlign, TextAlign.start);
  });

  testWidgets('cached body updates alignment and style without remounting', (
    tester,
  ) async {
    const firstStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
    await tester.pumpWidget(
      _app(style: firstStyle, alignment: TextAlign.center),
    );
    await tester.pumpAndSettle();
    final body = tester.element(
      find.byKey(const Key('forum-html-renderer-style-override')),
    );
    await tester.pumpWidget(_app(style: firstStyle, alignment: TextAlign.end));
    await tester.pumpAndSettle();

    expect(_paragraph(tester, 'plain base').textAlign, TextAlign.end);
    expect(_paragraph(tester, 'author paragraph').textAlign, TextAlign.left);
    expect(
      tester.element(
        find.byKey(const Key('forum-html-renderer-style-override')),
      ),
      same(body),
    );

    const nextStyle = TextStyle(
      fontSize: 23,
      fontFamily: 'monospace',
      fontWeight: FontWeight.w500,
    );
    await tester.pumpWidget(_app(style: nextStyle, alignment: TextAlign.end));
    await tester.pumpAndSettle();
    final style = _styleFor(
      _paragraph(tester, 'plain base').text,
      'plain base',
    )!;
    expect(style.fontSize, 23);
    expect(style.fontFamily, 'monospace');
    expect(style.fontWeight, FontWeight.w500);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'nullable alignment returns to the default cached body alignment',
    (tester) async {
      await tester.pumpWidget(
        _app(alignment: TextAlign.center, ambientAlignment: TextAlign.center),
      );
      await tester.pumpAndSettle();
      final body = tester.element(
        find.byKey(const Key('forum-html-renderer-style-override')),
      );
      expect(_paragraph(tester, 'plain base').textAlign, TextAlign.center);

      await tester.pumpWidget(_app(ambientAlignment: TextAlign.center));
      await tester.pumpAndSettle();
      expect(_paragraph(tester, 'plain base').textAlign, TextAlign.start);

      await tester.pumpWidget(
        _app(alignment: TextAlign.right, ambientAlignment: TextAlign.center),
      );
      await tester.pumpAndSettle();
      expect(_paragraph(tester, 'plain base').textAlign, TextAlign.right);
      expect(_paragraph(tester, 'author paragraph').textAlign, TextAlign.left);
      expect(
        tester.element(
          find.byKey(const Key('forum-html-renderer-style-override')),
        ),
        same(body),
      );
    },
  );
}

const _html =
    '<p>plain base <span style="font-size:26px;font-weight:400">'
    'author size</span></p><p style="text-align:left">author paragraph</p>';
const _options = ForumHtmlRenderOptions(
  fontScale: 2,
  lineHeightScale: 1.5,
  paragraphSpacing: 12,
  preserveAuthorFontSize: true,
);

Widget _app({
  TextStyle? style,
  TextAlign? alignment,
  TextAlign? ambientAlignment,
}) => MaterialApp(
  theme: ThemeData(
    textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 10)),
  ),
  home: Scaffold(
    body: SizedBox(
      width: 300,
      child: DefaultTextStyle.merge(
        textAlign: ambientAlignment,
        child: ForumHtmlRenderer(
          preparedDocument: prepareRenderTestDocument(_html, options: _options),
          theme: forumHtmlTestTheme,
          options: _options,
          labels: renderTestLabels,
          textStyle: style,
          textAlign: alignment,
          sourceId: 'style-override',
          buildAsync: false,
          enableCaching: true,
        ),
      ),
    ),
  ),
);

RichText _paragraph(WidgetTester tester, String text) =>
    tester.widget<RichText>(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains(text),
      ),
    );

TextStyle? _styleFor(
  InlineSpan span,
  String text, [
  TextStyle parent = const TextStyle(),
]) {
  final style = parent.merge(span.style);
  if (span is TextSpan) {
    if (span.text?.contains(text) ?? false) return style;
    for (final child in span.children ?? const <InlineSpan>[]) {
      final found = _styleFor(child, text, style);
      if (found != null) return found;
    }
  }
  return null;
}
