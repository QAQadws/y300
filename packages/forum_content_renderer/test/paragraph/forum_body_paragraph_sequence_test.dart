import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontSize: 20),
  fontRevision: 'synthetic-font',
  linkColor: const Color(0xff0000ff),
);
ForumBodyDocument _document(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'sequence',
  conversionIdentity: 'none',
);
ForumBodyStyledFlowCursor _flow(ForumBodyDocument document) =>
    ForumBodyStyledFlowCursor(document: document, reader: _reader);

void main() {
  test(
    'explicit inline fragments preserve root style, source and collapsible edges',
    () {
      final flow = _flow(
        _document('<ruby>A<rt style="font-size:10px"> x <b>y</b> </rt></ruby>'),
      );
      addTearDown(flow.close);
      while (flow.moveNext()) {
        if (flow.current!.node is ForumBodyElement &&
            (flow.current!.node as ForumBodyElement).kind ==
                ForumBodyElementKind.rubyText) {
          break;
        }
      }
      final root = flow.current!;
      const builder = ForumBodyParagraphContentBuilder();
      final sequence = builder.openInlineSequence(flow, root: root);
      while (flow.moveNext()) {
        final event = flow.current!;
        if (event.node.path == root.node.path &&
            event.phase == ForumBodyFlowPhase.close) {
          break;
        }
        if (event.phase != ForumBodyFlowPhase.close) sequence.appendCurrent();
      }
      final content = sequence.finish();
      expect(content.projection.text, ' x y ');
      expect(content.style.textStyle.fontSize, 10);
      expect(
        content.layoutMode,
        ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
      expect(content.projection.sourceAtUtf16(0).sourceRune, 1);
      expect(content.runs.any((run) => run.style.strong), isTrue);
      expect(flow.isClosed, isFalse);
      expect(
        () => builder.openInlineSequence(flow, root: root),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
    },
  );

  test(
    'inline fragment roots reject foreign ownership, resources and unhandled box geometry',
    () {
      const builder = ForumBodyParagraphContentBuilder();
      final first = _flow(_document('<span>x</span>'))..moveNext();
      final other = _flow(_document('<span>x</span>'))..moveNext();
      addTearDown(first.close);
      addTearDown(other.close);
      expect(
        () => builder.openInlineSequence(first, root: other.current!),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
      for (final html in [
        '<img src="x">',
        '<span style="padding:2px">x</span>',
        '<span style="display:block">x</span>',
      ]) {
        final flow = _flow(_document(html))..moveNext();
        addTearDown(flow.close);
        expect(
          () => builder.openInlineSequence(flow, root: flow.current!),
          throwsA(
            isA<ForumBodyParagraphInputException>().having(
              (error) => error.failure,
              'failure',
              ForumBodyParagraphInputFailure.structure,
            ),
          ),
        );
      }
    },
  );

  test(
    'explicit fragment limits do not relax ordinary ruby structural admission',
    () {
      final document = _document('<ruby>A<rt>a</rt></ruby>');
      final flow = _flow(document)..moveNext();
      addTearDown(flow.close);
      const builder = ForumBodyParagraphContentBuilder();
      expect(
        () => builder.build(
          document: document,
          styles: const ForumBodyStyleResolver().resolve(document, _reader),
        ),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
      final sequence = builder.openInlineSequence(flow, root: flow.current!);
      flow.moveNext();
      sequence.appendCurrent();
      flow.moveNext(); // Actual RT must be handled by its format consumer.
      expect(
        sequence.appendCurrent,
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
      expect(sequence.isClosed, isTrue);
      final limited = _flow(_document('<span>long</span>'))..moveNext();
      addTearDown(limited.close);
      final value = const ForumBodyParagraphContentBuilder(
        maxInputCodeUnits: 2,
      ).openInlineSequence(limited, root: limited.current!);
      limited.moveNext();
      expect(
        value.appendCurrent,
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyParagraphInputFailure.inputLimit,
          ),
        ),
      );
    },
  );

  test('raw sequence merge normalizes cross-run CRLF only once', () {
    final document = _document(
      '<p style="white-space:pre-wrap">a&#13;<b>&#10;b</b></p>',
    );
    final flow = _flow(document);
    addTearDown(flow.close);
    flow.moveNext();
    final block = flow.current!;
    const builder = ForumBodyParagraphContentBuilder();
    final head = builder.openSequence(flow, block: block);
    final tail = builder.openSequence(flow, block: block);
    flow.moveNext();
    final deferred = flow.current!;
    while (flow.moveNext()) {
      if (flow.current!.phase != ForumBodyFlowPhase.close) tail.appendCurrent();
    }
    head.appendEvent(deferred);
    expect(head.hasDisplayText, isTrue);
    head.appendSequence(tail);
    expect(tail.isClosed, isTrue);
    expect(tail.finish, throwsStateError);
    final content = head.finish();
    final eager = builder.build(
      document: document,
      styles: const ForumBodyStyleResolver().resolve(document, _reader),
      path: '0',
    );
    expect(content.projection.text, 'a\nb');
    expect(content.projection.hasSameSourceMapping(eager.projection), isTrue);
    expect(content.runs.map((run) => run.style.strong), [false, true]);
  });

  test('sequence merge rejects overlap and leaves the source caller-owned', () {
    final flow = _flow(_document('<p>a<b>b</b></p>'));
    addTearDown(flow.close);
    flow.moveNext();
    final block = flow.current!;
    const builder = ForumBodyParagraphContentBuilder();
    final head = builder.openSequence(flow, block: block);
    final tail = builder.openSequence(flow, block: block);
    flow.moveNext();
    head.appendCurrent();
    while (flow.moveNext()) {
      if (flow.current!.phase != ForumBodyFlowPhase.close) tail.appendCurrent();
    }
    expect(
      () => tail.appendSequence(head),
      throwsA(isA<ForumBodyParagraphInputException>()),
    );
    expect(tail.isClosed, isTrue);
    expect(head.isClosed, isFalse);
    expect(head.finish().projection.text, 'a');
  });

  for (final (maxInput, maxRuns, failure) in [
    (3, 8, ForumBodyParagraphInputFailure.inputLimit),
    (10, 1, ForumBodyParagraphInputFailure.runLimit),
  ]) {
    test('merged raw inputs enforce the receiver $failure budget', () {
      final flow = _flow(_document('<p>ab<b>cd</b></p>'));
      addTearDown(flow.close);
      flow.moveNext();
      final block = flow.current!;
      final builder = ForumBodyParagraphContentBuilder(
        maxInputCodeUnits: maxInput,
        maxRuns: maxRuns,
      );
      final head = builder.openSequence(flow, block: block);
      final tail = builder.openSequence(flow, block: block);
      flow.moveNext();
      head.appendCurrent();
      while (flow.moveNext()) {
        if (flow.current!.phase != ForumBodyFlowPhase.close) {
          tail.appendCurrent();
        }
      }
      expect(
        () => head.appendSequence(tail),
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (error) => error.failure,
            'failure',
            failure,
          ),
        ),
      );
      expect(head.isClosed, isTrue);
      expect(tail.isClosed, isFalse);
      expect(tail.finish().projection.text, 'cd');
    });
  }

  test('deferred events cannot cross a structural flow owner', () {
    final document = _document('<p>text</p>');
    final flow = _flow(document);
    final other = _flow(document);
    addTearDown(flow.close);
    addTearDown(other.close);
    flow.moveNext();
    final sequence = const ForumBodyParagraphContentBuilder().openSequence(
      flow,
      block: flow.current!,
    );
    other.moveNext();
    other.moveNext();
    expect(
      () => sequence.appendEvent(other.current!),
      throwsA(isA<ForumBodyParagraphInputException>()),
    );
    expect(sequence.isClosed, isTrue);
    expect(flow.isClosed, isFalse);
    expect(other.isClosed, isFalse);
  });

  test(
    'sequences split at real BR while keeping cross-node style and source inheritance',
    () {
      final document = _document(
        '<div style="font-size:24px"><font size="5">甲 <b>乙</b><br>'
        '丙<a href="target">e<i>́</i>丁</a></font></div>',
      );
      final flow = _flow(document);
      addTearDown(flow.close);
      flow.moveNext();
      final block = flow.current!;
      var sequence = const ForumBodyParagraphContentBuilder().openSequence(
        flow,
        block: block,
      );
      final chunks = <ForumBodyParagraphContent>[];
      while (flow.moveNext()) {
        final event = flow.current!;
        if (event.phase == ForumBodyFlowPhase.close) {
          if (identical(event.node, block.node)) break;
          continue;
        }
        sequence.appendCurrent();
        if (event.node is ForumBodyElement &&
            (event.node as ForumBodyElement).kind ==
                ForumBodyElementKind.hardBreak) {
          chunks.add(sequence.finish());
          sequence = const ForumBodyParagraphContentBuilder().openSequence(
            flow,
            block: block,
          );
        }
      }
      chunks.add(sequence.finish());
      final full = const ForumBodyParagraphContentBuilder().build(
        document: document,
        styles: const ForumBodyStyleResolver().resolve(document, _reader),
        path: '0',
      );
      expect(chunks.map((chunk) => chunk.projection.text), ['甲 乙\n', '丙é丁']);
      expect(chunks.first.runs.any((run) => run.style.strong), isTrue);
      expect(
        chunks.last.runs.any((run) => run.style.linkTarget == 'target'),
        isTrue,
      );
      expect(
        chunks.last.runs.every(
          (run) =>
              run.style.textStyle.fontSize ==
              chunks.first.runs.first.style.textStyle.fontSize,
        ),
        isTrue,
      );
      var displayBase = 0;
      for (final chunk in chunks) {
        expect(chunk.identity, document.identity);
        expect(chunk.path, '0');
        for (var offset = 0; offset <= chunk.projection.text.length; offset++) {
          for (final affinity in HtmlProjectionAffinity.values) {
            final local = chunk.projection.sourceAtUtf16(
              offset,
              affinity: affinity,
            );
            final whole = full.projection.sourceAtUtf16(
              displayBase + offset,
              affinity: affinity,
            );
            expect(
              (
                local.sourceRune,
                local.displayUtf16 + displayBase,
                local.isExact,
              ),
              (whole.sourceRune, whole.displayUtf16, whole.isExact),
            );
          }
        }
        displayBase += chunk.projection.text.length;
      }
      expect(displayBase, full.projection.text.length);
      expect(flow.isClosed, isFalse);
    },
  );

  test(
    'empty paragraph source base is retained in eager and sequence ports',
    () {
      final document = _document('<p>abc</p><p></p>');
      final eager = const ForumBodyParagraphContentBuilder().build(
        document: document,
        styles: const ForumBodyStyleResolver().resolve(document, _reader),
        path: '1',
      );
      expect(eager.projection.sourceAtUtf16(0).sourceRune, 3);
      final flow = _flow(document);
      addTearDown(flow.close);
      while (flow.moveNext()) {
        if (flow.current!.phase == ForumBodyFlowPhase.open &&
            flow.current!.node.path == '1') {
          break;
        }
      }
      final sequence = const ForumBodyParagraphContentBuilder(
        maxInputCodeUnits: 0,
        maxRuns: 0,
      ).openSequence(flow, block: flow.current!);
      expect(sequence.hasInput, isFalse);
      final empty = sequence.finish();
      expect(empty.projection.hasSameSourceMapping(eager.projection), isTrue);
      expect(empty.runs, isEmpty);
      expect(empty.projection.parts, isEmpty);
      expect(sequence.isClosed, isTrue);
      expect(sequence.finish, throwsStateError);
    },
  );

  test('same-document foreign or no-longer-open block events are rejected', () {
    final document = _document('<p>text</p>');
    final first = _flow(document);
    final second = _flow(document);
    addTearDown(first.close);
    addTearDown(second.close);
    first.moveNext();
    second.moveNext();
    final block = first.current!;
    expect(first.owns(block), isTrue);
    expect(second.owns(block), isFalse);
    expect(
      () => const ForumBodyParagraphContentBuilder().openSequence(
        second,
        block: block,
      ),
      throwsA(isA<ForumBodyParagraphInputException>()),
    );
    while (first.moveNext()) {}
    expect(first.isOpenElement(block), isFalse);
    expect(
      () => const ForumBodyParagraphContentBuilder().openSequence(
        first,
        block: block,
      ),
      throwsA(isA<ForumBodyParagraphInputException>()),
    );
  });

  test(
    'duplicate input, resources and limits fail without publishing a partial sequence',
    () {
      for (final (html, maxRuns, expected) in [
        ('<p>text</p>', 8, ForumBodyParagraphInputFailure.identity),
        ('<p><img src="x"></p>', 8, ForumBodyParagraphInputFailure.structure),
        ('<p>a<b>b</b></p>', 1, ForumBodyParagraphInputFailure.runLimit),
      ]) {
        final flow = _flow(_document(html));
        addTearDown(flow.close);
        flow.moveNext();
        final sequence = ForumBodyParagraphContentBuilder(
          maxRuns: maxRuns,
        ).openSequence(flow, block: flow.current!);
        void append() {
          while (flow.moveNext()) {
            if (flow.current!.phase == ForumBodyFlowPhase.close) continue;
            sequence.appendCurrent();
            if (expected == ForumBodyParagraphInputFailure.identity) {
              sequence.appendCurrent();
            }
          }
        }

        expect(
          append,
          throwsA(
            isA<ForumBodyParagraphInputException>().having(
              (error) => error.failure,
              'failure',
              expected,
            ),
          ),
        );
        expect(sequence.isClosed, isTrue);
        expect(sequence.finish, throwsStateError);
        expect(flow.isClosed, isFalse);
      }
    },
  );

  test('retiring the flow prevents late unsealed sequence publication', () {
    final flow = _flow(_document('<p>text</p>'));
    flow.moveNext();
    final sequence = const ForumBodyParagraphContentBuilder().openSequence(
      flow,
      block: flow.current!,
    );
    flow.moveNext();
    sequence.appendCurrent();
    expect(sequence.hasInput, isTrue);
    flow.close();
    expect(sequence.finish, throwsStateError);
    expect(sequence.isClosed, isTrue);
    expect(sequence.hasInput, isFalse);
  });
}
