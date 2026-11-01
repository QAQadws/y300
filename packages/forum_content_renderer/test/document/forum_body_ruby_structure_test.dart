import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontSize: 20, height: 1, fontFamily: 'Ahem'),
  fontRevision: 'explicit-ruby-structure',
  linkColor: const Color(0xff0000ff),
);

ForumBodyDocument _parse(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'explicit-ruby-structure',
  conversionIdentity: 'none',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'explicit base and annotation containers retain distinct IR and source',
    () {
      final document = _parse(
        '<ruby><rb>A</rb><rb>B</rb><rtc><rt>x</rt><rt>y</rt></rtc><rtc>word</rtc></ruby>',
      );
      final elements = document.descendants
          .whereType<ForumBodyElement>()
          .toList();
      expect(elements.map((node) => node.kind), [
        ForumBodyElementKind.ruby,
        ForumBodyElementKind.rubyBase,
        ForumBodyElementKind.rubyBase,
        ForumBodyElementKind.rubyAnnotationContainer,
        ForumBodyElementKind.rubyText,
        ForumBodyElementKind.rubyText,
        ForumBodyElementKind.rubyAnnotationContainer,
      ]);
      expect(document.sourceText, 'ABxyword');
      expect(
        elements.map((node) => (node.source.runeStart, node.source.runeEnd)),
        [(0, 8), (0, 1), (1, 2), (2, 4), (2, 3), (3, 4), (4, 8)],
      );
      expect(document.identity.parserRevision, ForumBodyParser.revision);
      for (final node in elements) {
        expect(document.nodeAtPath(node.path), same(node));
      }
    },
  );

  test(
    'structural containers stay inline without shrinking RT a second time',
    () {
      final flow = ForumBodyStyledFlowCursor(
        document: _parse('<ruby><rb>A</rb><rtc><rt>x</rt></rtc></ruby>'),
        reader: _reader,
      );
      try {
        final sizes = <String, double?>{};
        while (flow.moveNext()) {
          final event = flow.current!;
          if (event.phase != ForumBodyFlowPhase.open) continue;
          final node = event.node as ForumBodyElement;
          expect(event.style.display, ForumBodyDisplay.inline);
          sizes[node.tag] = event.style.textStyle.fontSize;
        }
        expect(sizes, {'ruby': 20, 'rb': 20, 'rtc': 10, 'rt': 10});
      } finally {
        flow.close();
      }
    },
  );

  for (final html in [
    '<ruby><rb>A<ruby>B<rt>b</rt></ruby></rb><rt>x</rt></ruby>',
    '<ruby><rb></rb><rt></rt></ruby>',
    '<ruby style="ruby-position:inter-character">A<rt>x</rt></ruby>',
    '<ruby><rb>A</rb><rb>B</rb><rtc style="white-space:pre"><rt>x</rt> <rt>y</rt></rtc></ruby>',
  ]) {
    test('leaf planning cannot flatten explicit structure: $html', () {
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      final session = ForumBodyTextPageSession(
        document: _parse(html),
        reader: _reader,
        cache: cache,
        limits: const ForumBodyTextPageSessionLimits(
          maxPages: 10,
          maxFragments: 20,
          maxParagraphs: 10,
          maxTextCodeUnits: 1000,
          maxRuns: 100,
          maxIssuedLeases: 20,
        ),
        layoutId: 'explicit-ruby-structure',
        width: 200,
        height: 100,
      );
      try {
        expect(() {
          for (var i = 0; !session.isComplete && i < 100; i++) {
            session.advance(maxEvents: 1, maxLines: 1);
          }
        }, throwsA(isA<ForumBodyParagraphInputException>()));
        expect(session.snapshot, isEmpty);
        expect(cache.layoutBuildCount, 0);
        expect(cache.activeLeases, 0);
      } finally {
        session.close();
        cache.close();
      }
    });
  }
}
