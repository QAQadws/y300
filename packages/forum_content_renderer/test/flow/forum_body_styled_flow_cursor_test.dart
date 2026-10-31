import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import '../conformance/forum_body_corpus.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontSize: 20, fontFamily: 'Reader'),
  fontRevision: 'synthetic-font',
  linkColor: const Color(0xff0000ff),
);

ForumBodyDocument _parse(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'synthetic-flow',
  conversionIdentity: 'none',
);

void main() {
  for (final sample in forumBodyCases) {
    test('bounded traversal preserves every IR node: ${sample.id}', () {
      final document = _parse(sample.html);
      final eager = const ForumBodyStyleResolver().resolve(document, _reader);
      final cursor = ForumBodyStyledFlowCursor(
        document: document,
        reader: _reader,
      );
      addTearDown(cursor.close);
      final opened = <ForumBodyStyledFlowEvent>[];
      final visited = <String>[];
      final text = StringBuffer();
      while (!cursor.isComplete) {
        final batch = cursor.nextBatch(maxEvents: 3);
        expect(batch.length, lessThanOrEqualTo(3));
        expect(() => batch.clear(), throwsUnsupportedError);
        for (final event in batch) {
          final expected = eager.byPath[event.node.path]!;
          expect(event.style.textStyle, expected.textStyle);
          expect(event.style.role, expected.role);
          expect(event.style.hidden, expected.hidden);
          expect(event.style.linkTarget, expected.linkTarget);
          if (event.phase == ForumBodyFlowPhase.close) {
            final start = opened.removeLast();
            expect(event.node, same(start.node));
            expect(event.style, same(start.style));
            expect(event.depth, opened.length);
          } else {
            expect(event.depth, opened.length);
            visited.add(event.node.path);
            if (event.phase == ForumBodyFlowPhase.open) {
              expect(event.node, isA<ForumBodyElement>());
              opened.add(event);
              if ((event.node as ForumBodyElement).kind ==
                  ForumBodyElementKind.hardBreak) {
                text.write('\n');
              }
            } else {
              text.write((event.node as ForumBodyText).text);
            }
          }
        }
      }
      expect(opened, isEmpty);
      expect(visited, document.descendants.map((node) => node.path));
      expect(text.toString(), document.sourceText);
      expect(cursor.resolvedNodeCount, document.descendants.length);
      expect(cursor.identity, document.identity);
      expect(cursor.fontRevision, _reader.fontRevision);
      expect(cursor.styleRevision, ForumBodyStyleResolver.revision);
      expect(cursor.nextBatch(maxEvents: 1), isEmpty);
      expect(cursor.current, isNull);
    });
  }

  test('a first block does not resolve the rest of a long chapter', () {
    final document = _parse(
      '<div><p>first</p>${List.filled(10000, '<p>later</p>').join()}</div>',
    );
    final cursor = ForumBodyStyledFlowCursor(
      document: document,
      reader: _reader,
    );
    addTearDown(cursor.close);
    final prefix = cursor.nextBatch(maxEvents: 4);
    expect(prefix.map((event) => (event.phase, event.node.path)), [
      (ForumBodyFlowPhase.open, '0'),
      (ForumBodyFlowPhase.open, '0/0'),
      (ForumBodyFlowPhase.text, '0/0/0'),
      (ForumBodyFlowPhase.close, '0/0'),
    ]);
    expect(
      cursor.resolvedNodeCount,
      4,
    ); // Exactly one following block lookahead.
    expect(cursor.isComplete, isFalse);
    final next = cursor.nextBatch(maxEvents: 1).single;
    expect(next.node.path, '0/1');
    expect(cursor.resolvedNodeCount, 4);
    expect(prefix.last.node.path, '0/0');
  });

  test('lookahead diagnostics are withheld until that node is delivered', () {
    final cursor = ForumBodyStyledFlowCursor(
      document: _parse('<p>first</p><p style="float:left">later</p>'),
      reader: _reader,
    );
    addTearDown(cursor.close);
    expect(cursor.nextBatch(maxEvents: 3).last.phase, ForumBodyFlowPhase.close);
    expect(cursor.resolvedNodeCount, 3);
    expect(cursor.takePendingIssues(), isEmpty);
    expect(cursor.nextBatch(maxEvents: 1).single.node.path, '1');
    final issues = cursor.takePendingIssues();
    expect(issues.single.property, 'float');
    expect(issues.single.path, '1');
    expect(() => issues.clear(), throwsUnsupportedError);
    expect(cursor.takePendingIssues(), isEmpty);
  });

  test('close retires lookahead, ancestry and pending diagnostics', () {
    final cursor = ForumBodyStyledFlowCursor(
      document: _parse('<div><p style="float:left">text</p></div>'),
      reader: _reader,
    );
    final batch = cursor.nextBatch(maxEvents: 2);
    cursor.close();
    cursor.close();
    expect(cursor.current, isNull);
    expect(cursor.isClosed, isTrue);
    expect(cursor.isComplete, isFalse);
    expect(batch.last.node.path, '0/0');
    expect(cursor.moveNext, throwsStateError);
    expect(() => cursor.nextBatch(maxEvents: 1), throwsStateError);
    expect(cursor.takePendingIssues, throwsStateError);
  });

  test('invalid batches do not advance and empty documents finish', () {
    final cursor = ForumBodyStyledFlowCursor(
      document: _parse(''),
      reader: _reader,
    );
    addTearDown(cursor.close);
    expect(() => cursor.nextBatch(maxEvents: 0), throwsArgumentError);
    expect(() => cursor.nextBatch(maxEvents: -1), throwsArgumentError);
    expect(cursor.resolvedNodeCount, 0);
    expect(cursor.nextBatch(maxEvents: 1), isEmpty);
    expect(cursor.isComplete, isTrue);
  });
}
