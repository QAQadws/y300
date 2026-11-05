import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyTextPageSession _open(
  String html, {
  double width = 100,
  double height = 60,
  int? handles,
  ForumBodyLength indent = ForumBodyLength.zero,
}) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'discuz-float-page',
    conversionIdentity: 'none',
  );
  final cache = ForumBodyParagraphCache(
    maxEntries: 32,
    maxEstimatedBytes: 1 << 22,
  );
  addTearDown(cache.close);
  final session = ForumBodyTextPageSession(
    document: document,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
      fontRevision: 'discuz-float-page',
      linkColor: const Color(0xff0000ff),
      paragraphAfter: 0,
      firstLineIndent: indent,
    ),
    cache: cache,
    limits: const ForumBodyTextPageSessionLimits(
      maxPages: 16,
      maxFragments: 48,
      maxParagraphs: 48,
      maxTextCodeUnits: 2048,
      maxRuns: 128,
      maxIssuedLeases: 8,
    ),
    layoutId: 'discuz-float-page',
    width: width,
    height: height,
    captureFloats: true,
    maxNativeHandlesPerPage: handles,
    maxNativeEntriesPerPage: handles,
    maxNativeEstimatedBytesPerPage: 1 << 20,
  );
  addTearDown(session.close);
  return session;
}

void _advance(ForumBodyTextPageSession session, {int? untilPages}) {
  var steps = 0;
  while (!session.isComplete &&
      (untilPages == null || session.snapshot.length < untilPages)) {
    if (++steps > 2000) fail('Float session did not reach its target');
    final step = session.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 4);
    expect(step.layoutsBuilt, lessThanOrEqualTo(1));
    expect(step.pagesPublished, lessThanOrEqualTo(1));
    expect(step.waitingForLayoutBudget, isFalse);
  }
}

