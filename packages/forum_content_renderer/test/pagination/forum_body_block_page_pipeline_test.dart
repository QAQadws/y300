import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

// Integration expectations consume the real bounded session, not a second
// implementation of block/margin/padding orchestration in the test harness.
({ForumBodyTextPageSnapshot pages, int builds}) _compose(
  String html, {
  double height = 100,
}) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'block-page-pipeline',
    conversionIdentity: 'none',
  );
  final cache = ForumBodyParagraphCache(
    maxEntries: 4,
    maxEstimatedBytes: 1 << 20,
  );
  final session = ForumBodyTextPageSession(
    document: document,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
    cache: cache,
    limits: const ForumBodyTextPageSessionLimits(
      maxPages: 100,
      maxFragments: 100,
      maxParagraphs: 100,
      maxTextCodeUnits: 10000,
      maxRuns: 1000,
      maxIssuedLeases: 20,
    ),
    layoutId: 'pipeline',
    width: 200,
    height: height,
  );
  try {
    var calls = 0;
    while (!session.isComplete) {
      if (++calls > 1000) fail('Session did not reach EOF');
      final step = session.advance(maxEvents: 1, maxLines: 1);
      expect(step.madeProgress, isTrue);
      expect(step.waitingForLayoutBudget, isFalse);
    }
    expect(cache.activeLeases, 0);
    return (pages: session.snapshot, builds: cache.layoutBuildCount);
  } finally {
    session.close();
    cache.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'adjoining paragraph margins reach real native fragment positions once',
    () {
      final result = _compose(
        '<p style="margin:10px 0 20px">a</p><p style="margin:30px 0 40px">b</p>',
      );
      expect(result.pages.single.fragments.map((fragment) => fragment.top), [
        0,
        40,
      ]);
      expect(result.pages.single.usedHeight, 50);
      expect(result.builds, 2);
    },
  );

  test(
    'nested padding and paragraph margin retain continuous native geometry',
    () {
      final result = _compose(
        '<div style="margin:5px;padding:2px"><p style="margin:10px">a</p></div>',
      );
      final fragment = result.pages.single.fragments.single;
      expect((fragment.left, fragment.top, fragment.width), (17, 12, 166));
      expect(result.pages.single.usedHeight, 34);
      expect(result.builds, 1);
    },
  );

  test('a margin before trailing padding trims on the real page break', () {
    final result = _compose(
      '<div style="padding:5px 0"><p style="margin:0 0 15px">a</p></div>',
      height: 20,
    );
    expect(result.pages.map((page) => page.usedHeight), [15, 5]);
    expect(result.pages.first.fragments.single.top, 5);
    expect(result.pages.last.fragments, isEmpty);
    expect(result.builds, 1);
  });

  test(
    'negative adjoining margin applies before padding and does not repeat before text',
    () {
      final result = _compose(
        '<div style="padding:0 0 5px"><p style="margin:0 0 -5px">a</p></div><p style="margin:0">b</p>',
      );
      expect(result.pages.single.fragments.map((fragment) => fragment.top), [
        0,
        10,
      ]);
      expect(result.pages.single.usedHeight, 20);
      expect(result.builds, 2);
    },
  );
}
