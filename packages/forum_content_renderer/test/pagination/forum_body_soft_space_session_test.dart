import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import '../inline/test_support/ruby_pair_fixture.dart';

({ForumBodyParagraphCache cache, ForumBodyTextPageSession session}) _open(
  String html, {
  double width = 200,
  double height = 1000,
  int entries = 8,
}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 24,
  );
  final session = ForumBodyTextPageSession(
    document: const ForumBodyParser().parse(
      html: html,
      sourceId: 'original-soft-space-session',
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
      maxPages: 1000,
      maxFragments: 10000,
      maxParagraphs: 1000,
      maxTextCodeUnits: 100000,
      maxRuns: 10000,
      maxIssuedLeases: 512,
    ),
    layoutId: 'original-soft-space',
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
    expect(cache.pictureBuildCount, 0);
    expect(step.waitingForLayoutBudget, isFalse);
    expect(step.madeProgress, isTrue);
  }
  expect(session.isComplete, isTrue);
}

List<ForumBodyPreparedTextFragment> _page(
  ForumBodyTextPageSession session,
  ForumBodyParagraphCache cache,
  int page,
  int q,
) {
  final job = session.openPagePreparation(page);
  try {
    for (var i = 0; !job.isReady && i < 30000; i++) {
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      final step = job.advance(maxFragments: 1, maxParts: q);
      expect(step.partsPrepared + step.partsInspected, lessThanOrEqualTo(q));
      expect(
        cache.layoutBuildCount -
            before.$1 +
            cache.pictureBuildCount -
            before.$2,
        lessThanOrEqualTo(1),
      );
      expect(step.waitingForLayoutBudget, isFalse);
      expect(step.madeProgress, isTrue);
    }
    expect(job.isReady, isTrue);
    return job.takeFragments();
  } finally {
    job.close();
  }
}

