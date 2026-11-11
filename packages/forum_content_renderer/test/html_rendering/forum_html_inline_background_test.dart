import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:html/dom.dart' as html_dom;

import 'render_test_support.dart';

const _color = Color(0xFFFFCC00);
const _options = ForumHtmlRenderOptions(
  fontScale: 1,
  lineHeightScale: 1.7,
  paragraphSpacing: 0,
  preserveAuthorFontSize: true,
);
const _content =
    '前😀 Alpha beta gamma שלום مرحبا delta epsilon zeta<br><br>下一段文字';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('preserves native layout and selection boxes in $direction', (
      tester,
    ) async {
      for (final scale in [1.0, 1.8]) {
        await tester.pumpWidget(
          _app(html: _content, direction: direction, scale: scale),
        );
        await tester.pumpAndSettle();
        final native = _paragraph(tester);
        final size = native.size;
        final baseline = native.getDryBaseline(
          native.constraints,
          TextBaseline.alphabetic,
        );
        final length = native.text
            .toPlainText(includeSemanticsLabels: false)
            .length;
        final boxes = native.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: length),
        );
        final intrinsicWidth = native.getMaxIntrinsicWidth(double.infinity);
        await tester.pumpWidget(
          _app(
            html: '<span style="background-color:#ffcc00">$_content</span>',
            direction: direction,
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        final rounded = _paragraph(tester);
        expect(rounded.size, size);
        expect(rounded.getMaxIntrinsicWidth(double.infinity), intrinsicWidth);
        expect(
          rounded.getDryBaseline(rounded.constraints, TextBaseline.alphabetic),
          baseline,
        );
        expect(
          rounded
              .getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: length),
              )
              .map((box) => box.toRect()),
          boxes.map((box) => box.toRect()),
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('rounded lines leave corners, line ends and blank lines clear', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        html:
            '<span style="background-color:#ffcc00;color:transparent">ABCD<br><br>EF</span>',
      ),
    );
    await tester.pumpAndSettle();
    final paragraph = _paragraph(tester);
    final plain = paragraph.text.toPlainText(includeSemanticsLabels: false);
    final first = _box(paragraph, 0, 4);
    final last = _box(paragraph, plain.indexOf('EF'), plain.length);
    expect(
      _render(tester),
      paints
        ..rrect(rrect: RRect.fromRectAndRadius(first, const Radius.circular(4)))
        ..rrect(rrect: RRect.fromRectAndRadius(last, const Radius.circular(4))),
    );
    final pixels = await _pixels(tester);
    expect(pixels.at(first.center), _color);
    expect(pixels.at(first.topLeft), Colors.white);
    expect(pixels.at(Offset(first.right + 4, first.center.dy)), Colors.white);
    expect(pixels.at(Offset(5, (first.bottom + last.top) / 2)), Colors.white);
    pixels.image.dispose();
  });

  testWidgets('alignment repaint reads current paragraph coordinates', (
    tester,
  ) async {
    const html = '<span style="background-color:#ffcc00">AB</span>';
    await tester.pumpWidget(_app(html: html));
    await tester.pumpAndSettle();
    final oldLeft = _box(_paragraph(tester), 0, 2).left;
    await tester.pumpWidget(_app(html: html, alignment: TextAlign.right));
    await tester.pumpAndSettle();
    final box = _box(_paragraph(tester), 0, 2);
    expect(box.left, greaterThan(oldLeft));
    expect(
      _render(tester),
      paints
        ..rrect(rrect: RRect.fromRectAndRadius(box, const Radius.circular(4))),
    );
  });

  for (final title in ['世界观', '角色介绍']) {
    for (final inTable in [false, true]) {
      testWidgets('rounds clipped fullwidth spaces: $title, table=$inTable', (
        tester,
      ) async {
        final heading =
            '<div align="center"><strong>'
            '<font style="font-size:125%"><font color="#777777">'
            '<font style="background-color:#ffcc00;color:transparent">'
            '　$title　</font></font></font></strong></div>';
        await tester.pumpWidget(
          _app(
            html: inTable
                ? '<table><tr><td>$heading</td></tr></table>'
                : heading,
            width: 300,
          ),
        );
        await tester.pumpAndSettle();
        final paragraph = _paragraph(tester);
        final length = paragraph.text.toPlainText().length;
        final raw = paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: length),
            )
            .map((box) => box.toRect())
            .reduce((a, b) => a.expandToInclude(b));
        // Reproduce the centered paragraph whose trailing fullwidth space
        // extends beyond its shrink-wrapped width; clipping an RRect loses a cap.
        expect(raw.right, greaterThan(paragraph.size.width));
        final visible = raw.intersect(Offset.zero & paragraph.size);
        final expected = MatrixUtils.transformRect(
          paragraph.getTransformTo(_render(tester)),
          visible,
        );
        expect(
          _render(tester),
          paints..rrect(
            rrect: RRect.fromRectAndRadius(expected, const Radius.circular(4)),
          ),
        );
        final bounds = MatrixUtils.transformRect(
          paragraph.getTransformTo(
            tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('pixels')),
            ),
          ),
          visible,
        );
        final pixels = await _pixels(tester);
        expect(
          pixels.at(Offset(bounds.right - 0.1, bounds.top + 0.1)),
          Colors.white,
        );
        expect(pixels.at(Offset(bounds.right - 1, bounds.center.dy)), _color);
        pixels.image.dispose();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('formatting runs join into one highlight on the same line', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(html: '<span style="background-color:#ffcc00"><b>AB</b>CD</span>'),
    );
    await tester.pumpAndSettle();
    final joined = _paragraph(tester)
        .getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 4),
        )
        .map((box) => box.toRect())
        .reduce((a, b) => a.expandToInclude(b));
    expect(
      _render(tester),
      paints..rrect(
        rrect: RRect.fromRectAndRadius(joined, const Radius.circular(4)),
      ),
    );
    expect(
      _styleFor(_paragraph(tester).text, 'AB')!.fontWeight,
      FontWeight.bold,
    );
  });

  testWidgets('nested colors and transparent resets retain UTF-16 ranges', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        html:
            '<span style="background-color:#ffcc00;color:transparent">A😀'
            '<span style="background-color:#0066cc">B</span>'
            '<span style="background-color:transparent">C</span>D</span>',
      ),
    );
    await tester.pumpAndSettle();
    final paragraph = _paragraph(tester);
    expect(paragraph.text.toPlainText(), 'A😀BCD');
    final pixels = await _pixels(tester);
    // Color emoji can paint independently of CSS foreground transparency.
    // Sample A; the following B still proves the surrogate-pair offset.
    expect(pixels.at(_box(paragraph, 0, 1).center), _color);
    expect(pixels.at(_box(paragraph, 3, 4).center), const Color(0xFF0066CC));
    expect(pixels.at(_box(paragraph, 4, 5).center), Colors.white);
    expect(pixels.at(_box(paragraph, 5, 6).center), _color);
    pixels.image.dispose();
  });

  testWidgets('inline images keep their placeholder and an unpainted gap', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        html:
            '<span style="background-color:#ffcc00;color:transparent">A'
            '<img width="40" height="20" data-original="static/image/smiley/test.gif" '
            'src="data:image/gif;base64,'
            'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7">B</span>',
      ),
    );
    await tester.pumpAndSettle();
    final paragraph = _paragraph(tester);
    expect(paragraph.text.toPlainText(), 'A\uFFFCB');
    expect(
      paragraph.text.getSpanForPosition(const TextPosition(offset: 1)),
      isA<WidgetSpan>(),
    );
    final pixels = await _pixels(tester);
    expect(pixels.at(_box(paragraph, 1, 2).center), Colors.white);
    expect(pixels.at(_box(paragraph, 0, 1).center), _color);
    expect(pixels.at(_box(paragraph, 2, 3).center), _color);
    pixels.image.dispose();
  });

  testWidgets('bidi selections leave uncolored text clear', (tester) async {
    await tester.pumpWidget(
      _app(
        html:
            '<span style="color:transparent">'
            '<span style="background-color:#ffcc00">AB </span>אבגד'
            '<span style="background-color:#ffcc00"> CD</span></span>',
        width: 300,
      ),
    );
    await tester.pumpAndSettle();
    final pixels = await _pixels(tester);
    expect(pixels.at(_box(_paragraph(tester), 3, 7).center), Colors.white);
    pixels.image.dispose();
  });

  testWidgets('width, color and removal do not retain old paint', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(html: '<span style="background-color:#ffcc00">ABCDEFGHIJKL</span>'),
    );
    await tester.pumpAndSettle();
    final oldHeight = _paragraph(tester).size.height;
    await tester.pumpWidget(
      _app(
        html: '<span style="background-color:#2196f3">ABCDEFGHIJKL</span>',
        width: 100,
      ),
    );
    await tester.pumpAndSettle();
    expect(_paragraph(tester).size.height, greaterThan(oldHeight));
    expect(_render(tester), paints..rrect(color: const Color(0xFF2196F3)));
    await tester.pumpWidget(_app(html: 'plain'));
    await tester.pumpAndSettle();
    expect(_render(tester), isNot(paints..rrect()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('links and selection still belong to the original RichText', (
    tester,
  ) async {
    final urls = <String>[];
    String? selected;
    await tester.pumpWidget(
      _app(
        html:
            '<a href="https://example.com/" style="background-color:#ffcc00">click me</a>',
        onTapUrl: (url) {
          urls.add(url);
          return true;
        },
        onSelection: (content) => selected = content?.plainText,
      ),
    );
    await tester.pumpAndSettle();
    final paragraph = find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == 'click me',
    );
    expect(tester.widget<RichText>(paragraph).selectionRegistrar, isNotNull);
    await tester.tap(paragraph);
    expect(urls, ['https://example.com/']);
    final rect = tester.getRect(paragraph);
    await tester.dragFrom(
      rect.topLeft + const Offset(1, 10),
      const Offset(175, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(selected, 'click me');
  });

  testWidgets('block backgrounds and concealed text keep their native paint', (
    tester,
  ) async {
    for (final html in [
      '<div style="background-color:#ffcc00">block</div>',
      '<span style="background-color:#ffcc00;color:#ffcc00">concealed</span>',
    ]) {
      await tester.pumpWidget(_app(html: html));
      await tester.pumpAndSettle();
      expect(_render(tester), isNot(paints..rrect()));
      if (html.contains('concealed')) {
        expect(
          _styleFor(
            _paragraph(tester).text,
            'concealed',
          )!.background!.color.toARGB32(),
          _color.toARGB32(),
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('shared factory leaves the prepared HTML unchanged', (
    tester,
  ) async {
    const html =
        '<p>before <span style="background-color:#ffcc00">highlight '
        '<a href="https://example.com/">link</a></span> after</p>';
    final document = prepareRenderTestDocument(html);
    final prepared = document.preparedHtml;
    await tester.pumpWidget(
      MaterialApp(
        home: ForumHtmlRenderer(
          preparedDocument: document,
          theme: forumHtmlTestTheme,
          options: renderTestOptions,
          labels: renderTestLabels,
          buildAsync: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(document.preparedHtml, prepared);
    expect(
      _paragraph(tester).text.toPlainText(),
      'before highlight link after',
    );
    expect(_render(tester), paints..rrect());
  });
}

Widget _app({
  required String html,
  double width = 180,
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
  TextAlign alignment = TextAlign.start,
  ValueChanged<SelectedContent?>? onSelection,
  bool Function(String)? onTapUrl,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: RepaintBoundary(
          key: const Key('pixels'),
          child: ColoredBox(
            color: Colors.white,
            child: SelectionArea(
              onSelectionChanged: onSelection,
              child: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Directionality(
                  textDirection: direction,
                  child: ForumHtmlRenderer(
                    preparedDocument: prepareRenderTestDocument(
                      html,
                      options: _options,
                      themeAdapter: const _OriginalColors(),
                    ),
                    theme: forumHtmlTestTheme,
                    options: _options,
                    labels: renderTestLabels,
                    textStyle: const TextStyle(fontSize: 20, height: 1.7),
                    textAlign: alignment,
                    buildAsync: false,
                    callbacks: ForumHtmlRenderCallbacks(onTapUrl: onTapUrl),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

RenderParagraph _paragraph(WidgetTester tester) => tester.renderObject(
  find
      .descendant(
        of: find.byType(ForumHtmlRenderer),
        matching: find.byType(RichText),
      )
      .first,
);

RenderObject _render(WidgetTester tester) =>
    tester.renderObject(find.byType(ForumHtmlRenderer));

Rect _box(RenderParagraph paragraph, int start, int end) => paragraph
    .getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: end))
    .first
    .toRect();

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

Future<({ui.Image image, Color Function(Offset) at})> _pixels(
  WidgetTester tester,
) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('pixels')),
  );
  final image = (await tester.runAsync(() => boundary.toImage()))!;
  final bytes = (await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
  ))!;
  Color at(Offset point) {
    final index = (point.dy.floor() * image.width + point.dx.floor()) * 4;
    return Color.fromARGB(
      bytes.getUint8(index + 3),
      bytes.getUint8(index),
      bytes.getUint8(index + 1),
      bytes.getUint8(index + 2),
    );
  }

  return (image: image, at: at);
}

class _OriginalColors implements ForumHtmlThemeAdapter {
  const _OriginalColors();

  @override
  ForumHtmlThemeAdaptationResult adapt({
    required html_dom.DocumentFragment fragment,
    required ForumHtmlThemeContext theme,
    required ForumHtmlColorAdaptationPolicy policy,
  }) => ForumHtmlThemeAdaptationResult(
    fragment: fragment,
    stats: ForumHtmlThemeAdaptationStats.none,
  );
}
