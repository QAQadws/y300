import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _headingStyle = 'margin:0;font-size:10px;line-height:10px';
const _heading = '<h2 style="$_headingStyle">Title</h2>';

ForumBodyTextPageSession _session(
  String html, {
  required bool keep,
  double height = 20,
  double width = 50,
  bool avoidIsolatedLines = false,
  ForumBodyParagraphCache? cache,
}) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'heading-keep',
    conversionIdentity: 'none',
  );
  final owner =
      cache ??
      ForumBodyParagraphCache(maxEntries: 12, maxEstimatedBytes: 1 << 22);
  if (cache == null) addTearDown(owner.close);
  final session = ForumBodyTextPageSession(
    document: document,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 10, height: 1),
      fontRevision: 'ahem',
      paragraphAfter: 0,
      linkColor: const Color(0xff0000ff),
    ),
    cache: owner,
    limits: const ForumBodyTextPageSessionLimits(
      maxPages: 100,
      maxFragments: 150,
      maxParagraphs: 100,
      maxTextCodeUnits: 20000,
      maxRuns: 500,
      maxIssuedLeases: 24,
    ),
    layoutId: 'heading-keep-$keep',
    width: width,
    height: height,
    keepHeadingWithNext: keep,
    avoidIsolatedLines: avoidIsolatedLines,
  );
  addTearDown(session.close);
  return session;
}

ForumBodyTextPageSessionStep _advance(ForumBodyTextPageSession session) {
  final step = session.advance(maxEvents: 1, maxLines: 1, maxFormatParts: 1);
  expect(step.flowWorkDone, lessThanOrEqualTo(1));
  expect(step.linesInspected, lessThanOrEqualTo(1));
  expect(step.formatUnitsPrepared, lessThanOrEqualTo(1));
  expect(step.pagesPublished, lessThanOrEqualTo(1));
  expect(step.madeProgress, isTrue);
  return step;
}

void _finish(ForumBodyTextPageSession session, {int? pages}) {
  for (var calls = 0; calls < 3000; calls++) {
    if (session.isComplete ||
        (pages != null && session.snapshot.length >= pages)) {
      return;
    }
    _advance(session);
  }
  fail('Heading pagination did not finish within its bounded test loop');
}

List<List<String?>> _paths(ForumBodyTextPageSession session) => [
  for (final page in session.snapshot) [for (final f in page.fragments) f.path],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });

  test(
    'a heading at page start takes precedence over the follower line balance',
    () {
      final keep = _session(
        '$_heading<p>abcdefgh</p>',
        keep: true,
        avoidIsolatedLines: true,
      );
      _finish(keep);
      expect(_paths(keep), [
        ['0', '1'],
        ['1'],
      ]);
      expect(keep.snapshot.first.fragments.last.endLine, 1);
    },
  );

  test(
    'title and the first line of its body move together without revising the prefix',
    () {
      const html = '<p>Intro</p>$_heading<p>abcdefgh</p>';
      final baseline = _session(html, keep: false);
      _finish(baseline);
      expect(_paths(baseline), [
        ['0', '1'],
        ['2'],
      ]);
      final keep = _session(html, keep: true, avoidIsolatedLines: true);
      _finish(keep, pages: 1);
      final prefix = keep.snapshot;
      expect(_paths(keep), [
        ['0'],
      ]);
      _finish(keep);
      expect(_paths(keep), [
        ['0'],
        ['1', '2'],
        ['2'],
      ]);
      expect(prefix, hasLength(1));
      expect(keep.snapshot.first, same(prefix.first));
      expect(keep.snapshot[1].fragments.last.endLine, 1);
      expect(keep.snapshot.last.fragments.single.startLine, 1);
      final prepared = keep.preparePageFragments(1);
      try {
        expect(prepared.map((fragment) => fragment.projection.text), [
          'Title',
          'abcdefgh',
        ]);
      } finally {
        for (final fragment in prepared) {
          fragment.close();
        }
      }
    },
  );

  test(
    'measured padding follows the heading and the next paragraph remains intact',
    () {
      final keep = _session(
        '<p>Intro</p><h2 style="$_headingStyle;padding:2px 0;margin:4px 0">Title</h2>'
        '<div><p>Body</p></div>',
        keep: true,
        height: 30,
      );
      _finish(keep);
      expect(_paths(keep), [
        ['0'],
        ['1', '2/0'],
      ]);
      expect(keep.snapshot.first.usedHeight, 10);
      expect(keep.snapshot.last.fragments.map((fragment) => fragment.top), [
        2,
        18,
      ]);
    },
  );

  test('a single-layer ruby follower uses the measured inline rows', () {
    final keep = _session(
      '<p>Intro</p>$_heading<p><ruby>基<rt>よみ</rt></ruby> A</p>',
      keep: true,
      height: 30,
    );
    _finish(keep);
    expect(_paths(keep), [
      ['0'],
      ['1', '2'],
    ]);
    expect(
      keep.snapshot.last.fragments.last.kind,
      ForumBodyTextPageFragmentKind.inline,
    );
  });

  for (final (label, suffix, height) in [
    ('terminal title', '', 20.0),
    ('rule barrier', '<hr><p>Body</p>', 20.0),
    ('impossibly short page', '<p>Body</p>', 15.0),
    ('long descendant stream', '<p>${'<span>a</span>' * 120}</p>', 20.0),
  ]) {
    test('$label relaxes without dropping any flow input', () {
      final html = '<p>Intro</p>$_heading$suffix';
      final baseline = _session(html, keep: false, height: height);
      final keep = _session(html, keep: true, height: height);
      _finish(baseline);
      _finish(keep);
      expect(_paths(keep), _paths(baseline));
      expect(
        keep.snapshot.map((page) => page.usedHeight),
        baseline.snapshot.map((page) => page.usedHeight),
      );
    });
  }

  test('retirement releases a speculative measurement', () {
    final cache = ForumBodyParagraphCache(
      maxEntries: 8,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final session = _session(
      '<p>Intro</p>$_heading<p>Body</p>',
      keep: true,
      cache: cache,
    );
    for (var i = 0; i < 200 && cache.layoutBuildCount < 2; i++) {
      _advance(session);
    }
    expect(cache.layoutBuildCount, 2);
    expect(session.retainedParagraphCount, 1);
    expect(cache.activeLeases, 1);
    session.close();
    expect(cache.activeLeases, 0);
  });
}
