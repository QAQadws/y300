import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontSize: 20, height: 1.5),
  fontRevision: 'synthetic-font',
  linkColor: const Color(0xff0000ff),
);

ForumBodyDocument _parse(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'synthetic-accumulator',
  conversionIdentity: 'none',
);

ForumBodyStyledFlowCursor _flow(ForumBodyDocument document) =>
    ForumBodyStyledFlowCursor(document: document, reader: _reader);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bounded paragraph consumption matches eager text, styles and source mapping',
    () {
      final document = _parse(
        '<div style="font-size:24px"><p> 甲 <b>乙</b><br>'
        '<a href="target">e<i>́</i>👩🏽‍💻</a>'
        '<span hidden>secret</span><span style="visibility:hidden">丙</span></p>'
        '${List.filled(5000, '<p>later</p>').join()}</div>',
      );
      final flow = _flow(document);
      addTearDown(flow.close);
      expect(flow.nextBatch(maxEvents: 2).last.node.path, '0/0');
      final accumulator = const ForumBodyParagraphContentBuilder().openCurrent(
        flow,
      );
      addTearDown(accumulator.close);
      expect(accumulator.finish, throwsStateError);
      var consumed = 0;
      while (!accumulator.isComplete) {
        consumed += accumulator.advance(maxEvents: 1);
      }
      expect(accumulator.advance(maxEvents: 1), 0);
      expect(consumed, greaterThan(10));
      expect(flow.current!.phase, ForumBodyFlowPhase.close);
      expect(flow.current!.node.path, '0/0');
      expect(flow.resolvedNodeCount, lessThan(30));
      final actual = accumulator.finish(issues: flow.takePendingIssues());
      expect(accumulator.isClosed, isTrue);
      expect(flow.isClosed, isFalse);
      final styles = const ForumBodyStyleResolver().resolve(document, _reader);
      final expected = const ForumBodyParagraphContentBuilder().build(
        document: document,
        styles: styles,
        path: '0/0',
      );
      expect(actual.textSpan.toPlainText(), expected.textSpan.toPlainText());
      expect(actual.style.textStyle, expected.style.textStyle);
      expect(
        actual.runs.map((run) => run.style.textStyle),
        expected.runs.map((run) => run.style.textStyle),
      );
      // Hidden text uses fresh mutable Paint values, whose identity is not
      // value equality. Verify their visible effect as well as raw typography.
      Object paintEffect(ForumBodyParagraphContent content) => content
          .textSpan
          .children!
          .whereType<TextSpan>()
          .map(
            (span) => (
              span.text,
              span.style!.foreground?.color,
              span.style!.background?.color,
              span.style!.decoration,
            ),
          )
          .toList();
      expect(paintEffect(actual), paintEffect(expected));
      expect(actual.identity, expected.identity);
      expect(actual.fontRevision, expected.fontRevision);
      expect(actual.styleRevision, expected.styleRevision);
      expect(
        actual.projection.hasSameSourceMapping(expected.projection),
        isTrue,
      );
      expect(
        actual.runs.map((run) => run.path),
        expected.runs.map((run) => run.path),
      );
      expect(actual.projection.text, '甲 乙\né👩🏽‍💻丙');
      for (var offset = 0; offset <= actual.projection.text.length; offset++) {
        for (final affinity in HtmlProjectionAffinity.values) {
          final first = actual.projection.sourceAtUtf16(
            offset,
            affinity: affinity,
          );
          final second = expected.projection.sourceAtUtf16(
            offset,
            affinity: affinity,
          );
          expect(
            (first.sourceRune, first.displayUtf16, first.isExact),
            (second.sourceRune, second.displayUtf16, second.isExact),
          );
        }
      }
      expect(flow.nextBatch(maxEvents: 1).single.node.path, '0/1');
    },
  );

  test('input/run admission is shared and a failed consumer cannot resume', () {
    for (final (builder, failure) in [
      (
        const ForumBodyParagraphContentBuilder(maxInputCodeUnits: 3),
        ForumBodyParagraphInputFailure.inputLimit,
      ),
      (
        const ForumBodyParagraphContentBuilder(maxRuns: 1),
        ForumBodyParagraphInputFailure.runLimit,
      ),
    ]) {
      final flow = _flow(_parse('<p>ab<b>cd</b></p>'));
      addTearDown(flow.close);
      flow.moveNext();
      final accumulator = builder.openCurrent(flow);
      expect(
        () => accumulator.advance(maxEvents: 20),
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (error) => error.failure,
            'failure',
            failure,
          ),
        ),
      );
      expect(accumulator.isClosed, isTrue);
      expect(() => accumulator.advance(maxEvents: 1), throwsStateError);
      expect(accumulator.finish, throwsStateError);
      expect(flow.isClosed, isFalse);
    }
  });

  test(
    'complex content is rejected explicitly; hidden trees remain bounded',
    () {
      for (final inner in [
        '<img src="x">',
        '<ruby>字<rt>じ</rt></ruby>',
        '<span style="padding:2px">box</span>',
      ]) {
        final flow = _flow(_parse('<p>$inner</p>'));
        addTearDown(flow.close);
        flow.moveNext();
        final accumulator = const ForumBodyParagraphContentBuilder()
            .openCurrent(flow);
        expect(
          () => accumulator.advance(maxEvents: 20),
          throwsA(
            isA<ForumBodyParagraphInputException>().having(
              (error) => error.failure,
              'failure',
              ForumBodyParagraphInputFailure.structure,
            ),
          ),
        );
      }
      final flow = _flow(
        _parse('<p hidden>${List.filled(1000, '<b>hidden</b>').join()}</p>'),
      );
      addTearDown(flow.close);
      flow.moveNext();
      final accumulator = const ForumBodyParagraphContentBuilder(
        maxInputCodeUnits: 0,
        maxRuns: 0,
      ).openCurrent(flow);
      addTearDown(accumulator.close);
      expect(accumulator.advance(maxEvents: 2), 2);
      expect(accumulator.isComplete, isFalse);
      expect(flow.resolvedNodeCount, lessThan(5));
      while (!accumulator.isComplete) {
        expect(accumulator.advance(maxEvents: 32), lessThanOrEqualTo(32));
      }
      expect(accumulator.finish().projection.text, isEmpty);
    },
  );

  test(
    'diagnostics stay with the flow owner and paragraph filters its subtree',
    () {
      final flow = _flow(
        _parse('<div style="float:left"><p style="float:right">text</p></div>'),
      );
      addTearDown(flow.close);
      flow.nextBatch(maxEvents: 2);
      final accumulator = const ForumBodyParagraphContentBuilder().openCurrent(
        flow,
      );
      while (!accumulator.isComplete) {
        accumulator.advance(maxEvents: 2);
      }
      final issues = flow.takePendingIssues();
      expect(issues.map((issue) => issue.path), ['0', '0/0']);
      final content = accumulator.finish(issues: issues);
      expect(content.issues.single.path, '0/0');
      expect(issues, hasLength(2));
    },
  );

  test(
    'cancel and concurrent cursor movement cannot publish a partial paragraph',
    () {
      final flow = _flow(_parse('<p>text<b>more</b></p>'));
      addTearDown(flow.close);
      flow.moveNext();
      final accumulator = const ForumBodyParagraphContentBuilder().openCurrent(
        flow,
      );
      expect(() => accumulator.advance(maxEvents: 0), throwsArgumentError);
      expect(flow.current!.node.path, '0');
      flow.moveNext();
      expect(
        () => accumulator.advance(maxEvents: 1),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
      expect(accumulator.isClosed, isTrue);
      final cancelledFlow = _flow(_parse('<p>text</p>'));
      cancelledFlow.moveNext();
      final cancelled = const ForumBodyParagraphContentBuilder().openCurrent(
        cancelledFlow,
      );
      cancelledFlow.close();
      expect(() => cancelled.advance(maxEvents: 1), throwsStateError);
      expect(cancelled.isClosed, isTrue);
    },
  );

  test(
    'standalone text and empty paragraphs finish with unchanged source identity',
    () {
      final flow = _flow(_parse('text<p></p>'));
      addTearDown(flow.close);
      flow.moveNext();
      final text = const ForumBodyParagraphContentBuilder().openCurrent(flow);
      expect(text.isComplete, isTrue);
      expect(text.finish().projection.text, 'text');
      flow.moveNext();
      final empty = const ForumBodyParagraphContentBuilder().openCurrent(flow);
      expect(empty.advance(maxEvents: 1), 1);
      expect(empty.finish().projection.text, isEmpty);
      expect(
        () => const ForumBodyParagraphContentBuilder().openCurrent(flow),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
    },
  );

  testWidgets(
    'incremental paragraph and eager input share one painted native layout',
    (tester) async {
      final document = _parse('<p>first line<br>second line</p><p>later</p>');
      final flow = _flow(document);
      addTearDown(flow.close);
      flow.moveNext();
      final accumulator = const ForumBodyParagraphContentBuilder().openCurrent(
        flow,
      );
      while (!accumulator.isComplete) {
        accumulator.advance(maxEvents: 2);
      }
      final incremental = accumulator.finish();
      final eager = const ForumBodyParagraphContentBuilder().build(
        document: document,
        styles: const ForumBodyStyleResolver().resolve(document, _reader),
        path: '0',
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 2,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final first = cache.acquire(content: incremental, width: 300);
      final second = cache.acquire(content: eager, width: 300);
      expect(first.layout, same(second.layout));
      expect(first.layout.lines, hasLength(2));
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ForumBodyParagraphSurface(
                  lease: first,
                  startLine: 0,
                  endLine: 1,
                ),
                ForumBodyParagraphSurface(
                  lease: second,
                  startLine: 1,
                  endLine: 2,
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(cache.layoutBuildCount, 1);
      expect(cache.activeLeases, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(cache.activeLeases, 0);
    },
  );
}