List<ForumBodyPreparedTextFragment> _prepare(
  ForumBodyTextPageSession session,
  int index,
) {
  final preparation = session.openPagePreparation(index);
  try {
    var steps = 0;
    while (!preparation.isReady) {
      if (++steps > 2000) fail('Float fragments did not become ready');
      preparation.advance(maxFragments: 1, maxParts: 4);
    }
    return preparation.takeFragments();
  } finally {
    preparation.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });

  testWidgets(
    'opposite floats paint in one page and clear moves the cursor by side',
    (tester) async {
      final session = _open(
        '<span style="float:left;margin:2px 5px 0 0;background-color:red">AA</span>'
        '<span style="float:right;margin-left:5px;height:30px">BBB</span>'
        '<br style="clear:left"><span style="float:left">CC</span>'
        '<br style="clear:both">tail',
      );
      _advance(session);
      final snapshot = session.snapshot;
      final page = snapshot.single;
      expect(page.usedHeight, 40);
      expect(page.fragments.map((fragment) => (fragment.left, fragment.top)), [
        (0.0, 2.0),
        (70.0, 0.0),
        (0.0, 12.0),
        (0.0, 30.0),
      ]);
      expect(page.fragments.map((fragment) => fragment.paragraphIndex), [
        0,
        1,
        2,
        3,
      ]);
      expect(page.backgrounds.single.color, const Color(0xffff0000));
      final deliveries = _prepare(session, 0);
      expect(deliveries.map((fragment) => fragment.projection.text), [
        'AA',
        'BBB',
        'CC',
        'tail',
      ]);
      expect(session.activeIssuedLeases, 4);
      final tapped = <(int, int)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: ForumBodyTextPageSurface.prepared(
              snapshot: snapshot,
              pageIndex: 0,
              layoutId: snapshot.layoutId,
              fragments: deliveries,
              onSourceTap: (fragment, position) =>
                  tapped.add((fragment.paragraphIndex, position.sourceRune)),
            ),
          ),
        ),
      );
      await tester.tapAt(const Offset(3, 6));
      await tester.tapAt(const Offset(74, 5));
      await tester.tapAt(const Offset(3, 16));
      expect(tapped, [(0, 0), (1, 2), (2, 6)]);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(session.activeIssuedLeases, 0);
    },
  );

  test(
    'a float moves as a unit to the next page and preserves the first prefix',
    () {
      final session = _open(
        '<p>lead</p><span style="float:right;height:30px">AA</span>'
        '<br style="clear:both"><p>tail</p>',
        height: 32,
      );
      _advance(session, untilPages: 1);
      final prefix = session.snapshot;
      expect(prefix.single.fragments.single.paragraphIndex, 0);
      _advance(session);
      expect(prefix, hasLength(1));
      expect(session.snapshot, hasLength(3));
      expect(session.snapshot.first, same(prefix.first));
      final float = session.snapshot[1].fragments.single;
      expect((float.paragraphIndex, float.left, float.top), (1, 80.0, 0.0));
      expect(session.snapshot[1].usedHeight, 30);
      expect(session.snapshot.last.fragments.single.paragraphIndex, 2);
    },
  );

  test('a second float respects the draft native handle budget', () {
    final session = _open(
      '<span style="float:left"><ruby>AA<rt>a</rt></ruby></span>'
      '<span style="float:right"><ruby>BB<rt>b</rt></ruby></span>',
      handles: 4,
    );
    _advance(session);
    expect(session.snapshot, hasLength(2));
    expect(session.snapshot.first.fragments.single.left, 0);
    expect(session.snapshot.last.fragments.single.left, 80);
    for (final index in [0, 1]) {
      final deliveries = _prepare(session, index);
      expect(deliveries.single.nativeLeases.length, greaterThan(2));
      deliveries.single.close();
    }
  });

  test('opposite float boxes move down when their margins leave no room', () {
    final session = _open(
      '<span style="float:left;margin-right:5px">AAA</span>'
      '<span style="float:right;margin-left:5px">BBB</span>',
      width: 50,
    );
    _advance(session);
    expect(
      session.snapshot.single.fragments.map(
        (fragment) => (fragment.left, fragment.top),
      ),
      [(0.0, 0.0), (20.0, 10.0)],
    );
  });

  test('text uses successive exclusion widths and keeps every source position', () {
    final text = 'A' * 48;
    final session = _open(
      '<span style="float:left;width:30px;height:30px;margin-right:5px">L</span>'
      '<span style="float:right;width:20px;height:10px;margin-left:5px">R</span>'
      '$text',
      height: 80,
    );
    _advance(session);
    final page = session.snapshot.single;
    final bands = page.fragments.skip(2).toList();
    expect(bands.map((part) => (part.left, part.top, part.width)), [
      (35.0, 0.0, 40.0),
      (35.0, 10.0, 65.0),
      (0.0, 30.0, 100.0),
    ]);
    final fragments = _prepare(session, 0);
    var rawOffset = 2;
    final painted = StringBuffer();
    for (final (index, part) in bands.indexed) {
      expect(part.sourceHint!.runeStart, rawOffset);
      rawOffset = part.sourceHint!.runeEnd;
      final projected = fragments[index + 2].projection.text;
      painted.write(
        projected.substring(part.coverageStartUtf16, part.coverageEndUtf16),
      );
    }
    expect(rawOffset, 50);
    expect(painted.toString(), text);
    for (final fragment in fragments) {
      fragment.close();
    }
  });

  for (final margin in [5, 10]) {
    test(
      'text moves under the float when the remaining width is ${10 - margin}',
      () {
        final session = _open(
          '<span style="float:left;width:90px;height:20px;margin-right:${margin}px">L</span>'
          '<p>text after</p>',
        );
        _advance(session);
        final parts = session.snapshot.single.fragments;
        expect(parts, hasLength(2));
        expect(
          (parts.last.left, parts.last.top, parts.last.width),
          (0.0, 20.0, 100.0),
        );
        expect(parts.last.sourceHint, (runeStart: 1, runeEnd: 11));
      },
    );
  }

  test('a book page seal reflows only the unconsumed text at full width', () {
    final text = 'Z' * 28;
    final session = _open(
      '<span style="float:right;width:35px;height:25px;margin-left:5px">R</span>'
      '$text',
      height: 28,
    );
    _advance(session, untilPages: 1);
    final prefix = session.snapshot;
    final beside = prefix.single.fragments.last;
    expect((beside.left, beside.width, beside.height), (0.0, 60.0, 20.0));
    expect(beside.sourceHint, (runeStart: 1, runeEnd: 13));
    _advance(session);
    expect(session.snapshot, hasLength(2));
    expect(session.snapshot.first, same(prefix.first));
    final continued = session.snapshot.last.fragments.single;
    expect((continued.left, continued.top, continued.width), (0.0, 0.0, 100.0));
    expect(continued.sourceHint, (runeStart: 13, runeEnd: 29));
  });

  test('a page-height float does not seal while there is room beside it', () {
    final session = _open(
      '<span style="float:left;width:30px;height:30px;margin-right:5px">L</span>'
      '${'A' * 20}',
      height: 30,
    );
    _advance(session);
    expect(session.snapshot, hasLength(2));
    final beside = session.snapshot.first.fragments.last;
    expect((beside.left, beside.width, beside.height), (35.0, 65.0, 30.0));
    expect(beside.sourceHint, (runeStart: 1, runeEnd: 19));
    final next = session.snapshot.last.fragments.single;
    expect((next.left, next.width, next.top), (0.0, 100.0, 0.0));
    expect(next.sourceHint, (runeStart: 19, runeEnd: 21));
  });

  test('a clear after wrapped text restores full width at the float bottom', () {
    final session = _open(
      '<span style="float:left;width:30px;height:30px;margin-right:5px">L</span>'
      'before<br style="clear:left">after',
    );
    _advance(session);
    final parts = session.snapshot.single.fragments;
    expect(parts.map((part) => (part.left, part.top, part.width)), [
      (0.0, 0.0, 30.0),
      (35.0, 0.0, 65.0),
      (0.0, 30.0, 100.0),
    ]);
    expect(parts[1].sourceHint, (runeStart: 1, runeEnd: 7));
    expect(parts[2].sourceHint, (runeStart: 8, runeEnd: 13));
  });

  test('a band change preserves author styles without indenting twice', () {
    final text = 'A' * 25;
    final session = _open(
      '<span style="float:left;width:30px;height:20px;margin-right:5px">L</span>'
      '<strong style="color:red">$text</strong>',
      indent: const ForumBodyLength(1, ForumBodyLengthUnit.em),
    );
    _advance(session);
    final page = session.snapshot.single;
    expect(page.fragments.map((part) => part.width), [30.0, 65.0, 100.0]);
    final deliveries = _prepare(session, 0);
    final beside = deliveries[1] as ForumBodyPreparedParagraphFragment;
    final after = deliveries[2] as ForumBodyPreparedParagraphFragment;
    expect(beside.lease.layout.firstLineIndent.appliedAdvance, greaterThan(0));
    expect(after.lease.layout.firstLineIndent.appliedAdvance, 0);
    expect(beside.runs.single.style.textStyle.color, const Color(0xffff0000));
    expect(after.runs.single.style.textStyle.color, const Color(0xffff0000));
    expect(
      page.fragments[1].sourceHint!.runeEnd,
      page.fragments[2].sourceHint!.runeStart,
    );
    for (final fragment in deliveries) {
      fragment.close();
    }
  });

  test('terminal empty lines do not replay floats from the previous row', () {
    final session = _open(
      '<span style="float:left;width:30px;height:30px">L</span>text<br><br>',
    );
    _advance(session);
    final parts = session.snapshot.single.fragments;
    expect(
      parts.where((part) => part.sourceHint?.runeStart == 0),
      hasLength(1),
    );
    expect(parts.last.sourceHint, isNull);
    expect(parts.last.left, 30);
  });

  test(
    'a failure in unresolved float lines leaves the stable prefix readable',
    () {
      final session = _open(
        '<p>lead</p>preceding<span style="float:left">AA</span>alongside',
        height: 10,
      );
      _advance(session, untilPages: 1);
      final prefix = session.snapshot;
      expect(
        () => _advance(session),
        throwsA(
          isA<ForumBodyTextPageSessionException>().having(
            (error) => error.failure,
            'failure',
            ForumBodyTextPageSessionFailure.floatLineLayout,
          ),
        ),
      );
      expect(session.state, ForumBodyTextPageSessionState.failed);
      expect(session.snapshot.single, same(prefix.single));
      final delivered = _prepare(session, 0).single;
      expect(delivered.projection.text, 'lead');
      delivered.close();
    },
  );
}
