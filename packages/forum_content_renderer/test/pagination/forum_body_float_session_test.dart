import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyTextPageSession _open(
  String html, {
  double width = 100,
  double height = 60,
  int? handles,
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

  test(
    'a failure in unresolved float lines leaves the stable prefix readable',
    () {
      final session = _open(
        '<p>lead</p><span style="float:left">AA</span>alongside',
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
