import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(
    fontFamily: 'Ahem',
    fontSize: 20,
    height: 1,
    color: Color(0xff000000),
  ),
  fontRevision: 'edit-status-font',
  linkColor: const Color(0xff0000ff),
);

ForumBodyDocument _document(String html) => const ForumBodyParser().parse(
  html: html,
  sourceId: 'edit-status',
  conversionIdentity: 'none',
);

List<ForumBodyTextFlowUnit> _drain(ForumBodyTextFlowCursor flow) {
  final units = <ForumBodyTextFlowUnit>[];
  var calls = 0;
  while (!flow.isComplete) {
    if (++calls > 10000) fail('Edit status flow did not complete');
    final step = flow.advance(maxEvents: 1);
    expect(step.eventsRead, lessThanOrEqualTo(1));
    expect(step.eventsRead > 0 || step.hasOutput, isTrue);
    if (step.hasOutput) units.add(flow.current!);
  }
  return units;
}

List<ForumBodyTextFlowParagraph> _paragraphs(String html) {
  final flow = ForumBodyTextFlowCursor(
    document: _document(html),
    reader: _reader,
  );
  try {
    return _drain(flow).whereType<ForumBodyTextFlowParagraph>().toList();
  } finally {
    flow.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'edit notice is fitted without rewriting the IR or body source coordinates',
    () {
      final document = _document(
        '<i class="pstatus"> Editor&nbsp;A<br> at<span> \t2026 </span></i><br><br><p>Body.</p>',
      );
      final flow = ForumBodyTextFlowCursor(document: document, reader: _reader);
      addTearDown(flow.close);
      final units = _drain(flow);
      final paragraphs = units.whereType<ForumBodyTextFlowParagraph>().toList();
      expect(paragraphs.map((unit) => unit.content.projection.text), [
        'Editor A at 2026',
        'Body.',
      ]);
      expect(paragraphs.map((unit) => unit.content.layoutMode), [
        ForumBodyParagraphLayoutMode.fitSingleLine,
        ForumBodyParagraphLayoutMode.wrap,
      ]);
      expect(
        paragraphs.every(
          (unit) => unit.window == ForumBodyParagraphWindow.full,
        ),
        isTrue,
      );
      expect(paragraphs.first.content.style.role, ForumBodyTextRole.notice);
      expect(
        paragraphs.first.content.style.textStyle.fontSize,
        closeTo(17.6, 1e-9),
      );
      expect(
        paragraphs.first.content.style.textStyle.fontStyle,
        FontStyle.italic,
      );
      expect(
        paragraphs.first.content.style.textStyle.color!.a,
        closeTo(.62, 1e-9),
      );
      expect(paragraphs.last.content.style.textStyle.fontSize, 20);
      expect(paragraphs.last.content.style.textStyle.color!.a, 1);
      expect(
        (document.nodeAtPath('1') as ForumBodyElement).kind,
        ForumBodyElementKind.hardBreak,
      );
      expect(
        (document.nodeAtPath('2') as ForumBodyElement).kind,
        ForumBodyElementKind.hardBreak,
      );
      expect(
        paragraphs.last.content.projection.sourceAtUtf16(0).sourceRune,
        document.nodeAtPath('3/0')!.source.runeStart,
      );
    },
  );

  test(
    'eager, bounded subtree and text flow share notice whitespace provenance',
    () {
      final document = _document(
        '<i class="pstatus"> A\r\n<span>&nbsp;B</span><br>C </i>',
      );
      final styles = const ForumBodyStyleResolver().resolve(document, _reader);
      const builder = ForumBodyParagraphContentBuilder();
      final eager = builder.build(
        document: document,
        styles: styles,
        path: '0',
        layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
      );
      final styled = ForumBodyStyledFlowCursor(
        document: document,
        reader: _reader,
      );
      addTearDown(styled.close);
      expect(styled.moveNext(), isTrue);
      final accumulator = builder.openCurrent(
        styled,
        layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
      );
      while (!accumulator.isComplete) {
        expect(accumulator.advance(maxEvents: 1), lessThanOrEqualTo(1));
      }
      final incremental = accumulator.finish();
      final flow = ForumBodyTextFlowCursor(document: document, reader: _reader);
      addTearDown(flow.close);
      final streamed = _drain(
        flow,
      ).whereType<ForumBodyTextFlowParagraph>().single.content;
      expect(eager.projection.text, 'A B C');
      expect(
        eager.projection.hasSameSourceMapping(incremental.projection),
        isTrue,
      );
      expect(
        eager.projection.hasSameSourceMapping(streamed.projection),
        isTrue,
      );
      expect(incremental.layoutMode, streamed.layoutMode);
    },
  );

  test('only sibling breaks following the notice are normalized', () {
    final paragraphs = _paragraphs(
      '<div><i class="pstatus">Notice</i><br></div><br><br>Outside',
    );
    expect(paragraphs.first.content.projection.text, 'Notice');
    expect(
      paragraphs
          .skip(1)
          .any((unit) => unit.content.projection.text.contains('\n')),
      isTrue,
    );
    expect(paragraphs.last.content.projection.text, contains('Outside'));
  });

  test(
    'following preformatted whitespace survives unless a BR confirms normalization',
    () {
      final withoutBreak = _paragraphs(
        '<div style="white-space:pre-wrap"><i class="pstatus">Notice</i> \t<span>x</span></div>',
      );
      expect(withoutBreak.map((unit) => unit.content.projection.text), [
        'Notice',
        ' \tx',
      ]);
      final withBreak = _paragraphs(
        '<div style="white-space:pre-wrap"><i class="pstatus">Notice</i> \t<br>&nbsp;<br> \t<span>x</span></div>',
      );
      expect(withBreak.map((unit) => unit.content.projection.text), [
        'Notice',
        'x',
      ]);
    },
  );

  test(
    'fitted notice height and fixed padding feed the same page and native leases',
    () {
      final document = _document(
        '<i class="pstatus">abcdefghijklmnopqrst</i><br><br><p>Body</p>',
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final session = ForumBodyTextPageSession(
        document: document,
        reader: _reader,
        cache: cache,
        layoutId: 'edit-page',
        width: 100,
        height: 40,
        limits: const ForumBodyTextPageSessionLimits(
          maxPages: 20,
          maxFragments: 40,
          maxParagraphs: 20,
          maxTextCodeUnits: 2000,
          maxRuns: 40,
          maxIssuedLeases: 8,
        ),
      );
      addTearDown(session.close);
      var calls = 0;
      while (!session.isComplete) {
        if (++calls > 10000) fail('Edit notice page did not finish');
        final step = session.advance(maxEvents: 1, maxLines: 1);
        expect(step.eventsRead, lessThanOrEqualTo(1));
        expect(step.linesInspected, lessThanOrEqualTo(1));
        expect(step.madeProgress, isTrue);
      }
      expect(session.snapshot, hasLength(1));
      final page = session.snapshot.single;
      expect(page.fragments, hasLength(2));
      expect(page.fragments.first.height, lessThan(10));
      expect(
        page.fragments.last.top,
        closeTo(page.fragments.first.height + 8, 1e-5),
      );
      expect(page.usedHeight, closeTo(page.fragments.last.top + 20, 1e-5));
      final leases = session.preparePageLeases(0);
      validateForumBodyTextPageBinding(
        snapshot: session.snapshot,
        pageIndex: 0,
        layoutId: 'edit-page',
        leases: leases,
      );
      expect(
        leases.first.content.layoutMode,
        ForumBodyParagraphLayoutMode.fitSingleLine,
      );
      expect(leases.first.layout.lines, hasLength(1));
      expect(page.fragments.first.height, leases.first.layout.height);
      expect(
        leases.first.layout.selectionBoxes(19, 20).single.right,
        closeTo(100, 1e-5),
      );
      expect(cache.layoutBuildCount, 2);
      for (final lease in leases) {
        lease.release();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'edit status admission cannot silently flatten resources or nested blocks',
    () {
      for (final html in [
        '<i class="pstatus">Notice<img src="image.png"></i>',
        '<i class="pstatus">Notice<div>nested block</div></i>',
      ]) {
        final flow = ForumBodyTextFlowCursor(
          document: _document(html),
          reader: _reader,
        );
        expect(
          () => _drain(flow),
          throwsA(isA<ForumBodyParagraphInputException>()),
        );
        expect(flow.isClosed, isTrue);
      }
    },
  );
}
