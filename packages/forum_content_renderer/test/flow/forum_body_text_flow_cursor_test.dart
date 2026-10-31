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
}) => ForumBodyTextFlowCursor(
  document: document,
  reader: _reader,
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
    expect(step.eventsRead > 0 || step.hasOutput, isTrue);
    if (step.hasOutput) units.add(cursor.current!);
  }
  return units;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
        while (!composer.needsParagraph && composer.snapshot.isEmpty) {
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
      expect(
        () => _drain(resource),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
      expect(resource.isClosed, isTrue);
    },
  );
}
