import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontSize: 10, height: 1, fontFamily: 'Ahem'),
  fontRevision: 'synthetic-ahem',
  linkColor: const Color(0xff0000ff),
);
ForumBodyDocument _document(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'text-flow',
  conversionIdentity: 'none',
);
ForumBodyTextFlowCursor _cursor(
  ForumBodyDocument document, {
  ForumBodyParagraphContentBuilder builder =
      const ForumBodyParagraphContentBuilder(),
  bool compressBlankLines = false,
}) => ForumBodyTextFlowCursor(
  document: document,
  reader: compressBlankLines
      ? ForumBodyReaderStyle(
          textStyle: _reader.textStyle,
          fontRevision: _reader.fontRevision,
          linkColor: _reader.linkColor,
          compressBlankLines: true,
        )
      : _reader,
  paragraphBuilder: builder,
);

List<ForumBodyTextFlowUnit> _drain(
  ForumBodyTextFlowCursor cursor, {
  int budget = 2,
}) {
  final units = <ForumBodyTextFlowUnit>[];
  var calls = 0;
  while (!cursor.isComplete) {
    if (++calls > 10000) fail('Text flow did not reach EOF');
    final step = cursor.advance(maxEvents: budget);
    expect(step.eventsRead, lessThanOrEqualTo(budget));
    expect(step.workDone, lessThanOrEqualTo(budget));
    expect(step.workDone > 0 || step.hasOutput, isTrue);
    if (step.hasOutput) units.add(cursor.current!);
  }
  return units;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'blank line cleanup preserves canonical sources and remains bounded',
    () {
      final document = _document(
        '<p>甲<br> \n<br>${'<br>\n' * 550}乙</p>'
        '<p>&nbsp;</p>\n${'<p>　</p>\n' * 550}<p>丙</p>',
      );
      final original = _cursor(document);
      final cleanup = _cursor(document, compressBlankLines: true);
      addTearDown(original.close);
      addTearDown(cleanup.close);
      final originalParagraphs = _drain(
        original,
        budget: 4,
      ).whereType<ForumBodyTextFlowParagraph>().toList();
      final units = _drain(cleanup, budget: 1);
      final paragraphs = units.whereType<ForumBodyTextFlowParagraph>().toList();
      expect(originalParagraphs, hasLength(1105));
      expect(paragraphs.map((unit) => unit.content.projection.text), [
        '甲\n',
        '\n',
        '乙',
        '\u00a0',
        '丙',
      ]);
      expect(paragraphs.map((unit) => unit.identity).toSet(), {
        document.identity,
      });
      expect(units.last, isA<ForumBodyTextFlowBoundary>());
      final tail = paragraphs.last.content.projection;
      expect(
        tail.sourceAtUtf16(0).sourceRune,
        document.sourceMap.runeLength - 1,
      );
      expect(tail.sourceAtUtf16(0).isExact, isTrue);
      final omitted = document.descendants
          .whereType<ForumBodyElement>()
          .where((node) => node.kind == ForumBodyElementKind.hardBreak)
          .elementAt(2)
          .source;
      expect(
        paragraphs.expand(
          (unit) => unit.content.projection.displayRangesInSource(
            sourceStart: omitted.runeStart,
            sourceEnd: omitted.runeEnd,
            startUtf16: 0,
            endUtf16: unit.content.projection.text.length,
          ),
        ),
        isEmpty,
      );
      expect(document.sourceText, contains('乙\u00a0\n　'));
    },
  );

  test('blank line cleanup preserves protected and authored formatting', () {
    final document = _document(
      '<div class="verse">诗<br><br><br>句<p>&nbsp;</p><p>　</p></div>'
      '<pre>代<br><br><br>码</pre>'
      '<table><tr><td>表<br><br><br>格</td></tr></table>'
      '<div class="locked">权<br><br><br>限</div>'
      '<div class="showcollapse_box"><div class="showcollapse_title">标题</div>'
      '<div class="showcollapse_content">折<br><br><br>叠</div></div>'
      '<p>样<br><br><br style="color:red">式</p>'
      '<p id="blank-anchor">&nbsp;</p><p>　</p>',
    );
    Iterable<String> displayed(bool cleanup) {
      final cursor = _cursor(document, compressBlankLines: cleanup);
      addTearDown(cursor.close);
      return _drain(cursor, budget: 1)
          .whereType<ForumBodyTextFlowParagraph>()
          .map((unit) => unit.content.projection.text);
    }

    final expected = displayed(false);
    expect(expected, containsAll(['诗\n', '句', '权\n', '限', '折\n', '叠']));
    expect(displayed(true), expected);
  });

  test('Discuz span, clearance and table keep their inline source order', () {
    final document = _document(
      '<div style="padding:0 10px 0 20px">lead '
      '<span style="float:left;margin-right:5px;color:red"><b>浮動</b></span>'
      ' tail <br style="clear:both">'
      '<table class="float" style="float:right;margin-left:5px">'
      '<tbody><tr><td>格</td></tr></tbody></table>'
      'end</div>',
    );
    for (final budget in [1, 64]) {
      final cursor = ForumBodyBlockFlowCursor(
        document: document,
        reader: _reader,
        width: 180,
        dedicatedTables: true,
        captureFloats: true,
      );
      addTearDown(cursor.close);
      final units = <ForumBodyBlockFlowUnit>[];
      while (!cursor.isComplete) {
        final step = cursor.advance(maxEvents: budget);
        expect(step.workDone, lessThanOrEqualTo(budget));
        if (step.hasOutput) units.add(cursor.current!);
      }
      final flow = units.whereType<ForumBodyBlockFlowInline>().single;
      expect(units.whereType<ForumBodyBlockFlowTable>(), isEmpty);
      expect(flow.contentLeft, 20);
      expect(flow.contentWidth, 150);
      expect(flow.paragraph.index, 0);
      final content = flow.paragraph.content;
      expect(content.path, '0');
      expect(content.identity, document.identity);
      final parts = content.parts;
      expect(parts, hasLength(6));
      final lead = (parts[0] as ForumBodyInlineFlowText).content;
      final left = parts[1] as ForumBodyInlineFlowFloat;
      final tail = (parts[2] as ForumBodyInlineFlowText).content;
      final clear = parts[3] as ForumBodyInlineFlowClear;
      final right = parts[4] as ForumBodyInlineFlowFloat;
      final end = (parts[5] as ForumBodyInlineFlowText).content;
      expect(lead.projection.text, 'lead ');
      expect(tail.projection.text, ' tail ');
      expect(end.projection.text, 'end');
      for (final control in [left, clear, right]) {
        expect(
          document.nodeAtPath(control.element.path),
          same(control.element),
        );
        expect(control.event.phase, ForumBodyFlowPhase.open);
      }
      expect(left.event.style.floatSide, ForumBodyFloatSide.left);
      expect(left.event.style.margin.right, const ForumBodyLength(5));
      expect(right.element.kind, ForumBodyElementKind.table);
      expect(right.event.style.floatSide, ForumBodyFloatSide.right);
      expect(clear.event.style.clear, ForumBodyClear.both);
      expect(clear.element.source.runeEnd - clear.element.source.runeStart, 1);
      expect(
        left.element.source.runeEnd,
        lessThan(clear.element.source.runeStart),
      );
      expect(clear.element.source.runeEnd, right.element.source.runeStart);

      final nested = ForumBodyTextFlowCursor(
        document: document,
        reader: _reader,
        contentRoot: left.element,
        captureFloats: true,
      );
      addTearDown(nested.close);
      final floated = _drain(
        nested,
      ).whereType<ForumBodyTextFlowParagraph>().single;
      expect(floated.content.projection.text, '浮動');
      expect(floated.content.path, left.element.path);
      expect(
        floated.content.runs.single.style.textStyle.color,
        const Color(0xffff0000),
      );
    }
  });

  test('float subtree is deferred and BR remains a real source fence', () {
    final document = _document(
      'before<br><span style="float:right">'
      '${List.filled(600, '<i>child</i>').join()}</span>'
      '<br style="clear:left">',
    );
    final cursor = ForumBodyTextFlowCursor(
      document: document,
      reader: _reader,
      captureFloats: true,
    );
    addTearDown(cursor.close);
    final units = _drain(cursor, budget: 1);
    expect(cursor.resolvedNodeCount, 4);
    final before = units.whereType<ForumBodyTextFlowParagraph>().single;
    expect(before.content.projection.text, 'before\n');
    expect(before.window, ForumBodyParagraphWindow.beforeTerminalEmptyLine);
    final after = units.whereType<ForumBodyTextFlowInline>().single;
    expect(after.content.appliesFirstLineIndent, isFalse);
    expect(after.content.parts, [
      isA<ForumBodyInlineFlowFloat>(),
      isA<ForumBodyInlineFlowClear>(),
    ]);
    expect(after.window, ForumBodyParagraphWindow.full);
    expect(
      (units.last as ForumBodyTextFlowBoundary).trimmedTerminalBreak,
      isNull,
    );
  });

  test('clearance following a Discuz edit notice is not skipped', () {
    final cursor = ForumBodyTextFlowCursor(
      document: _document(
        '<i class="pstatus">Notice</i><br><br style="clear:right">after',
      ),
      reader: _reader,
      captureFloats: true,
    );
    addTearDown(cursor.close);
    final units = _drain(cursor);
    final notice = units.whereType<ForumBodyTextFlowParagraph>().single;
    expect(notice.content.projection.text, 'Notice');
    final parts = units
        .whereType<ForumBodyTextFlowInline>()
        .single
        .content
        .parts;
    expect(parts, hasLength(2));
    final clear = parts.first as ForumBodyInlineFlowClear;
    final after = parts.last as ForumBodyInlineFlowText;
    expect(clear.event.style.clear, ForumBodyClear.right);
    expect(after.content.projection.text, 'after');
  });

  test(
    'deferred float and clear controls count toward the structure budget',
    () {
      final cursor = ForumBodyTextFlowCursor(
        document: _document(
          '<span style="float:left">a</span><br style="clear:both">',
        ),
        reader: _reader,
        captureFloats: true,
        rubyLimits: const ForumBodyRubyContentLimits(maxStructureItems: 1),
      );
      addTearDown(cursor.close);
      expect(
        () => _drain(cursor),
        throwsA(
          isA<ForumBodyRubyContentException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyRubyContentFailure.structureLimit,
          ),
        ),
      );
      expect(cursor.isClosed, isTrue);
      expect(cursor.current, isNull);
    },
  );

  test(
    'a 100000-character v1 chapter yields a stable page without resolving the full style tree',
    () {
      final document = _document(
        '<font>${List.filled(2500, '${'正文' * 20}<br>').join()}</font>',
      );
      expect(document.sourceMap.runeLength, greaterThanOrEqualTo(100000));
      final cursor = _cursor(document);
      final cache = ForumBodyParagraphCache(
        maxEntries: 8,
        maxEstimatedBytes: 1 << 20,
      );
      final composer = ForumBodyTextPageComposer(
        identity: document.identity,
        layoutId: 'long-prefix',
        width: 200,
        height: 60,
        maxPages: 10000,
        maxFragments: 10000,
      );
      addTearDown(cursor.close);
      addTearDown(cache.close);
      addTearDown(composer.close);
      while (composer.snapshot.isEmpty) {
        cursor.advance(maxEvents: 2);
        final unit = cursor.current;
        if (unit is! ForumBodyTextFlowParagraph) continue;
        composer.append(
          lease: cache.acquire(content: unit.content, width: 200),
          paragraphIndex: unit.index,
          left: 0,
          spaceBefore: 0,
          spaceAtPageStart: 0,
          window: unit.window,
        );
        while (!composer.needsInput && composer.snapshot.isEmpty) {
          composer.advance(maxLines: 2);
        }
      }
      expect(cursor.resolvedNodeCount, lessThanOrEqualTo(10));
      expect(cursor.isComplete, isFalse);
      expect(composer.snapshot.single.usedHeight, 60);
      expect(cache.layoutBuildCount, 3);
      expect(cache.activeLeases, 0);
    },
  );

  for (final (html, texts, windows) in [
    (
      '<font>a<br>b<br></font>',
      ['a\n', 'b'],
      [
        ForumBodyParagraphWindow.beforeTerminalEmptyLine,
        ForumBodyParagraphWindow.full,
      ],
    ),
    (
      '<span>a<br><br></span>',
      ['a\n', 'a\n'],
      [
        ForumBodyParagraphWindow.beforeTerminalEmptyLine,
        ForumBodyParagraphWindow.terminalEmptyLine,
      ],
    ),
    ('<span><br></span>', <String>[], <ForumBodyParagraphWindow>[]),
    (
      '<span><br><br></span>',
      ['\n', '\n'],
      [
        ForumBodyParagraphWindow.beforeTerminalEmptyLine,
        ForumBodyParagraphWindow.terminalEmptyLine,
      ],
    ),
    (
      '<pre>a<br></pre>',
      ['a\n', 'a\n'],
      [
        ForumBodyParagraphWindow.beforeTerminalEmptyLine,
        ForumBodyParagraphWindow.terminalEmptyLine,
      ],
    ),
    ('<span>a<br> \t </span>', ['a'], [ForumBodyParagraphWindow.full]),
  ]) {
    test('hard-break compatibility: $html', () {
      final document = _document(html);
      final cursor = _cursor(document);
      addTearDown(cursor.close);
      final units = _drain(cursor, budget: 1);
      final paragraphs = units.whereType<ForumBodyTextFlowParagraph>().toList();
      expect(paragraphs.map((unit) => unit.content.projection.text), texts);
      expect(paragraphs.map((unit) => unit.window), windows);
      expect(
        paragraphs.map((unit) => unit.index),
        List.generate(paragraphs.length, (index) => index),
      );
      expect(
        units.last,
        isA<ForumBodyTextFlowBoundary>().having(
          (unit) => unit.kind,
          'kind',
          ForumBodyTextFlowBoundaryKind.endDocument,
        ),
      );
      expect(cursor.advance(maxEvents: 1), (
        eventsRead: 0,
        workDone: 0,
        hasOutput: false,
        isComplete: true,
      ));
      expect(cursor.current, isNull);
      expect(units.every((unit) => unit.identity == document.identity), isTrue);
    });
  }

  test(
    'block hierarchy remains explicit and a trimmed BR retains original provenance',
    () {
      final cursor = _cursor(
        _document('<div><font>a<br>b<br></font><p>c</p>d</div>'),
      );
      addTearDown(cursor.close);
      final units = _drain(cursor);
      expect(
        units.map(
          (unit) => switch (unit) {
            ForumBodyTextFlowParagraph() =>
              'text:${unit.content.projection.text}',
            ForumBodyTextFlowInline() => 'inline:${unit.index}',
            ForumBodyTextFlowImage() => 'image:${unit.index}',
            ForumBodyTextFlowTable() => 'table:${unit.element.path}',
            ForumBodyTextFlowBoundary() =>
              '${unit.kind.name}:${unit.event?.node.path}',
          },
        ),
        [
          'openBlock:0',
          'text:a\n',
          'text:b',
          'openBlock:0/1',
          'text:c',
          'closeBlock:0/1',
          'text:d',
          'closeBlock:0',
          'endDocument:null',
        ],
      );
      final openP = units.whereType<ForumBodyTextFlowBoundary>().firstWhere(
        (unit) =>
            unit.kind == ForumBodyTextFlowBoundaryKind.openBlock &&
            unit.event!.node.path == '0/1',
      );
      expect(openP.trimmedTerminalBreak!.node.path, '0/0/3');
      expect(openP.trimmedTerminalBreak!.node.source.runeStart, 3);
    },
  );

  test(
    'a first logical paragraph resolves only a bounded prefix of a v1 long chapter',
    () {
      final cursor = _cursor(
        _document(
          '<font>${List.generate(10000, (index) => '行$index<br>').join()}</font>',
        ),
      );
      addTearDown(cursor.close);
      ForumBodyTextFlowParagraph? first;
      while (first == null) {
        final step = cursor.advance(maxEvents: 2);
        expect(step.eventsRead, lessThanOrEqualTo(2));
        if (cursor.current is ForumBodyTextFlowParagraph) {
          first = cursor.current as ForumBodyTextFlowParagraph;
        }
      }
      expect(first.content.projection.text, '行0\n');
      expect(cursor.resolvedNodeCount, lessThanOrEqualTo(6));
      expect(cursor.isComplete, isFalse);
    },
  );

  test('hidden breaks do not create rows and diagnostics stay drainable', () {
    final cursor = _cursor(
      _document('<font style="float:left">a<br hidden>b<br></font>'),
    );
    addTearDown(cursor.close);
    cursor.advance(maxEvents: 1);
    final issues = cursor.takePendingIssues();
    expect(issues.single.property, 'float');
    expect(() => issues.clear(), throwsUnsupportedError);
    final units = _drain(cursor);
    final paragraph = units.whereType<ForumBodyTextFlowParagraph>().single;
    expect(paragraph.content.projection.text, 'ab');
    expect(paragraph.content.projection.sourceAtUtf16(1).isExact, isFalse);
    expect(cursor.takePendingIssues(), isEmpty);
  });

  test(
    'late input-limit failure keeps already composed pages and releases unfinished sequences',
    () {
      final document = _document('<font>ok<br>ok<br>${'x' * 1000}</font>');
      final cursor = _cursor(
        document,
        builder: const ForumBodyParagraphContentBuilder(maxInputCodeUnits: 100),
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      final composer = ForumBodyTextPageComposer(
        identity: document.identity,
        layoutId: 'scope',
        width: 100,
        height: 10,
        maxPages: 20,
        maxFragments: 20,
      );
      addTearDown(cursor.close);
      addTearDown(cache.close);
      addTearDown(composer.close);
      while (cursor.current is! ForumBodyTextFlowParagraph) {
        cursor.advance(maxEvents: 2);
      }
      final first = cursor.current as ForumBodyTextFlowParagraph;
      composer.append(
        lease: cache.acquire(content: first.content, width: 100),
        paragraphIndex: first.index,
        left: 0,
        spaceBefore: 0,
        spaceAtPageStart: 0,
        window: first.window,
      );
      composer.advance(maxLines: 2);
      final snapshot = composer.snapshot;
      expect(snapshot, hasLength(1));
      expect(
        () => cursor.advance(maxEvents: 20),
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyParagraphInputFailure.inputLimit,
          ),
        ),
      );
      expect(cursor.isClosed, isTrue);
      expect(cursor.current, isNull);
      expect(composer.snapshot, same(snapshot));
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'closing retires deferred output and no inline resource is silently dropped',
    () {
      final cursor = _cursor(_document('<font>a<br></font>'));
      cursor.advance(maxEvents: 3);
      expect(cursor.current, isNull);
      cursor.close();
      expect(() => cursor.advance(maxEvents: 1), throwsStateError);
      expect(cursor.takePendingIssues, throwsStateError);
      final resource = _cursor(_document('<span>a<img src="x">b</span>'));
      addTearDown(resource.close);
      final units = _drain(resource);
      expect(
        units.whereType<ForumBodyTextFlowImage>().single.event.node.path,
        '0/1',
      );
      expect(
        units.whereType<ForumBodyTextFlowParagraph>().map(
          (unit) => unit.content.projection.text,
        ),
        ['a', 'b'],
      );
      expect(resource.isComplete, isTrue);
    },
  );
}
