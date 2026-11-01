import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/ruby_atom_page_fixture.dart';

({ForumBodyParagraphCache cache, ForumBodyTextPageSession session}) _open(
  String html, {
  required int pageLimit,
  double width = 200,
  double height = 1000,
}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: 16,
    maxEstimatedBytes: 1 << 24,
  );
  final session = ForumBodyTextPageSession(
    document: const ForumBodyParser().parse(
      html: html,
      sourceId: 'physical-page-slots',
      conversionIdentity: 'none',
    ),
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
      paragraphBefore: 0,
      paragraphAfter: 0,
    ),
    cache: cache,
    limits: const ForumBodyTextPageSessionLimits(
      maxPages: 100,
      maxFragments: 1000,
      maxParagraphs: 100,
      maxTextCodeUnits: 100000,
      maxRuns: 10000,
      maxIssuedLeases: 512,
    ),
    maxNativeHandlesPerPage: pageLimit,
    layoutId: 'physical-page-slots',
    width: width,
    height: height,
  );
  addTearDown(() {
    session.close();
    cache.close();
    expect(cache.activeLeases, 0);
    expect(cache.estimatedRetainedBytes, 0);
  });
  return (cache: cache, session: session);
}

void _finish(ForumBodyTextPageSession session, ForumBodyParagraphCache cache) {
  for (var i = 0; !session.isComplete && i < 30000; i++) {
    final before = cache.layoutBuildCount;
    final step = session.advance(maxEvents: 1, maxLines: 1);
    expect(step.formatUnitsPrepared, lessThanOrEqualTo(32));
    expect(cache.layoutBuildCount - before, lessThanOrEqualTo(1));
    expect(step.waitingForLayoutBudget, isFalse);
  }
  expect(session.isComplete, isTrue);
  expect(cache.pictureBuildCount, 0);
}

List<ForumBodyPreparedTextFragment> _page(
  ForumBodyTextPageSession session,
  int page,
  int q,
) {
  final job = session.openPagePreparation(page);
  try {
    for (var i = 0; !job.isReady && i < 30000; i++) {
      final step = job.advance(maxFragments: 1, maxParts: q);
      expect(step.partsPrepared + step.partsInspected, lessThanOrEqualTo(q));
      expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget, isFalse);
    }
    expect(job.isReady, isTrue);
    return job.takeFragments();
  } finally {
    job.close();
  }
}

String _ruby(int columns, {int ranks = 1, double gapSize = 10}) =>
    '<ruby>${List.generate(columns, (i) => '<rb>A</rb>').join(' ')}'
    '${List.generate(ranks, (r) => '<rtc style="font-size:${ranks > 1 ? 1 : gapSize}px">${List.generate(columns, (i) => '<rt>x</rt>').join(' ')}</rtc>').join()}</ruby>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  test(
    'pure request cost rejects partial opaque atoms and excludes ordinary text',
    () {
      final f = RubyAtomPageFixture.segment(surrounding: true);
      addTearDown(f.close);
      final input = f.input;
      final atom = input.content.projection.atoms.single;
      final builds = f.cache.layoutBuildCount;
      expect(input.nativeHandleCountInRange(0, atom.displayStartUtf16), 1);
      expect(
        input.nativeHandleCountInRange(
          atom.displayEndUtf16,
          input.textCodeUnits,
        ),
        1,
      );
      expect(input.nativeHandleCountInRange(0, 0), 1);
      expect(
        input.nativeHandleCountInRange(
          input.textCodeUnits,
          input.textCodeUnits,
        ),
        1,
      );
      expect(
        () => input.nativeHandleCountInRange(
          atom.displayStartUtf16 + 1,
          atom.displayEndUtf16,
        ),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
      expect(
        () => input.nativeHandleCountInRange(0, atom.displayEndUtf16 - 1),
        throwsA(isA<ForumBodyTextPageSurfaceException>()),
      );
      expect(() => input.nativeHandleCountInRange(-1, 0), throwsRangeError);
      expect(f.cache.layoutBuildCount, builds);
      expect(f.cache.activeLeases, 0);
    },
  );
  for (final q in [1, 7, 32]) {
    test(
      'actual page slots seal before otherwise fitting paragraphs and permit both pages q=$q',
      () {
        final f = _open(
          List.filled(3, '<p>${_ruby(2)}</p>').join(),
          pageLimit: 13,
        );
        _finish(f.session, f.cache);
        expect(f.session.snapshot.length, 3);
        final prefix = f.session.snapshot;
        final first = _page(f.session, 0, q);
        final next = _page(f.session, 1, q);
        expect(first.single.nativeLeases.length, 7);
        expect(next.single.nativeLeases.length, 7);
        expect(f.session.activeIssuedLeases, 14);
        expect(f.session.snapshot.first, same(prefix.first));
        for (final p in [...first, ...next]) {
          p.close();
        }
        expect(f.session.activeIssuedLeases, 0);
      },
    );
    test(
      'continuation rows count one parent and their own actual columns q=$q',
      () {
        final f = _open(_ruby(6), pageLimit: 8, width: 60);
        _finish(f.session, f.cache);
        expect(f.session.snapshot.length, 3);
        for (var p = 0; p < 3; p++) {
          final fragments = _page(f.session, p, q);
          expect(fragments.single.nativeLeases.length, 7);
          final fragment = fragments.single as ForumBodyPreparedInlineFragment;
          expect(fragment.view.atomIndices, [p * 4, p * 4 + 1, p * 4 + 2]);
          for (final part in fragments) {
            part.close();
          }
        }
      },
    );
  }
  test('trimmed original huge gap contributes no page request slots', () {
    final f = _open(
      _ruby(2, gapSize: 1000),
      pageLimit: 5,
      width: 40,
      height: 2000,
    );
    _finish(f.session, f.cache);
    expect(f.session.snapshot.length, 1);
    final fragments = _page(f.session, 0, 1);
    final fragment = fragments.single as ForumBodyPreparedInlineFragment;
    expect(fragment.view.atomIndices, [0, 2]);
    expect(fragment.nativeLeases.length, 5);
    for (final part in fragments) {
      part.close();
    }
  });
  test(
    'one indivisible native row over its slot budget preserves published prefix',
    () {
      final f = _open(
        '<p>prefix</p><p>${_ruby(6, ranks: 24)}</p>',
        pageLimit: 256,
        width: 1000,
        height: 1000,
      );
      for (var i = 0; f.session.snapshot.isEmpty && i < 30000; i++) {
        f.session.advance(maxEvents: 1, maxLines: 1);
      }
      final prefix = f.session.snapshot.first;
      expect(
        () => _finish(f.session, f.cache),
        throwsA(
          isA<ForumBodyTextPageException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageFailure.nativeHandleLimit,
          ),
        ),
      );
      expect(f.session.snapshot.first, same(prefix));
      for (final part in _page(f.session, 0, 1)) {
        part.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );
  test(
    'plain paragraphs obey parent slot capacity without repeating spacing',
    () {
      final f = _open('<p>A</p><p>B</p><p>C</p>', pageLimit: 2);
      _finish(f.session, f.cache);
      expect(f.session.snapshot.length, 2);
      expect(f.session.snapshot[0].fragments.length, 2);
      expect(f.session.snapshot[1].fragments.length, 1);
    },
  );
}
