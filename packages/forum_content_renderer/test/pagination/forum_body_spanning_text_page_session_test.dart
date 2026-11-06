import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
  fontRevision: 'ahem',
  linkColor: const Color(0xff0000ff),
  paragraphBefore: 0,
  paragraphAfter: 0,
);

({ForumBodyParagraphCache cache, ForumBodyTextPageSession session}) _open(
  String html, {
  double width = 140,
  double height = 1000,
  int entries = 8,
  TextScaler scaler = TextScaler.noScaling,
}) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'formal-spanning-session',
    conversionIdentity: 'none',
  );
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 24,
  );
  final session = ForumBodyTextPageSession(
    document: document,
    reader: _reader,
    cache: cache,
    limits: const ForumBodyTextPageSessionLimits(
      maxPages: 1000,
      maxFragments: 10000,
      maxParagraphs: 1000,
      maxTextCodeUnits: 100000,
      maxRuns: 10000,
      maxIssuedLeases: 512,
    ),
    layoutId: 'formal-spanning',
    width: width,
    height: height,
    textScaler: scaler,
  );
  addTearDown(() {
    session.close();
    cache.close();
  });
  return (cache: cache, session: session);
}

void _finish(ForumBodyTextPageSession session, ForumBodyParagraphCache cache) {
  for (var i = 0; !session.isComplete && i < 30000; i++) {
    final builds = cache.layoutBuildCount;
    final step = session.advance(maxEvents: 1, maxLines: 1);
    expect(step.formatUnitsPrepared, lessThanOrEqualTo(32));
    expect(cache.layoutBuildCount - builds, lessThanOrEqualTo(1));
    expect(step.waitingForLayoutBudget, isFalse);
    expect(step.madeProgress, isTrue);
    expect(cache.pictureBuildCount, 0);
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

String _ruby({bool dense = false, String direction = 'ltr', String gap = ''}) {
  final moreBases = dense ? '<rb style="font-size:1px">C</rb>' * 80 : '';
  return '<ruby style="direction:$direction"><rb style="font-size:20px">A</rb>'
      '$gap<rb style="font-size:30px">B</rb>$moreBases'
      '<rtc style="font-size:10px">abcdefghij</rtc></ruby>';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final q in [1, 7, 32]) {
    for (final dense in [false, true]) {
      for (final (direction, gap) in [
        for (final direction in ['ltr', 'rtl'])
          for (final gap in ['', ' ']) (direction, gap),
      ]) {
        test(
          'spanning single-level ruby retains original members q=$q dense=$dense $direction gap=${gap.isNotEmpty}',
          () {
            final f = _open(
              '<p dir="$direction">${_ruby(dense: dense, direction: direction, gap: gap)}</p>',
              entries: dense ? 3 : 2,
              width: 160,
            );
            _finish(f.session, f.cache);
            expect(f.session.snapshot.length, 1);
            final fragments = _page(f.session, f.cache, 0, q);
            try {
              final fragment =
                  fragments.single as ForumBodyPreparedInlineFragment;
              expect(fragment.view.atomIndices, [0]);
              final extra = gap.isEmpty ? 0 : 1;
              final handles = dense ? 84 : 4;
              expect(fragment.nativeLeases.length, handles + extra);
              expect(f.cache.pictureBuildCount, dense ? 2 : 1);
              for (final window in fragment.view.content.contexts) {
                final text = window.content.projection.text;
                if (text.isEmpty) continue;
                final from = text.length == 1 ? 0 : 1;
                final box = fragment
                    .glyphBoxes(
                      window.startUtf16 + from,
                      window.startUtf16 + from + 1,
                    )
                    .first;
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
                  window.content.projection.sourceAtUtf16(from).sourceRune,
                  reason: 'text=$text from=$from box=$box',
                );
                expect(hit.isExact, isTrue);
              }
            } finally {
              for (final f in fragments) {
                f.close();
              }
            }
            expect(f.session.activeIssuedLeases, 0);
            expect(f.cache.activeLeases, 0);
            final counts = (
              f.cache.layoutBuildCount,
              f.cache.pictureBuildCount,
            );
            final warm = _page(f.session, f.cache, 0, 1);
            for (final f in warm) {
              f.close();
            }
            expect((
              f.cache.layoutBuildCount,
              f.cache.pictureBuildCount,
            ), counts);
            f.session.close();
            f.cache.close();
            expect(f.cache.estimatedRetainedBytes, 0);
          },
        );
      }
    }
  }

  test(
    'real continuation pages only prepare the one complete visible spanning atom',
    () {
      final f = _open(
        '<p>${'P' * 100}${_ruby()}${'Q' * 100}</p>',
        height: 100,
        entries: 4,
      );
      _finish(f.session, f.cache);
      expect(f.session.snapshot.length, greaterThan(2));
      var atomicPages = 0;
      for (var page = 0; page < f.session.snapshot.length; page++) {
        final fragments = _page(f.session, f.cache, page, 1);
        try {
          for (final fragment
              in fragments.cast<ForumBodyPreparedInlineFragment>()) {
            if (fragment.view.atomIndices.isEmpty) {
              expect(fragment.nativeLeases.length, 1);
            } else {
              atomicPages++;
              expect(fragment.view.atomIndices, [0]);
              expect(fragment.nativeLeases.length, 4);
              final spanStart = fragment.projection.text.indexOf('abcdefghij');
              expect(
                fragment.glyphBoxes(spanStart, spanStart + 10),
                isNotEmpty,
              );
            }
          }
        } finally {
          for (final f in fragments) {
            f.close();
          }
        }
        expect(f.cache.activeLeases, 0);
      }
      expect(atomicPages, 1);
    },
  );

  for (final (left, right) in [('', 'y'), ('x', ''), ('', '')]) {
    test(
      'actual root gap preserves empty RT slots without invented glyphs ($left,$right)',
      () {
        final f = _open(
          '<ruby><rb>A</rb><rb>B</rb><rt>$left</rt> <rt>$right</rt></ruby>',
        );
        _finish(f.session, f.cache);
        final fragments = _page(f.session, f.cache, 0, 1);
        final fragment = fragments.single as ForumBodyPreparedInlineFragment;
        try {
          final nonempty = (left.isEmpty ? 0 : 1) + (right.isEmpty ? 0 : 1);
          expect(fragment.nativeLeases.length, 4 + nonempty);
          expect(f.cache.pictureBuildCount, 1);
          final window = fragment.view.content.contexts.singleWhere(
            (w) => w.content.projection.text == ' ',
          );
          final box = fragment
              .glyphBoxes(window.startUtf16, window.endUtf16)
              .single;
          final hit = fragment.view.sourceAt(
            Offset(box.left + .001, (box.top + box.bottom) / 2),
          );
          expect(hit.isExact, left.isNotEmpty);
          expect(hit.sourceRune, 2 + left.length);
        } finally {
          for (final fragment in fragments) {
            fragment.close();
          }
        }
        expect(f.cache.activeLeases, 0);
      },
    );
  }

  test('orphan fallback does not expose annotations from a second level', () {
    final f = _open(
      '<ruby><rtc>word</rtc><rtc><rt>x</rt><rt>y</rt></rtc></ruby>',
      entries: 3,
    );
    _finish(f.session, f.cache);
    final fragments = _page(f.session, f.cache, 0, 1);
    try {
      final fragment = fragments.single as ForumBodyPreparedInlineFragment;
      expect(fragment.projection.text, 'word');
      expect(fragment.nativeLeases.length, 3);
      expect(f.cache.pictureBuildCount, 1);
    } finally {
      for (final f in fragments) {
        f.close();
      }
    }
    expect(f.cache.activeLeases, 0);
  });

  test(
    'cancel during actual spanning metrics retires the only current native work',
    () {
      final f = _open(_ruby(dense: true), entries: 3);
      for (var i = 0; f.cache.layoutBuildCount == 0 && i < 10000; i++) {
        f.session.advance(maxEvents: 1, maxLines: 1);
      }
      expect(f.cache.layoutBuildCount, 1);
      expect(f.session.snapshot, isEmpty);
      f.session.close();
      f.cache.close();
      expect(f.cache.activeLeases, 0);
      expect(f.cache.estimatedRetainedBytes, 0);
    },
  );

  test(
    'late over-wide component cannot replace or partially append a committed prefix',
    () {
      final f = _open(
        '<p>prefix</p><p>${_ruby()}</p>',
        width: 60,
        height: 20,
        entries: 4,
      );
      for (var i = 0; f.session.snapshot.isEmpty && i < 10000; i++) {
        f.session.advance(maxEvents: 1, maxLines: 1);
      }
      final prefix = f.session.snapshot.first;
      expect(
        () => _finish(f.session, f.cache),
        throwsA(isA<ForumBodyRubyGroupException>()),
      );
      expect(f.session.snapshot.first, same(prefix));
      final fragments = _page(f.session, f.cache, 0, 1);
      for (final fragment in fragments) {
        fragment.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'raw spanning Unicode preserves actual grapheme and semantic coordinates',
    () {
      final f = _open('<ruby><rb>a\u0301</rb><rb>😀</rb><rtc>漢字</rtc></ruby>');
      _finish(f.session, f.cache);
      final fragments = _page(f.session, f.cache, 0, 1);
      try {
        final fragment = fragments.single as ForumBodyPreparedInlineFragment;
        expect(fragment.projection.text, 'a\u0301😀漢字');
        expect(fragment.nativeLeases.length, 4);
        for (final window in fragment.view.content.contexts) {
          final box = fragment
              .glyphBoxes(window.startUtf16, window.endUtf16)
              .first;
          final hit = fragment.view.sourceAt(
            Offset(box.left + .001, (box.top + box.bottom) / 2),
          );
          expect(
            hit.sourceRune,
            window.content.projection.sourceAtUtf16(0).sourceRune,
          );
          expect(hit.isExact, isTrue);
        }
      } finally {
        for (final f in fragments) {
          f.close();
        }
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'preserved annotation gap remains explicit failure after a published prefix',
    () {
      final f = _open(
        '<p>prefix</p><p><ruby><rb>A</rb><rb>B</rb><rtc style="white-space:pre"><rt>x</rt> <rt>y</rt></rtc></ruby></p>',
        height: 20,
      );
      for (var i = 0; f.session.snapshot.isEmpty && i < 10000; i++) {
        f.session.advance(maxEvents: 1, maxLines: 1);
      }
      final prefix = f.session.snapshot.first;
      final shapes = f.cache.layoutBuildCount;
      expect(
        () => _finish(f.session, f.cache),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
      expect(f.session.snapshot.first, same(prefix));
      expect(f.cache.layoutBuildCount, shapes);
      expect(f.cache.activeLeases, 0);
      final fragments = _page(f.session, f.cache, 0, 1);
      for (final fragment in fragments) {
        fragment.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );
}
