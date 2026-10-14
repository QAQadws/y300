import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:html/parser.dart' as parser;

import 'render_test_support.dart';

void main() {
  const smallPlanner = ForumHtmlSafeDisplayPlanner(
    minCodeUnits: 0,
    targetChunkCodeUnits: 80,
    maxChunkCodeUnits: 1024,
  );

  testWidgets('changing the logical tail updates an already cached factory', (
    tester,
  ) async {
    final document = prepareRenderTestDocument('<p>marker-0 tail</p>');
    Future<void> pump(bool hasTrailingContent) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              key: const Key('body'),
              child: _renderer(
                document,
                layout: ForumHtmlContentLayout.compact,
                hasTrailingContent: hasTrailingContent,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(false);
    final element = tester.element(find.byType(ForumHtmlRenderer));
    final height = tester.getSize(find.byKey(const Key('body'))).height;
    await pump(true);
    expect(tester.element(find.byType(ForumHtmlRenderer)), same(element));
    expect(
      tester.getSize(find.byKey(const Key('body'))).height,
      closeTo(height + renderTestOptions.paragraphSpacing, 0.01),
    );
    await pump(false);
    expect(
      tester.getSize(find.byKey(const Key('body'))).height,
      closeTo(height, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  test(
    'plans are immutable values and keep the logical root and resources',
    () {
      final html = List.generate(
        20,
        (i) => 'line-$i ${'正文🙂' * 10}<br>',
      ).join();
      final document = prepareRenderTestDocument(
        html,
        sourceId: 'logical-body',
      );
      final plan = smallPlanner.plan(document);
      expect(plan.kind, ForumHtmlSafeDisplayPlanKind.textLines);
      expect(plan.chunks.length, greaterThan(1));
      expect(plan.sourceHtml, same(document.preparedHtml));
      expect(plan.sourceId, 'logical-body');
      expect(plan.chunks.map((chunk) => chunk.sourceId).toSet(), {
        'logical-body',
      });
      expect(
        plan.chunks.map((chunk) => chunk.layoutIdentity).toSet().length,
        plan.chunks.length,
      );
      expect(plan.chunks.last.hasTrailingContent, isFalse);
      expect(plan.unitCount, 21);
      expect(plan.chunks.first.startUnit, 0);
      for (var unit = 0; unit < plan.unitCount; unit++) {
        final chunk = plan.chunkForUnit(unit)!;
        expect(unit, inInclusiveRange(chunk.startUnit, chunk.endUnit - 1));
      }
      expect(plan.chunkForUnit(-1), isNull);
      expect(plan.chunkForUnit(plan.unitCount), isNull);
      expect(
        plan.chunks
            .take(plan.chunks.length - 1)
            .every((chunk) => chunk.hasTrailingContent),
        isTrue,
      );
      expect(() => plan.chunks.clear(), throwsUnsupportedError);
      final attached = document.copyWith(safeDisplayPlan: plan);
      expect(attached.copyWith().safeDisplayPlan, same(plan));
      final part = attached.copyWith(
        preparedHtml: plan.chunks.first.html,
        clearSafeDisplayPlan: true,
      );
      expect(part.safeDisplayPlan, isNull);
      expect(part.sequence, same(document.sequence));
      expect(part.attachmentIdsByUrl, same(document.attachmentIdsByUrl));
      expect(
        parser.parseFragment(plan.chunks.map((part) => part.html).join()).text,
        parser.parseFragment(html).text,
      );
    },
  );

  test('source units survive length-changing projections and regrouping', () {
    ForumHtmlSafeDisplayPlan lines(int repeat) => smallPlanner.plan(
      prepareRenderTestDocument(
        List.generate(24, (i) => 'unit-$i ${'字' * repeat}').join('<br><br>'),
        sourceId: 'same-owner',
      ),
    );
    final original = lines(16);
    final expanded = lines(80);
    expect(original.unitCount, 47);
    expect(expanded.unitCount, original.unitCount);
    expect(expanded.chunks.length, greaterThan(original.chunks.length));
    for (var line = 0; line < 24; line++) {
      final unit = line * 2;
      expect(original.chunkForUnit(unit)!.html, contains('unit-$line '));
      expect(expanded.chunkForUnit(unit)!.html, contains('unit-$line '));
    }
    final paragraphs = smallPlanner.plan(
      prepareRenderTestDocument(
        List.generate(
          12,
          (i) => '<p>unit-$i ${'字' * 20}</p>\n<!--edge-->',
        ).join(),
      ),
    );
    expect(paragraphs.unitCount, 12);
    for (var unit = 0; unit < 12; unit++) {
      expect(paragraphs.chunkForUnit(unit)!.html, contains('unit-$unit '));
    }
  });

  test('fixed 48-unit chunks retain boundaries across length expansion', () {
    const planner = ForumHtmlSafeDisplayPlanner(
      minCodeUnits: 0,
      targetChunkUnits: 48,
    );
    for (final paragraphs in [false, true]) {
      ForumHtmlSafeDisplayPlan plan(int repeat) {
        final html = List.generate(
          127,
          (unit) => paragraphs
              ? '<p>unit-$unit ${'字' * repeat}</p>\n'
              : 'unit-$unit ${'字' * repeat}',
        ).join(paragraphs ? '' : '<br>');
        return planner.plan(prepareRenderTestDocument(html));
      }

      final original = plan(20);
      final translated = plan(80);
      expect(original.isChunked, isTrue);
      expect(translated.isChunked, isTrue);
      expect(original.chunks.map((c) => (c.startUnit, c.endUnit)), [
        (0, 48),
        (48, 96),
        (96, 127),
      ]);
      expect(
        translated.chunks.map((c) => (c.startUnit, c.endUnit)),
        original.chunks.map((c) => (c.startUnit, c.endUnit)),
      );
      expect(translated.unitCount, 127);
    }
  });

  test(
    'fixed units still reject oversized chunks without moving their boundary',
    () {
      const planner = ForumHtmlSafeDisplayPlanner(
        minCodeUnits: 0,
        targetChunkUnits: 48,
      );
      final html = List.generate(
        96,
        (i) => 'line-$i ${'字' * 200}',
      ).join('<br>');
      final document = prepareRenderTestDocument(html);
      final plan = planner.plan(document);
      expect(plan.isChunked, isFalse);
      expect(
        plan.fallbackReason,
        ForumHtmlSafeDisplayFallbackReason.oversizedChunk,
      );
      expect(plan.chunks.single.html, same(document.preparedHtml));
    },
  );

  test(
    'prepared plan is transferable from real isolate as read-only values',
    () async {
      final document = prepareRenderTestDocument(
        List.generate(360, (i) => '<p>unit-$i ${'正文' * 48}</p>').join(),
        sourceId: 'background-owner',
      );
      final synchronous = const ForumHtmlSafeDisplayPlanner().plan(document);
      final prepared = await Isolate.run(() {
        final plan = const ForumHtmlSafeDisplayPlanner().plan(document);
        return document.copyWith(safeDisplayPlan: plan);
      });
      final background = prepared.safeDisplayPlan!;
      expect(background.kind, synchronous.kind);
      expect(background.sourceId, synchronous.sourceId);
      expect(background.sourceHtml, synchronous.sourceHtml);
      expect(background.unitCount, synchronous.unitCount);
      expect(
        background.chunks.map(
          (c) =>
              (c.ordinal, c.html, c.startUnit, c.endUnit, c.hasTrailingContent),
        ),
        synchronous.chunks.map(
          (c) =>
              (c.ordinal, c.html, c.startUnit, c.endUnit, c.hasTrailingContent),
        ),
      );
      expect(prepared.sequence.sourceId, document.sequence.sourceId);
      expect(prepared.themeSignature, document.themeSignature);
      expect(() => background.chunks.clear(), throwsUnsupportedError);
    },
  );

  test('short input and a single unbreakable text stay byte exact', () {
    final short = prepareRenderTestDocument('short<br>body');
    final shortPlan = const ForumHtmlSafeDisplayPlanner().plan(short);
    expect(shortPlan.isChunked, isFalse);
    expect(
      shortPlan.fallbackReason,
      ForumHtmlSafeDisplayFallbackReason.belowThreshold,
    );
    expect(shortPlan.chunks.single.html, same(short.preparedHtml));
    final plain = prepareRenderTestDocument('正文' * 20000);
    final plan = smallPlanner.plan(plain);
    expect(plan.isChunked, isFalse);
    expect(
      plan.fallbackReason,
      ForumHtmlSafeDisplayFallbackReason.noSafeBoundaries,
    );
    expect(plan.chunks.single.html, same(plain.preparedHtml));
  });

  test(
    'complex structure is a whole document fallback with original image sequence',
    () {
      final unsafe = [
        '<div style="background:red;padding:8px"><p>text</p></div>',
        '<p style="margin:20px">text</p><p>more</p>',
        '<p style="white-space:pre-wrap">text</p><p>more</p>',
        '<p id="target">text</p><p><a href="#target">jump</a></p>',
        '<p><img src="https://example.invalid/image.jpg"></p>',
        '<p><ruby>字<rt>annotation</rt></ruby></p>',
        '<table><tr><td>text</td></tr></table>',
        '<ol><li>first</li><li>second</li></ol>',
        '<div class="showcollapse_box"><div class="showcollapse_content">fold</div></div>',
        '<y300-forum-text-chunk>reserved</y300-forum-text-chunk>',
        'text<br class="author-break">text',
        '<p><span style="padding:2px">decorated inline</span></p>',
        '<p>${'字' * 100}</p><p></p><p>next</p>',
        '<p>${'字' * 100}</p><p> \n\t</p><p>next</p>',
        '<p>${'字' * 100}</p><p><br></p><p>next</p>',
        '<p>${'字' * 100}</p>&nbsp;<p>next</p>',
      ];
      for (final html in unsafe) {
        final document = prepareRenderTestDocument(html);
        final plan = smallPlanner.plan(document);
        expect(plan.kind, ForumHtmlSafeDisplayPlanKind.whole, reason: html);
        expect(plan.chunks.single.html, same(document.preparedHtml));
        final attached = document.copyWith(safeDisplayPlan: plan);
        expect(attached.sequence, same(document.sequence));
      }
    },
  );

  test(
    'oversized atomic chunks fall back rather than cutting a word or paragraph',
    () {
      final html = '${'字' * 2000}<br>${'文' * 2000}<br>end';
      final document = prepareRenderTestDocument(html);
      final plan = smallPlanner.plan(document);
      expect(plan.isChunked, isFalse);
      expect(
        plan.fallbackReason,
        ForumHtmlSafeDisplayFallbackReason.oversizedChunk,
      );
      expect(plan.chunks.single.html, same(document.preparedHtml));
    },
  );

  for (final separator in ['<br>', '<br><br>', '<br> \r\n<br>\r\n']) {
    testWidgets(
      'plain line geometry and all blank spacing survive: $separator',
      (tester) async {
        final html = List.generate(
          18,
          (i) => 'marker-$i ${'字' * 20}',
        ).join(separator);
        final document = prepareRenderTestDocument(html);
        final plan = smallPlanner.plan(document);
        expect(plan.isChunked, isTrue);
        await tester.pumpWidget(_scene(document, plan));
        await tester.pumpAndSettle();
        _expectGeometry(tester, [for (var i = 0; i < 18; i++) 'marker-$i']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final layout in ForumHtmlContentLayout.values) {
    testWidgets(
      'paragraphs retain edges and author inline typography in $layout',
      (tester) async {
        final html = List.generate(
          12,
          (i) =>
              '<p>marker-$i <span style="color:red;font-weight:bold">style</span>'
              '<font size="4">size</font> tail</p>\n',
        ).join();
        final document = prepareRenderTestDocument(html);
        final plan = smallPlanner.plan(document);
        expect(plan.kind, ForumHtmlSafeDisplayPlanKind.paragraphs);
        await tester.pumpWidget(_scene(document, plan, layout: layout));
        await tester.pumpAndSettle();
        _expectGeometry(tester, [for (var i = 0; i < 12; i++) 'marker-$i']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final direction in TextDirection.values) {
    testWidgets('line edges and scaling retain geometry in $direction', (
      tester,
    ) async {
      final body = List.generate(
        16,
        (i) => 'marker-$i 正文🙂&amp;${'字' * 24}',
      ).join('<br>\n<br>');
      final html = '<br><br> \n<!--head-->$body<br><br>\n<!--tail-->';
      final document = prepareRenderTestDocument(html);
      final plan = smallPlanner.plan(document);
      expect(plan.isChunked, isTrue);
      await tester.pumpWidget(
        _scene(
          document,
          plan,
          direction: direction,
          textScaler: const TextScaler.linear(1.15),
          textStyle: const TextStyle(fontSize: 19.2, height: 1.37),
          textAlign: TextAlign.center,
        ),
      );
      await tester.pumpAndSettle();
      _expectGeometry(tester, [for (var i = 0; i < 16; i++) 'marker-$i']);
      expect(tester.takeException(), isNull);
    });
  }

  for (final paragraphs in [false, true]) {
    testWidgets(
      'fixed unit geometry keeps whitespace and compact edges: P=$paragraphs',
      (tester) async {
        const planner = ForumHtmlSafeDisplayPlanner(
          minCodeUnits: 0,
          targetChunkUnits: 4,
        );
        final body = List.generate(
          18,
          (i) => paragraphs
              ? '<p>marker-$i <span style="color:red">${'字' * 8}</span></p>\n'
              : 'marker-$i ${'字' * 8}',
        ).join(paragraphs ? '' : '<br>\n<br>');
        final html = paragraphs
            ? '\n<!--head-->$body<!--tail-->'
            : '<br><br>\n$body<br><br>\n<!--tail-->';
        final document = prepareRenderTestDocument(html);
        final plan = planner.plan(document);
        expect(plan.isChunked, isTrue);
        await tester.pumpWidget(
          _scene(
            document,
            plan,
            layout: ForumHtmlContentLayout.compact,
            textScaler: const TextScaler.linear(1.15),
            textStyle: const TextStyle(fontSize: 19.2, height: 1.37),
          ),
        );
        await tester.pumpAndSettle();
        _expectGeometry(tester, [for (var i = 0; i < 18; i++) 'marker-$i']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final layout in ForumHtmlContentLayout.values) {
    testWidgets('paragraph zero margins and direction retain $layout', (
      tester,
    ) async {
      final body = List.generate(
        14,
        (i) =>
            '<p style="margin:0;direction:rtl;text-align:right">marker-$i '
            '<span style="font-size:150%;line-height:1.2">גדול</span>'
            '<a href="https://example.invalid/target">link</a></p>\n',
      ).join();
      final html = '\n<!--head-->$body<!--tail-->';
      final document = prepareRenderTestDocument(html);
      final plan = smallPlanner.plan(document);
      expect(plan.kind, ForumHtmlSafeDisplayPlanKind.paragraphs);
      await tester.pumpWidget(
        _scene(
          document,
          plan,
          layout: layout,
          direction: TextDirection.rtl,
          textScaler: const TextScaler.linear(1.15),
          textStyle: const TextStyle(fontSize: 19.2, height: 1.37),
        ),
      );
      await tester.pumpAndSettle();
      _expectGeometry(tester, [for (var i = 0; i < 14; i++) 'marker-$i']);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _scene(
  ForumHtmlPreparedRenderDocument document,
  ForumHtmlSafeDisplayPlan plan, {
  ForumHtmlContentLayout layout = ForumHtmlContentLayout.document,
  TextStyle textStyle = const TextStyle(fontSize: 18, height: 1.5),
  TextScaler textScaler = TextScaler.noScaling,
  TextDirection direction = TextDirection.ltr,
  TextAlign? textAlign,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: Directionality(textDirection: direction, child: child!),
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              key: const Key('whole'),
              child: _renderer(
                document,
                layout: layout,
                textStyle: textStyle,
                textAlign: textAlign,
              ),
            ),
            Container(
              key: const Key('parts'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final chunk in plan.chunks)
                    _renderer(
                      document.copyWith(
                        preparedHtml: chunk.html,
                        clearSafeDisplayPlan: true,
                      ),
                      layout: layout,
                      hasTrailingContent: chunk.hasTrailingContent,
                      textStyle: textStyle,
                      textAlign: textAlign,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

Widget _renderer(
  ForumHtmlPreparedRenderDocument document, {
  required ForumHtmlContentLayout layout,
  bool hasTrailingContent = false,
  TextStyle textStyle = const TextStyle(fontSize: 18, height: 1.5),
  TextAlign? textAlign,
}) => ForumHtmlRenderer(
  preparedDocument: document,
  theme: forumHtmlTestTheme,
  options: renderTestOptions,
  labels: renderTestLabels,
  textStyle: textStyle,
  textAlign: textAlign,
  sourceId: document.sequence.sourceId,
  contentLayout: layout,
  hasTrailingContent: hasTrailingContent,
  buildAsync: false,
  enableCaching: true,
);

void _expectGeometry(WidgetTester tester, List<String> markers) {
  final whole = find.byKey(const Key('whole'));
  final parts = find.byKey(const Key('parts'));
  for (final marker in markers) {
    final fullBox = _markerBox(tester, whole, marker);
    final partBox = _markerBox(tester, parts, marker);
    expect(partBox.left, closeTo(fullBox.left, 0.01), reason: marker);
    expect(partBox.top, closeTo(fullBox.top, 0.01), reason: marker);
    expect(partBox.width, closeTo(fullBox.width, 0.01), reason: marker);
    expect(partBox.height, closeTo(fullBox.height, 0.01), reason: marker);
  }
  expect(
    tester.getSize(parts).height,
    closeTo(tester.getSize(whole).height, 0.01),
  );
}

Rect _markerBox(WidgetTester tester, Finder body, String marker) {
  final text = find.descendant(
    of: body,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is RichText && widget.text.toPlainText().contains('$marker '),
    ),
  );
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final plainText = paragraph.text.toPlainText();
  final start = plainText.indexOf('$marker ');
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: start + marker.length),
  );
  final rect = boxes.first.toRect();
  return rect.shift(
    paragraph.localToGlobal(Offset.zero) - tester.getTopLeft(body),
  );
}
