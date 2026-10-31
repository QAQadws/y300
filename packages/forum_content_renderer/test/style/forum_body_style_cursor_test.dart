import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyReaderStyle reader() => ForumBodyReaderStyle(
  textStyle: const TextStyle(fontSize: 20, height: 1.6),
  fontRevision: 'loaded',
  linkColor: const Color(0xff0000ff),
  policy: ForumBodyStylePolicy({
    ForumBodyStyleProperty.fontSize: ForumBodyStyleScope.forceBody,
    ForumBodyStyleProperty.wordSpacing: ForumBodyStyleScope.forceBody,
  }),
);

ForumBodyDocument document(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'style-cursor',
  conversionIdentity: 'none',
);

void main() {
  test(
    'cursor resolves only the consumed prefix and drains immutable issues',
    () {
      final input = document(
        '<p>first</p><p style="word-spacing:20%">second</p>',
      );
      final cursor = const ForumBodyStyleResolver().open(input, reader());
      expect(cursor.resolvedNodeCount, 0);
      expect(cursor.currentNode, isNull);
      expect(cursor.moveNext(), isTrue);
      expect(cursor.currentNode!.path, '0');
      final first = cursor.currentStyle!;
      expect(cursor.takePendingIssues(), isEmpty);
      expect(cursor.moveNext(), isTrue);
      expect(cursor.currentNode!.path, '0/0');
      expect(identical(first, cursor.currentStyle), isTrue);
      expect(cursor.takePendingIssues(), isEmpty);
      expect(cursor.moveNext(), isTrue);
      expect(cursor.currentNode!.path, '1');
      final issues = cursor.takePendingIssues();
      expect(issues, hasLength(1));
      expect(issues.single.property, 'word-spacing');
      expect(cursor.takePendingIssues(), isEmpty);
      expect(() => issues.clear(), throwsUnsupportedError);
      cursor.close();
      expect(issues.single.path, '1');
      expect(first.textStyle.fontSize, 20);
      expect(cursor.isComplete, isFalse);
      expect(cursor.isClosed, isTrue);
      expect(cursor.currentNode, isNull);
      expect(cursor.currentStyle, isNull);
      expect(() => cursor.moveNext(), throwsStateError);
      expect(() => cursor.takePendingIssues(), throwsStateError);
      cursor.close();
    },
  );

  test(
    'streamed traversal preserves author/effective ancestry and eager results',
    () {
      final input = document(
        '<div style="font-size:30px;text-align:center">'
        '<p>body</p><h2><span>heading</span></h2><blockquote>quote</blockquote></div>',
      );
      final options = reader();
      final eager = const ForumBodyStyleResolver().resolve(input, options);
      final cursor = const ForumBodyStyleResolver().open(input, options);
      try {
        final paths = <String>[];
        while (cursor.moveNext()) {
          final path = cursor.currentNode!.path;
          paths.add(path);
          expect(cursor.currentStyle!.textStyle, eager.byPath[path]!.textStyle);
          expect(cursor.currentStyle!.textAlign, eager.byPath[path]!.textAlign);
        }
        expect(paths, input.descendants.map((node) => node.path));
        expect(cursor.resolvedNodeCount, input.descendants.length);
        expect(cursor.isComplete, isTrue);
        expect(cursor.moveNext(), isFalse);
        expect(cursor.currentNode, isNull);
        expect(cursor.takePendingIssues(), isEmpty);
      } finally {
        cursor.close();
      }
    },
  );

  test('neutral policies retain unique declaration diagnostics', () {
    final input = document(
      '<p style="width:calc(50%);width:calc(50%)">body</p>',
    );
    final options = ForumBodyReaderStyle(
      textStyle: const TextStyle(fontSize: 20),
      fontRevision: 'system',
      linkColor: const Color(0xff0000ff),
    );
    final cursor = const ForumBodyStyleResolver().open(input, options);
    try {
      expect(cursor.moveNext(), isTrue);
      expect(cursor.takePendingIssues(), hasLength(1));
    } finally {
      cursor.close();
    }
  });
}