String _ruby({
  bool baseGap = false,
  bool root = false,
  bool empty = false,
  int ranks = 1,
  bool rtl = false,
}) {
  final rt = '<rt>${empty ? '' : 'x'}</rt> <rt>${empty ? '' : 'y'}</rt>';
  return '<ruby style="direction:${rtl ? 'rtl' : 'ltr'}"><rb>A</rb>${baseGap ? ' ' : ''}<rb>B</rb>'
      '${root ? rt : List.generate(ranks, (_) => '<rtc style="font-size:${ranks > 3 ? 1 : 10}px">$rt</rtc>').join()}'
      '</ruby>';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final q in [1, 7, 32]) {
    for (final rtl in [false, true]) {
      for (final trimmed in [false, true]) {
        for (final sample in [0, 1, 2, 3, 4]) {
          test(
            'PUBLIC Session original breakable gap q=$q rtl=$rtl trimmed=$trimmed sample=$sample',
            () {
              final f = _open(
                _ruby(
                  baseGap: sample != 0,
                  root: sample == 1,
                  empty: sample == 2,
                  ranks: sample == 4
                      ? 80
                      : sample == 3
                      ? 3
                      : 1,
                  rtl: rtl,
                ),
                width: trimmed ? 40 : 200,
                entries: sample == 4 ? 5 : 3,
              );
              _finish(f.session, f.cache);
              expect(f.session.snapshot.length, 1);
              final fragments = _page(f.session, f.cache, 0, q);
              try {
                final fragment =
                    fragments.single as ForumBodyPreparedInlineFragment;
                expect(fragment.view.atomIndices, trimmed ? [0, 2] : [0, 1, 2]);
                final visibleMembers =
                    2 +
                    (sample == 2 ? 0 : 2) +
                    (trimmed ? 0 : 1 + (sample == 0 ? 0 : 1));
                expect(fragment.nativeLeases.length, visibleMembers + 1);
                for (final window in fragment.view.content.contexts) {
                  final text = window.content.projection.text;
                  final boxes = fragment.glyphBoxes(
                    window.startUtf16,
                    window.endUtf16,
                  );
                  if (text.isEmpty || (trimmed && text == ' ')) {
                    expect(boxes, isEmpty);
                    continue;
                  }
                  expect(boxes, isNotEmpty);
                  final box = boxes.first;
                  final hit = fragment.view.sourceAt(
                    Offset(
                      box.direction == TextDirection.rtl
                          ? box.right - .001
                          : box.left + .001,
                      (box.top + box.bottom) / 2,
                    ),
                  );
                  expect(
                    hit.sourceRune,
                    window.content.projection.sourceAtUtf16(0).sourceRune,
                  );
                  // A column-major display boundary can join nonadjacent
                  // original source windows. Preserve that explicit ambiguity.
                  expect(
                    hit.isExact,
                    fragment.view.content.projection.display
                        .sourceAtUtf16(window.startUtf16)
                        .isExact,
                  );
                }
              } finally {
                for (final fragment in fragments) {
                  fragment.close();
                }
              }
              expect(f.session.activeIssuedLeases, 0);
              expect(f.cache.activeLeases, 0);
              final builds = (
                f.cache.layoutBuildCount,
                f.cache.pictureBuildCount,
              );
              for (final fragment in _page(f.session, f.cache, 0, q)) {
                fragment.close();
              }
              expect((
                f.cache.layoutBuildCount,
                f.cache.pictureBuildCount,
              ), builds);
            },
          );
        }
      }
    }
  }

  test(
    'actual CJK LF fence and later visible edge retain original beforeColumn and Unicode source',
    () {
      final f = _open(
        '<ruby><rb>a\u0301</rb><rb>😀</rb><rb>C</rb><rtc><rt>漢</rt>\n<rt>字</rt> <rt>終</rt></rtc></ruby>',
      );
      _finish(f.session, f.cache);
      final fragments = _page(f.session, f.cache, 0, 1);
      final fragment = fragments.single as ForumBodyPreparedInlineFragment;
      expect(fragment.projection.text, 'a\u0301漢😀字 C終');
      expect(fragment.view.atomIndices, [0, 1, 2, 3]);
      for (final window in fragment.view.content.contexts) {
        if (window.content.projection.text.isEmpty) {
          expect(
            fragment.glyphBoxes(window.startUtf16, window.endUtf16),
            isEmpty,
          );
        } else {
          final box = fragment
              .glyphBoxes(window.startUtf16, window.endUtf16)
              .first;
          expect(
            fragment.view
                .sourceAt(Offset(box.left + .001, (box.top + box.bottom) / 2))
                .sourceRune,
            window.content.projection.sourceAtUtf16(0).sourceRune,
          );
        }
      }
      for (final fragment in fragments) {
        fragment.close();
      }
    },
  );

  test(
    'two physical pages omit trimmed gap and expose only their actual column',
    () {
      final f = _open(_ruby(baseGap: true), width: 40, height: 30, entries: 2);
      _finish(f.session, f.cache);
      expect(f.session.snapshot.length, 2);
      for (var page = 0; page < 2; page++) {
        final fragments = _page(f.session, f.cache, page, 1);
        final fragment = fragments.single as ForumBodyPreparedInlineFragment;
        expect(fragment.view.atomIndices, [page * 2]);
        expect(fragment.nativeLeases.length, 3);
        for (final fragment in fragments) {
          fragment.close();
        }
        expect(f.cache.activeLeases, 0);
      }
    },
  );

  test(
    'full foreign native budget waits and resumes the same original gap format',
    () {
      final f = _open(_ruby(baseGap: true), entries: 2);
      final one = f.cache.acquire(
        content: rubyPairInput(base: 'foreign-one').base,
        width: 100,
      );
      final two = f.cache.acquire(
        content: rubyPairInput(base: 'foreign-two').base,
        width: 100,
      );
      addTearDown(one.release);
      addTearDown(two.release);
      var waiting = false;
      for (var i = 0; !waiting && i < 1000; i++) {
        waiting = f.session
            .advance(maxEvents: 1, maxLines: 1)
            .waitingForLayoutBudget;
      }
      expect(waiting, isTrue);
      final builds = f.cache.layoutBuildCount;
      for (var i = 0; i < 3; i++) {
        final step = f.session.advance(maxEvents: 1, maxLines: 1);
        expect(step.waitingForLayoutBudget, isTrue);
        expect(step.madeProgress, isFalse);
        expect(f.cache.layoutBuildCount, builds);
      }
      one.release();
      _finish(f.session, f.cache);
      expect(two.isActive, isTrue);
      f.session.close();
      expect(two.isActive, isTrue);
      two.release();
    },
  );

  test('oversized original gap row preserves an already published prefix', () {
    final f = _open('<p>prefix</p><p>${_ruby()}</p>', height: 20);
    for (var i = 0; f.session.snapshot.isEmpty && i < 10000; i++) {
      f.session.advance(maxEvents: 1, maxLines: 1);
    }
    final prefix = f.session.snapshot.single;
    expect(
      () => _finish(f.session, f.cache),
      throwsA(
        isA<ForumBodyTextPageException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyTextPageFailure.oversizedGroup,
        ),
      ),
    );
    expect(f.session.snapshot.single, same(prefix));
    for (final fragment in _page(f.session, f.cache, 0, 1)) {
      fragment.close();
    }
    expect(f.cache.activeLeases, 0);
  });

  for (final base in ['', 'A', ' A ']) {
    test(
      'actual orphan annotation gap keeps missing base separate and omitted outer whitespace source ($base)',
      () {
        final f = _open('<ruby>$base<rt>x</rt> <rt>y</rt></ruby>', entries: 4);
        _finish(f.session, f.cache);
        final fragments = _page(f.session, f.cache, 0, 1);
        try {
          final fragment = fragments.single as ForumBodyPreparedInlineFragment;
          expect(fragment.view.atomIndices, [0, 1, 2]);
          expect(fragment.nativeLeases.length, 6);
          final gap = fragment.view.content.contexts.singleWhere(
            (w) =>
                w.content.projection.text == ' ' &&
                w.content.projection.sourceAtUtf16(0).sourceRune ==
                    base.length + 1,
          );
          expect(fragment.glyphBoxes(gap.startUtf16, gap.endUtf16), isNotEmpty);
          expect(fragment.projection.text, base.isEmpty ? 'x y' : 'Ax y');
        } finally {
          for (final fragment in fragments) {
            fragment.close();
          }
        }
        expect(f.cache.activeLeases, 0);
      },
    );
  }

  test('cancel actual raw-gap format retires metrics before publication', () {
    final f = _open(_ruby(baseGap: true, ranks: 80), entries: 1);
    for (var i = 0; f.cache.layoutBuildCount == 0 && i < 10000; i++) {
      f.session.advance(maxEvents: 1, maxLines: 1);
    }
    expect(f.cache.layoutBuildCount, 1);
    expect(f.session.snapshot, isEmpty);
    f.session.close();
    f.cache.close();
    expect(f.cache.activeLeases, 0);
  });
}
