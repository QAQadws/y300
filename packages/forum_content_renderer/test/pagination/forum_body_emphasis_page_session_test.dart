import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _ignored =
    "text-emphasis:'◆' red;text-emphasis-style:filled sesame;"
    'text-emphasis-color:lime;text-emphasis-position:under left;'
    "-webkit-text-emphasis:'✦';-webkit-text-emphasis-style:open dot;"
    '-webkit-text-emphasis-color:orange;-webkit-text-emphasis-position:over;';

({List<Object?> pages, List<String> text, int layouts, int pictures}) _read(
  String html,
) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'ignored-emphasis',
    conversionIdentity: 'none',
  );
  final cache = ForumBodyParagraphCache(
    maxEntries: 16,
    maxEstimatedBytes: 1 << 24,
  );
  final session = ForumBodyTextPageSession(
    document: document,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 16, height: 1),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
    cache: cache,
    limits: const ForumBodyTextPageSessionLimits(
      maxPages: 80,
      maxFragments: 100,
      maxParagraphs: 100,
      maxTextCodeUnits: 10000,
      maxRuns: 2000,
      maxIssuedLeases: 64,
    ),
    layoutId: 'ignored-emphasis',
    width: 112,
    height: 48,
  );
  try {
    for (var step = 0; !session.isComplete && step < 10000; step++) {
      final result = session.advance(maxEvents: 2, maxLines: 1);
      expect(result.waitingForLayoutBudget, isFalse);
    }
    expect(session.isComplete, isTrue);
    final pages = <Object?>[], text = <String>{};
    for (final (pageIndex, page) in session.snapshot.indexed) {
      final job = session.openPagePreparation(pageIndex);
      try {
        while (!job.isReady) {
          final step = job.advance(maxFragments: 1, maxParts: 1);
          expect(step.waitingForLayoutBudget, isFalse);
        }
        final fragments = job.takeFragments();
        try {
          pages.add([
            for (final (index, fragment) in page.fragments.indexed)
              _signature(fragment, fragments[index]),
          ]);
          text.addAll(fragments.map((fragment) => fragment.projection.text));
        } finally {
          for (final fragment in fragments) {
            fragment.close();
          }
        }
      } finally {
        job.close();
      }
    }
    expect(cache.activeLeases, 0);
    expect(session.activeIssuedLeases, 0);
    return (
      pages: pages,
      text: text.toList(),
      layouts: cache.layoutBuildCount,
      pictures: cache.pictureBuildCount,
    );
  } finally {
    session.close();
    cache.close();
  }
}

List<Object?> _signature(
  ForumBodyTextPageFragment geometry,
  ForumBodyPreparedTextFragment fragment,
) => [
  geometry.kind,
  geometry.height,
  geometry.sourceHint,
  fragment.projection.text,
  [for (final run in fragment.runs) run.style.textStyle],
  fragment.glyphBoxes(0, fragment.projection.text.length),
  fragment.nativeLeases.length,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (name, html, retained) in [
    (
      'body text and literal punctuation',
      '<p style="__mark__color:blue">AB • CD '
          '<span style="__mark__font-weight:bold;background-color:yellow">EF</span> GH IJ</p>',
      '•',
    ),
    (
      'single-level ruby base and annotation',
      '<p>start <ruby style="__mark__color:blue">'
          '<rb style="__mark__background-color:yellow">AB</rb>'
          '<rt style="__mark__color:green">xy</rt></ruby> end</p>',
      'ABxy',
    ),
    (
      'fitted edit status',
      '<div class="pstatus" style="__mark__color:blue">ABCDEF 1234567890</div>',
      'ABCDEF',
    ),
  ]) {
    test(
      'author emphasis leaves native layout and source intact for $name',
      () {
        final actual = _read(html.replaceAll('__mark__', _ignored));
        final reference = _read(html.replaceAll('__mark__', ''));
        expect(actual.text.any((text) => text.contains(retained)), isTrue);
        expect(actual.pages, reference.pages);
        expect(actual.text, reference.text);
        expect(actual.layouts, reference.layouts);
        expect(actual.pictures, reference.pictures);
      },
    );
  }
}
