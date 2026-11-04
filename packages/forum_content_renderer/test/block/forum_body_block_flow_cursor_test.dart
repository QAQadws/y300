import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontSize: 10, height: 1, fontFamily: 'Ahem'),
  fontRevision: 'ahem',
  linkColor: const Color(0xff0000ff),
);

ForumBodyDocument _document(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'block-flow',
  conversionIdentity: 'none',
);

ForumBodyBlockFlowCursor _cursor(String html) => ForumBodyBlockFlowCursor(
  document: _document(html),
  reader: _reader,
  width: 200,
  edgeMargins: ForumBodyBlockEdgeMargins.preserve,
);

List<ForumBodyBlockFlowUnit> _drain(
  ForumBodyBlockFlowCursor cursor, {
  int budget = 1,
}) {
  final units = <ForumBodyBlockFlowUnit>[];
  var calls = 0;
  while (!cursor.isComplete) {
    if (++calls > 100000) fail('Block flow did not complete');
    final step = cursor.advance(maxEvents: budget);
    expect(step.eventsRead, lessThanOrEqualTo(budget));
    expect(step.eventsRead > 0 || step.hasOutput, isTrue);
    if (step.hasOutput) units.add(cursor.current!);
  }
  expect(units.last, isA<ForumBodyBlockFlowBoundary>());
  expect(
    (units.last as ForumBodyBlockFlowBoundary).boundary.kind,
    ForumBodyTextFlowBoundaryKind.endDocument,
  );
  return units;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (html, spaces) in [
    (
      '<p style="margin:10px 0 20px">a</p><p style="margin:30px 0 40px">b</p>',
      [10.0, 30.0, 40.0],
    ),
    (
      '<div style="margin:5px 0 7px"><p style="margin:10px 0 20px">a</p></div>',
      [10.0, 20.0],
    ),
    (
      '<div style="margin:5px 0 7px"><p style="margin:10px 0 20px"></p></div><p style="margin:15px 0 30px">b</p>',
      [20.0, 30.0],
    ),
    (
      '<p style="margin:0 0 20px">a</p><p style="margin:-8px 0 -30px">b</p><p style="margin:-5px 0 0">c</p>',
      [12.0, -30.0],
    ),
    (
      '<div style="margin:-5px 0 -7px"><p style="margin:-10px 0 -20px">a</p></div>',
      [-10.0, -20.0],
    ),
    (
      '<div style="margin:5px 0 7px"><p style="margin:-10px 0 -20px">a</p></div>',
      [-5.0, -13.0],
    ),
  ]) {
    test('adjoining signed margin groups: $html', () {
      final cursor = _cursor(html);
      addTearDown(cursor.close);
      final units = _drain(cursor);
      final gaps = units.whereType<ForumBodyBlockFlowSpace>().toList();
      expect(gaps.map((gap) => gap.extent), spaces);
      expect(
        gaps.every(
          (gap) =>
              gap.kind == ForumBodyBlockSpaceKind.collapsedMargin &&
              gap.path == null,
        ),
        isTrue,
      );
      expect(units.every((unit) => unit.identity == cursor.identity), isTrue);
    });
  }

  test(
    'body edge trimming preserves internal margins and every padding barrier',
    () {
      for (final (html, expected) in [
        (
          '<p style="margin:10px 0 20px">a</p><p style="margin:30px 0 40px">b</p>',
          [30.0],
        ),
        (
          '<div style="margin:5px;padding:2px"><p style="margin:10px">a</p></div>',
          [2.0, 10.0, 10.0, 2.0],
        ),
        (
          '<div style="margin:5px"><p style="margin:10px"></p></div>',
          <double>[],
        ),
      ]) {
        final cursor = ForumBodyBlockFlowCursor(
          document: _document(html),
          reader: _reader,
          width: 200,
        );
        try {
          final units = _drain(cursor);
          expect(
            units.whereType<ForumBodyBlockFlowSpace>().map(
              (unit) => unit.extent,
            ),
            expected,
          );
        } finally {
          cursor.close();
        }
      }
    },
  );

  test('padding separates collapsed groups and retains its owning block', () {
    final cursor = _cursor(
      '<div style="margin:5px;padding:2px"><p style="margin:10px">a</p></div>',
    );
    addTearDown(cursor.close);
    final units = _drain(cursor);
    final sequence = [
      for (final unit in units)
        switch (unit) {
          ForumBodyBlockFlowSpace() =>
            '${unit.kind.name}:${unit.extent}:${unit.path}',
          ForumBodyBlockFlowParagraph() =>
            'text:${unit.paragraph.content.projection.text}',
          ForumBodyBlockFlowInline() => 'inline:${unit.paragraph.index}',
          ForumBodyBlockFlowRule() => 'rule:${unit.path}',
          ForumBodyBlockFlowListItemStart() => 'list:${unit.marker.itemPath}',
          ForumBodyBlockFlowBoundary() =>
            '${unit.boundary.kind.name}:${unit.boundary.event?.node.path}',
        },
    ];
    expect(sequence, [
      'openBlock:0',
      'collapsedMargin:5.0:null',
      'paddingTop:2.0:0',
      'openBlock:0/0',
      'collapsedMargin:10.0:null',
      'text:a',
      'closeBlock:0/0',
      'collapsedMargin:10.0:null',
      'paddingBottom:2.0:0',
      'closeBlock:0',
      'collapsedMargin:5.0:null',
      'endDocument:null',
    ]);
  });

  test(
    'real text separates groups; BR partitions do not add paragraph margins',
    () {
      final cursor = _cursor(
        '<div style="margin:3px">a<p style="margin:10px">b<br>c<br></p>d</div>',
      );
      addTearDown(cursor.close);
      final units = _drain(cursor);
      expect(
        units.whereType<ForumBodyBlockFlowSpace>().map((unit) => unit.extent),
        [3.0, 10.0, 10.0, 3.0],
      );
      expect(
        units.whereType<ForumBodyBlockFlowParagraph>().map(
          (unit) => unit.paragraph.content.projection.text,
        ),
        ['a', 'b\n', 'c', 'd'],
      );
    },
  );

  test('nested boxes use actual content width and containing direction', () {
    final cursor = _cursor(
      '<div style="padding:10px"><div dir="rtl" style="width:80px;margin:0 10px">אבג</div></div>',
    );
    addTearDown(cursor.close);
    final units = _drain(cursor);
    final paragraph = units.whereType<ForumBodyBlockFlowParagraph>().single;
    expect(paragraph.contentLeft, 20);
    expect(paragraph.contentWidth, 80);
    expect(paragraph.paragraph.content.style.textDirection, TextDirection.rtl);
    final inner = units.whereType<ForumBodyBlockFlowBoundary>().firstWhere(
      (unit) => unit.boundary.event?.node.path == '0/0',
    );
    expect(inner.box!.containingWidth, 180);
    expect(inner.box!.margin.right, 90);
    expect(inner.contentLeft, 20);
  });

  test(
    'zero-width nested blocks stay zero and do not invent a native width',
    () {
      final cursor = _cursor(
        '<div style="width:0"><div style="padding:0">x</div></div>',
      );
      addTearDown(cursor.close);
      final paragraph = _drain(
        cursor,
      ).whereType<ForumBodyBlockFlowParagraph>().single;
      expect(paragraph.contentWidth, 0);
      expect(
        () => ForumBodyParagraphLayout.create(
          content: paragraph.paragraph.content,
          width: paragraph.contentWidth,
        ),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
    },
  );

  test('a long chapter first paragraph does not resolve later block styles', () {
    final cursor = _cursor(
      '<div style="padding:5px"><font>${List.filled(3000, '正文<br>').join()}</font></div>',
    );
    addTearDown(cursor.close);
    ForumBodyBlockFlowParagraph? first;
    while (first == null) {
      cursor.advance(maxEvents: 1);
      if (cursor.current case final ForumBodyBlockFlowParagraph unit) {
        first = unit;
      }
    }
    expect(first.paragraph.content.projection.text, '正文\n');
    expect(first.contentLeft, 5);
    expect(first.contentWidth, 190);
    expect(cursor.resolvedNodeCount, lessThanOrEqualTo(8));
    expect(cursor.isComplete, isFalse);
  });

  test('event budgets preserve identical geometry and control order', () {
    const html =
        '<div style="margin:5px;padding:2px">a<p style="margin:-3px 0 10px">b<br>c<br></p><div></div>d</div>';
    List<String> signature(int budget) {
      final cursor = _cursor(html);
      try {
        return [
          for (final unit in _drain(cursor, budget: budget))
            switch (unit) {
              ForumBodyBlockFlowSpace() =>
                '${unit.kind}:${unit.extent}:${unit.path}',
              ForumBodyBlockFlowParagraph() =>
                '${unit.paragraph.index}:${unit.paragraph.content.projection.text}:${unit.paragraph.window}:${unit.contentLeft}:${unit.contentWidth}',
              ForumBodyBlockFlowInline() => 'inline:${unit.paragraph.index}',
              ForumBodyBlockFlowRule() => 'rule:${unit.path}',
              ForumBodyBlockFlowListItemStart() =>
                'list:${unit.marker.itemPath}',
              ForumBodyBlockFlowBoundary() =>
                '${unit.boundary.kind}:${unit.boundary.event?.node.path}:${unit.contentLeft}',
            },
        ];
      } finally {
        cursor.close();
      }
    }

    expect(signature(1), signature(1000));
  });

  test('closing drops queued spacing and retires all remaining traversal', () {
    final cursor = _cursor('<div style="margin:5px;padding:2px">x</div>');
    cursor.advance(maxEvents: 1);
    expect(cursor.current, isA<ForumBodyBlockFlowBoundary>());
    cursor.close();
    expect(cursor.current, isNull);
    expect(() => cursor.advance(maxEvents: 1), throwsStateError);
    expect(cursor.takePendingIssues, throwsStateError);
  });

  for (final html in [
    '<img style="display:block" src="x">',
    '<pre>code</pre>',
    '<table><tr><td>x</td></tr></table>',
  ]) {
    test(
      'dedicated format nodes cannot disappear as ordinary empty blocks: $html',
      () {
        final cursor = _cursor(html);
        addTearDown(cursor.close);
        expect(
          () => _drain(cursor),
          throwsA(isA<ForumBodyBlockFlowException>()),
        );
        expect(cursor.isClosed, isTrue);
        expect(cursor.current, isNull);
      },
    );
  }

  test(
    'diagnostics are immutable drainable data from the one underlying style cursor',
    () {
      final cursor = _cursor('<div style="filter:blur(1px)">x</div>');
      addTearDown(cursor.close);
      cursor.advance(maxEvents: 1);
      final issues = cursor.takePendingIssues();
      expect(issues.single.property, 'filter');
      expect(() => issues.clear(), throwsUnsupportedError);
      _drain(cursor);
      expect(cursor.takePendingIssues(), isEmpty);
      expect(cursor.advance(maxEvents: 1), (
        eventsRead: 0,
        workDone: 0,
        hasOutput: false,
        isComplete: true,
      ));
    },
  );

  for (final css in [
    'height:30px',
    'min-height:10px',
    'position:absolute',
    'float:left',
    'overflow:hidden',
    'border-top:1px solid red',
    'display:flex',
    'writing-mode:vertical-rl',
  ]) {
    test(
      'ordinary margin collapse rejects an incompatible geometry contract: $css',
      () {
        final cursor = _cursor('<div style="$css">text</div>');
        addTearDown(cursor.close);
        expect(
          () => _drain(cursor),
          throwsA(
            isA<ForumBodyBlockFlowException>().having(
              (error) => error.failure,
              'failure',
              ForumBodyBlockFlowFailure.geometry,
            ),
          ),
        );
        expect(cursor.isClosed, isTrue);
      },
    );
  }

  test(
    'overridden non-normal declarations do not reject the effective normal box',
    () {
      final cursor = _cursor(
        '<div style="height:30px;height:auto;position:absolute;position:static!important;position:fixed;display:flex;display:block">text</div>',
      );
      addTearDown(cursor.close);
      expect(
        _drain(cursor).whereType<ForumBodyBlockFlowParagraph>(),
        hasLength(1),
      );
    },
  );
}
