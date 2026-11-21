import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'render_test_support.dart';

void main() {
  const smallPlanner = ForumHtmlSafeDisplayPlanner(
    minCodeUnits: 0,
    targetChunkCodeUnits: 80,
    maxChunkCodeUnits: 1024,
  );

  test('canonical planning takes ownership of the existing roots', () {
    final document = prepareRenderTestDocument('<p>first</p><p>second</p>');
    final fragment = parser.parseFragment(document.preparedHtml);
    const planner = ForumHtmlSafeDisplayPlanner(
      minCodeUnits: 0,
      targetChunkUnits: 1,
    );
    final plan = planner.planPrepared(document, ownedFragment: fragment);
    expect(fragment.nodes, isEmpty);
    expect(plan.chunks.map((c) => c.html), ['<p>first</p>', '<p>second</p>']);
  });

  test('preparation preserves the serialized planner output byte for byte', () {
    const planner = ForumHtmlSafeDisplayPlanner(
      minCodeUnits: 0,
      targetChunkUnits: 2,
    );
    for (final html in [
      '字&amp;🙂<br><br> &lt; <br><!-- 注 -->末行<br>',
      '<p style="color:#ddd">https://example.org/a?q=1&amp;b=2</p>'
          '<p>繁體 <em>🙂</em></p>\n<p>段落 &nbsp; 三</p>',
      '<p title="A&#13;B">前&#13;&#10;后</p><p>二</p><p>三</p>',
      '前&#13;后<br>二<br>三',
      '<div>首&amp;行<br><!--空行--><br>二<br>三<br></div>',
      '<div><strong>首行</strong><br>https://example.org/map<br><b>末行</b></div>',
      '<p>未闭合<b>加粗<p>乙</b><p>丙',
      '\n<!--head--><div><p>甲</p><p>乙<br>续</p><p>丙</p></div>\n',
      '<div style="padding:12px"><p>一</p><p>二</p><p>三</p></div>',
      '<p>甲</p><img id="aimg_7" src="page.jpg"><p>乙</p>',
    ]) {
      final options = renderTestOptions.copyWith(enablePlainTextLinks: true);
      final original = prepareRenderTestDocument(html, options: options);
      final expected = planner.plan(original);
      final prepared = prepareRenderTestDocument(
        html,
        options: options,
        displayPlanner: planner,
      );
      final actual = prepared.safeDisplayPlan!;
      expect(prepared.preparedHtml, original.preparedHtml);
      expect(actual.sourceHtml, same(prepared.preparedHtml));
      expect(actual.kind, expected.kind);
      expect(actual.fallbackReason, expected.fallbackReason);
      expect(
        actual.chunks.map(
          (c) => (c.html, c.startUnit, c.endUnit, c.hasTrailingContent),
        ),
        expected.chunks.map(
          (c) => (c.html, c.startUnit, c.endUnit, c.hasTrailingContent),
        ),
      );
    }
  });

  test(
    'planning leaves a custom preparation codec’s retained roots intact',
    () {
      final fragment = parser.parseFragment('<p>first</p><p>second</p>');
      final prepared = prepareRenderTestDocument(
        'source',
        fragmentCodec: _OwnedFragmentCodec(fragment),
        displayPlanner: const ForumHtmlSafeDisplayPlanner(
          minCodeUnits: 0,
          targetChunkUnits: 1,
        ),
      );
      expect(fragment.children, hasLength(2));
      expect(prepared.safeDisplayPlan!.chunks.map((c) => c.html), [
        '<p>first</p>',
        '<p>second</p>',
      ]);
    },
  );

  test('an injected planner codec still parses the serialized document', () {
    final codec = _OwnedFragmentCodec(
      parser.parseFragment('<p>changed</p><p>tail</p>'),
    );
    final prepared = prepareRenderTestDocument(
      '<p>original</p>',
      displayPlanner: ForumHtmlSafeDisplayPlanner(
        minCodeUnits: 0,
        targetChunkUnits: 1,
        fragmentCodec: codec,
      ),
    );
    expect(codec.parseCount, 1);
    expect(prepared.safeDisplayPlan!.chunks.first.html, '<p>changed</p>');
    expect(prepared.preparedHtml, '<p>original</p>');
  });

  test('large leading wrappers keep the original whole display document', () {
    final body = List.generate(3000, (unit) => 'marker[$unit] 正文<br>').join();
    for (final tag in ['font', 'span']) {
      final document = prepareRenderTestDocument('<$tag>$body</$tag>');
      final plan = const ForumHtmlSafeDisplayPlanner().plan(document);
      expect(plan.isChunked, isFalse);
      expect(
        plan.fallbackReason,
        ForumHtmlSafeDisplayFallbackReason.unsupportedStructure,
      );
      expect(plan.chunks.single.html, same(document.preparedHtml));
      expect(
        document.copyWith(safeDisplayPlan: plan).sequence,
        same(document.sequence),
      );
    }
  });

  test('custom fragment codecs keep responsibility for root parsing', () {
    final document = prepareRenderTestDocument('<font>custom source</font>');
    final codec = _OwnedFragmentCodec(
      parser.parseFragment('<p>first</p><p>second</p>'),
    );
    final plan = ForumHtmlSafeDisplayPlanner(
      minCodeUnits: 0,
      targetChunkUnits: 1,
      fragmentCodec: codec,
    ).plan(document);
    expect(codec.parseCount, 1);
    expect(plan.isChunked, isTrue);
    expect(plan.unitCount, 2);
  });

  test('only one bare DIV containing ordinary paragraphs can be split', () {
    const planner = ForumHtmlSafeDisplayPlanner(
      minCodeUnits: 0,
      targetChunkUnits: 1,
    );
    const ps = '<p>one</p><p>two</p>';
    for (final html in [
      '<div dir="rtl">$ps</div>',
      '<div style="padding:12px">$ps</div>',
      '<div>$ps</div><p>outside</p>',
      'before<div>$ps</div>',
      '<div><div>$ps</div></div>',
      '<div>mixed$ps</div>',
      '<div><p style="margin:0">one</p><p>two</p></div>',
      '<div><p><img src="x.png"></p>$ps</div>',
      '<div><p></p>$ps</div>',
      '<div class="quote">one<br>two<br>three</div>',
      '<div>one<br id="anchor">two<br>three</div>',
      '<div>one<br><b id="anchor">two</b><br>three</div>',
      '<div>one<br>two</div><div>three<br>four</div>',
      'outside<div>one<br>two<br>three</div>',
    ]) {
      final doc = prepareRenderTestDocument(html);
      expect(
        planner.plan(doc).chunks.single.html,
        same(doc.preparedHtml),
        reason: html,
      );
    }
  });

  test(
    'BR chunks retain complete inline links, styles and a link-only tail',
    () {
      const planner = ForumHtmlSafeDisplayPlanner(
        minCodeUnits: 0,
        targetChunkCodeUnits: 3,
      );
      const head = '<b><strong>一二三</strong></b>';
      const tail =
          '<a target="_blank" rel="nofollow" href="https://example.org/map">'
          '<b>末行</b></a>';
      for (final wrapped in [false, true]) {
        const body = '$head<br><br>$tail<br>';
        final doc = prepareRenderTestDocument(
          wrapped ? '<div>$body</div>' : body,
        );
        final plan = planner.plan(doc);
        expect(
          plan.kind,
          ForumHtmlSafeDisplayPlanKind.textLines,
          reason: '${plan.fallbackReason}: ${doc.preparedHtml}',
        );
        expect(plan.chunks.map((c) => (c.startUnit, c.endUnit)), [
          (0, 1),
          (1, 4),
        ]);
        expect(plan.chunks.first.html, contains(head));
        final preparedLink = parser
            .parseFragment(doc.preparedHtml)
            .querySelector('a')!;
        expect(
          plan.chunks.last.html,
          contains('<br>${preparedLink.outerHtml}<br>'),
        );
      }
    },
  );

  test(
    'BR chunks preserve prepared inline colors at the beginning and end',
    () {
      const planner = ForumHtmlSafeDisplayPlanner(
        minCodeUnits: 0,
        targetChunkUnits: 1,
      );
      const body =
          '<font color="#af283d">红</font>普通字<br><br>'
          '<b><font style="color:#15639a">蓝</font></b><br>';
      for (final wrapped in [false, true]) {
        final doc = prepareRenderTestDocument(
          wrapped ? '<div>$body</div>' : body,
          displayPlanner: planner,
        );
        final plan = doc.safeDisplayPlan!;
        final source = parser.parseFragment(doc.preparedHtml);
        expect(plan.kind, ForumHtmlSafeDisplayPlanKind.textLines);
        expect(plan.chunks.map((c) => (c.startUnit, c.endUnit)), [
          (0, 1),
          (1, 4),
        ]);
        expect(
          plan.chunks.first.html,
          contains('${source.querySelector('font')!.outerHtml}普通字'),
        );
        expect(
          plan.chunks.last.html,
          contains('<br>${source.querySelector('b')!.outerHtml}<br>'),
        );
      }
    },
  );

  test(
    'BR planner keeps spanning formatting, local anchors and styled layout whole',
    () {
      const planner = ForumHtmlSafeDisplayPlanner(
        minCodeUnits: 0,
        targetChunkUnits: 1,
      );
      for (final inline in [
        '<b>跨<br>行</b>',
        '<font color="red">跨<br>行</font>',
        '<font color="red" size="5">大字</font>',
        '<font color="red" id="anchor">锚点</font>',
        '<font style="color:red;display:block">块</font>',
        '<a href="https://example.org/map">跨<br>行</a>',
        '<a href="#jump">跳转</a>',
        '<a href="https://example.org/map" style="display:block">块</a>',
        '<strong><img src="map.png"></strong>',
      ]) {
        final doc = prepareRenderTestDocument('甲<br>$inline<br>乙');
        expect(
          planner.plan(doc).chunks.single.html,
          same(doc.preparedHtml),
          reason: inline,
        );
      }
    },
  );

  test('complete paragraph inline wrappers still undergo DOM admission', () {
    final document = prepareRenderTestDocument(
      '<p><span><font>first</font></span></p><p>second</p>',
    );
    final codec = _OwnedFragmentCodec(
      parser.parseFragment(document.preparedHtml),
    );
    final plan = ForumHtmlSafeDisplayPlanner(
      minCodeUnits: 0,
      targetChunkUnits: 1,
      fragmentCodec: codec,
    ).plan(document);
    expect(codec.parseCount, 1);
    expect(plan.isChunked, isTrue);
    expect(plan.unitCount, 2);
  });

  for (final paragraphs in [false, true]) {
    for (final units in [128, 10000]) {
      test(
        'owned $units roots detach together without sibling removals: P=$paragraphs',
        () {
          final counter = _RootRemovalWork();
          final fragment = dom.DocumentFragment();
          final roots = <dom.Node>[];
          for (var unit = 0; unit < units; unit++) {
            final label = 'unit[$unit] 正文🙂 & < > "';
            if (paragraphs) {
              roots.add(
                _ObservedElement('p', counter)
                  ..nodes.add(
                    dom.Element.tag('span')
                      ..attributes['style'] = 'font-weight:bold'
                      ..nodes.add(dom.Text(label)),
                  ),
              );
            } else {
              if (unit > 0) roots.add(_ObservedElement('br', counter));
              roots.add(_ObservedText(label, counter));
            }
          }
          fragment.nodes.addAll(roots);
          counter.root = fragment;
          final codec = _OwnedFragmentCodec(fragment);
          final html = const HtmlPackageForumHtmlFragmentCodec().serialize(
            fragment,
          );
          final document = prepareRenderTestDocument(html);
          final expectedFirst = const HtmlPackageForumHtmlFragmentCodec()
              .serialize(
                dom.DocumentFragment()
                  ..nodes.addAll(
                    paragraphs
                        ? roots.take(48).map((node) => node.clone(true))
                        : [
                            dom.Element.tag('y300-forum-text-chunk')
                              ..attributes['style'] = 'display:block;margin:0'
                              ..nodes.addAll(
                                roots.take(95).map((node) => node.clone(true)),
                              ),
                          ],
                  ),
              );
          final plan = ForumHtmlSafeDisplayPlanner(
            minCodeUnits: 0,
            targetChunkUnits: 48,
            fragmentCodec: codec,
          ).plan(document);
          expect(plan.isChunked, isTrue);
          expect(plan.unitCount, units);
          expect(plan.chunks.first.html, expectedFirst);
          expect(plan.chunks.last.endUnit, units);
          expect(codec.parseCount, 1);
          expect(fragment.nodes, isEmpty);
          expect(counter.parentedRemovals, 0);
          expect(counter.siblingWork, 0);
          expect(
            parser
                .parseFragment(plan.chunks.map((chunk) => chunk.html).join())
                .text,
            parser.parseFragment(document.preparedHtml).text,
          );
        },
      );
    }
  }

  test(
    'rejected structure keeps its owned roots intact and bytes unchanged',
    () {
      final fragment = parser.parseFragment(
        '<div><p>unsupported ancestor</p></div>',
      );
      final root = fragment.nodes.single;
      final document = prepareRenderTestDocument(
        const HtmlPackageForumHtmlFragmentCodec().serialize(fragment),
      );
      final plan = ForumHtmlSafeDisplayPlanner(
        minCodeUnits: 0,
        fragmentCodec: _OwnedFragmentCodec(fragment),
      ).plan(document);
      expect(plan.isChunked, isFalse);
      expect(plan.chunks.single.html, same(document.preparedHtml));
      expect(fragment.nodes.single, same(root));
      expect(root.parentNode, same(fragment));
    },
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
      'wrapped BR lines retain blank lines and document edges in $layout',
      (tester) async {
        const planner = ForumHtmlSafeDisplayPlanner(
          minCodeUnits: 0,
          targetChunkUnits: 3,
        );
        final doc = prepareRenderTestDocument(
          ' <!--outside--><div><br>marker-0 正文🙂<br>marker-1 甲<br><!-- seam --><br><br>marker-2 乙<br>marker-3 丙<br><br>marker-4 丁<br><br></div>\n',
        );
        final plan = planner.plan(doc);
        expect(plan.kind, ForumHtmlSafeDisplayPlanKind.textLines);
        expect(plan.chunks.map((c) => (c.startUnit, c.endUnit)), [
          (0, 3),
          (3, 6),
          (6, 11),
        ]);
        expect(plan.sourceHtml, same(doc.preparedHtml));
        await tester.pumpWidget(_scene(doc, plan, layout: layout));
        await tester.pumpAndSettle();
        _expectGeometry(tester, [for (var i = 0; i < 5; i++) 'marker-$i']);
      },
    );
    testWidgets('inline links and bold retain BR geometry in $layout', (
      tester,
    ) async {
      const planner = ForumHtmlSafeDisplayPlanner(
        minCodeUnits: 0,
        targetChunkUnits: 2,
      );
      final doc = prepareRenderTestDocument(
        '<div>marker-0 正文<br><a href="https://example.org/a"><b>marker-1 地图</b></a>'
        '<br><br><strong>marker-2 周末开放</strong><br>marker-3 https://example.org/b'
        '<br><b>marker-4 末行</b><br></div>',
        options: renderTestOptions.copyWith(enablePlainTextLinks: true),
      );
      final plan = planner.plan(doc);
      expect(
        plan.kind,
        ForumHtmlSafeDisplayPlanKind.textLines,
        reason: '${plan.fallbackReason}: ${doc.preparedHtml}',
      );
      expect(plan.chunks.map((c) => (c.startUnit, c.endUnit)), [
        (0, 2),
        (2, 4),
        (4, 7),
      ]);
      await tester.pumpWidget(_scene(doc, plan, layout: layout));
      await tester.pumpAndSettle();
      _expectGeometry(tester, [for (var i = 0; i < 5; i++) 'marker-$i']);
    });

    testWidgets(
      'bare outer DIV preserves paragraph geometry across seams in $layout',
      (tester) async {
        final body = List.generate(
          9,
          (i) => '<p>marker-$i <b>粗体</b> 段落🙂</p>',
        ).join('\n');
        final document = prepareRenderTestDocument(
          '\n<!--head--><div>\n$body\n</div>\n',
        );
        const planner = ForumHtmlSafeDisplayPlanner(
          minCodeUnits: 0,
          targetChunkUnits: 3,
        );
        final plan = planner.plan(document);
        expect(plan.chunks.map((c) => (c.startUnit, c.endUnit)), [
          (0, 3),
          (3, 6),
          (6, 9),
        ]);
        expect(plan.sourceHtml, same(document.preparedHtml));
        await tester.pumpWidget(_scene(document, plan, layout: layout));
        await tester.pumpAndSettle();
        _expectGeometry(tester, [for (var i = 0; i < 9; i++) 'marker-$i']);
      },
    );
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

final class _RootRemovalWork {
  dom.Node? root;
  int parentedRemovals = 0;
  int siblingWork = 0;

  void removing(dom.Node node) {
    if (root == null || !identical(node.parentNode, root)) return;
    parentedRemovals++;
    siblingWork += root!.nodes.length;
  }
}

final class _ObservedText extends dom.Text {
  _ObservedText(super.data, this.counter);
  final _RootRemovalWork counter;

  @override
  dom.Node remove() {
    counter.removing(this);
    return super.remove();
  }
}

final class _ObservedElement extends dom.Element {
  _ObservedElement(super.localName, this.counter) : super.tag();
  final _RootRemovalWork counter;

  @override
  dom.Node remove() {
    counter.removing(this);
    return super.remove();
  }
}

final class _OwnedFragmentCodec implements ForumHtmlFragmentCodec {
  _OwnedFragmentCodec(this.fragment);
  final dom.DocumentFragment fragment;
  int parseCount = 0;

  @override
  dom.DocumentFragment parse(String html) {
    parseCount++;
    return fragment;
  }

  @override
  String serialize(dom.DocumentFragment fragment) =>
      const HtmlPackageForumHtmlFragmentCodec().serialize(fragment);
}
