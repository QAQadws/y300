import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontSize: 10, height: 1, fontFamily: 'Ahem'),
  fontRevision: 'ahem-list',
  linkColor: const Color(0xff0000ff),
);
ForumBodyDocument _document(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'list-flow',
  conversionIdentity: 'none',
);
List<ForumBodyBlockFlowUnit> _drain(String html, {int budget = 1}) {
  final cursor = ForumBodyBlockFlowCursor(
    document: _document(html),
    reader: _reader,
    width: 240,
  );
  try {
    final units = <ForumBodyBlockFlowUnit>[];
    var calls = 0;
    while (!cursor.isComplete) {
      if (++calls > 100000) fail('List flow did not complete');
      final step = cursor.advance(maxEvents: budget);
      expect(step.eventsRead, lessThanOrEqualTo(budget));
      expect(step.workDone, lessThanOrEqualTo(budget));
      expect(step.workDone > 0 || step.hasOutput, isTrue);
      if (step.hasOutput) units.add(cursor.current!);
      if (cursor.current case ForumBodyBlockFlowListItemStart item) {
        cursor.resolveListItemGutter(item, 0);
      }
    }
    return units;
  } finally {
    cursor.close();
  }
}

List<ForumBodyListItemMarker> _markers(List<ForumBodyBlockFlowUnit> units) => [
  for (final unit in units)
    ...switch (unit) {
      ForumBodyBlockFlowParagraph() => unit.listMarkers,
      ForumBodyBlockFlowInline() => unit.listMarkers,
      _ => const <ForumBodyListItemMarker>[],
    },
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Discuz counters survive tiny batches and carry through alphabetic labels',
    () {
      final html =
          '<ul type="A" class="litype_3">${List.generate(28, (i) => '<li>item$i</li>').join()}</ul>';
      final units = _drain(html);
      final markers = _markers(units);
      expect(markers.map((m) => m.ordinal), List.generate(28, (i) => i + 1));
      expect(markers.skip(25).map((m) => m.text), ['Z.', 'AA.', 'AB.']);
      expect(
        markers.every(
          (m) =>
              m.listPath == '0' && m.contentLeft == 40 && m.contentWidth == 200,
        ),
        isTrue,
      );
      final paragraphs = units
          .whereType<ForumBodyBlockFlowParagraph>()
          .toList();
      expect(
        paragraphs.map((p) => p.paragraph.content.projection.text),
        List.generate(28, (i) => 'item$i'),
      );
      expect(
        () => paragraphs.first.listMarkers.clear(),
        throwsUnsupportedError,
      );
      expect(
        _markers(
          _drain(html, budget: 1000),
        ).map((m) => (m.itemPath, m.ordinal, m.text)),
        markers.map((m) => (m.itemPath, m.ordinal, m.text)),
      );
    },
  );

  test(
    'nested counters, BR continuations and child paragraphs emit each marker once',
    () {
      const html =
          '<ol start="3"><li>A<br>B<p>C</p><ul type="A"><li>X</li><li>Y</li></ul><p>D</p></li><li value="10">E</li><li></li></ol>';
      final units = _drain(html);
      final paragraphs = units
          .whereType<ForumBodyBlockFlowParagraph>()
          .toList();
      expect(paragraphs.map((p) => p.paragraph.content.projection.text), [
        'A\n',
        'B',
        'C',
        'X',
        'Y',
        'D',
        'E',
        '',
      ]);
      expect(_markers(units).map((m) => m.text), [
        '3.',
        'A.',
        'B.',
        '10.',
        '11.',
      ]);
      expect(_markers(units).map((m) => m.contentLeft), [40, 80, 80, 40, 40]);
      expect(
        paragraphs
            .where((p) => p.listMarkers.isNotEmpty)
            .map((p) => p.paragraph.content.projection.text),
        ['A\n', 'X', 'Y', 'E', ''],
      );
    },
  );

  test(
    'single-level ruby consumes the first marker without flattening annotation',
    () {
      final units = _drain(
        '<ul type="1"><li><ruby>字<rt>じ</rt></ruby><p>tail</p></li><li>next</li></ul>',
      );
      final mixed = units.whereType<ForumBodyBlockFlowInline>().single;
      expect(mixed.listMarkers.single.text, '1.');
      final ordinary = units.whereType<ForumBodyBlockFlowParagraph>().toList();
      expect(ordinary.first.listMarkers, isEmpty);
      expect(ordinary.last.listMarkers.single.text, '2.');
    },
  );

  test(
    'empty items keep actual empty node provenance and a real native strut',
    () {
      const html =
          '<p>prefix</p><ol><li id="empty"></li><li><div></div></li><li>text</li></ol>';
      final document = _document(html);
      final actual = document.descendants
          .whereType<ForumBodyElement>()
          .singleWhere((e) => e.attributes['id'] == 'empty');
      final paragraphs = _drain(
        html,
      ).whereType<ForumBodyBlockFlowParagraph>().toList();
      final empty = paragraphs[1].paragraph.content;
      expect(empty.path, actual.path);
      expect(empty.projection.text, isEmpty);
      expect(empty.isSourceFree, isFalse);
      expect(
        empty.projection.sourceAtUtf16(0).sourceRune,
        actual.source.runeStart,
      );
      expect(paragraphs.map((p) => p.paragraph.content.projection.text), [
        'prefix',
        '',
        '',
        'text',
      ]);
      expect(paragraphs.skip(1).map((p) => p.listMarkers.single.text), [
        '1.',
        '2.',
        '3.',
      ]);
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      final lease = cache.acquire(content: empty, width: 200);
      try {
        expect(lease.layout.height, greaterThan(0));
        expect(lease.layout.selectionBoxes(0, 0), isEmpty);
      } finally {
        lease.release();
        cache.close();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'display none, visibility hidden and block overrides have distinct counting semantics',
    () {
      final markers = _markers(
        _drain(
          '<ol><li style="display:none">none</li><li style="visibility:hidden">hidden</li><li style="display:block">block</li><li>shown</li></ol>',
        ),
      );
      expect(markers.map((m) => m.ordinal), [1, 2]);
      expect(markers.map((m) => m.style.visibilityHidden), [true, false]);
    },
  );

  test(
    'computed list-item display and separate implicit owners use their actual nodes',
    () {
      final units = _drain(
        '<div style="list-style-type:decimal"><span style="display:list-item">one</span><li>two</li></div><div><li>three</li></div>',
      );
      expect(_markers(units).map((m) => (m.ordinal, m.text)), [
        (1, '1.'),
        (2, '2.'),
        (1, '•'),
      ]);
    },
  );

  test(
    'physical gutter follows effective direction and explicit author padding',
    () {
      for (final (attributes, left, width) in [
        ('', 40.0, 200.0),
        ('dir="rtl"', 0.0, 200.0),
        ('style="padding:0 10px 0 5px"', 5.0, 225.0),
      ]) {
        final unit = _drain(
          '<ul $attributes><li>text</li></ul>',
        ).whereType<ForumBodyBlockFlowParagraph>().single;
        expect((unit.contentLeft, unit.contentWidth), (left, width));
        expect(
          (
            unit.listMarkers.single.contentLeft,
            unit.listMarkers.single.contentWidth,
          ),
          (left, width),
        );
      }
      final nested = _drain(
        '<ul dir="rtl"><li><ul dir="ltr"><li>text</li></ul></li></ul>',
      ).whereType<ForumBodyBlockFlowParagraph>().single;
      expect((nested.contentLeft, nested.contentWidth), (40.0, 160.0));
      expect(nested.listMarkers.map((m) => m.style.textDirection), [
        TextDirection.rtl,
        TextDirection.ltr,
      ]);
      expect(nested.listMarkers.map((m) => m.contentLeft), [0, 40]);
    },
  );

  test(
    'item type hints override only the item while counter state stays structural',
    () {
      final markers = _markers(
        _drain(
          '<ol start="27"><li type="A">alpha</li><li>decimal</li><li style="list-style-type:none">none</li><li>last</li></ol>',
        ),
      );
      expect(markers.map((m) => (m.ordinal, m.text)), [
        (27, 'AA.'),
        (28, '28.'),
        (29, null),
        (30, '30.'),
      ]);
    },
  );

  test(
    'explicit start/value parsing, descending counters and overflow cannot wrap',
    () {
      for (final (html, expected) in [
        (
          '<ol start=" +03suffix"><li>a</li><li value="0x10">b</li><li value="bad">c</li></ol>',
          [3, 0, 1],
        ),
        (
          '<ol start="7" reversed><li>a</li><li value="-2">b</li><li>c</li></ol>',
          [7, -2, -3],
        ),
        (
          '<ol start="9223372036854775807"><li>a</li></ol>',
          [9223372036854775807],
        ),
        (
          '<ol start="9223372036854775807"><li>a</li><li value="0">b</li><li>c</li></ol>',
          [9223372036854775807, 0, 1],
        ),
      ]) {
        expect(
          _markers(_drain(html)).map((m) => m.ordinal),
          expected,
          reason: html,
        );
      }
      for (final html in [
        '<ol start="9223372036854775807"><li>a</li><li>b</li></ol>',
        '<ol start="999999999999999999999"><li>a</li></ol>',
        '<ol reversed><li>a</li></ol>',
      ]) {
        expect(() => _drain(html), throwsA(isA<ForumBodyBlockFlowException>()));
      }
    },
  );

  test('close retires pending empty-item proof and unread counters', () {
    final cursor = ForumBodyBlockFlowCursor(
      document: _document('<ol><li></li><li>later</li></ol>'),
      reader: _reader,
      width: 240,
    );
    cursor.advance(maxEvents: 1);
    cursor.advance(maxEvents: 1);
    cursor.close();
    expect(cursor.current, isNull);
    expect(() => cursor.advance(maxEvents: 1), throwsStateError);
  });
}
