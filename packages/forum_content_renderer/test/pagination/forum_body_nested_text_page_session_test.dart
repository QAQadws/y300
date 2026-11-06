import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class _Fixture {
  _Fixture(
    String html, {
    double width = 100,
    double height = 100,
    TextScaler scaler = TextScaler.noScaling,
    TextDirection direction = TextDirection.ltr,
    int maxText = 100000,
    int maxRuns = 10000,
    int maxIssued = 512,
    int cacheEntries = 64,
    int? pageEntries,
    int cacheBytes = 1 << 24,
    int? pageBytes,
    ForumBodyParagraphCache? sharedCache,
  }) {
    final document = const ForumBodyParser().parse(
      html: html,
      sourceId: 'formal-nested-session',
      conversionIdentity: 'none',
    );
    cache =
        sharedCache ??
        ForumBodyParagraphCache(
          maxEntries: cacheEntries,
          maxEstimatedBytes: cacheBytes,
        );
    session = ForumBodyTextPageSession(
      document: document,
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
        fontRevision: 'nested-ahem',
        linkColor: const Color(0xff0000ff),
        paragraphBefore: 0,
        paragraphAfter: 0,
        textDirection: direction,
      ),
      cache: cache,
      limits: ForumBodyTextPageSessionLimits(
        maxPages: 1000,
        maxFragments: 10000,
        maxParagraphs: 10000,
        maxTextCodeUnits: maxText,
        maxRuns: maxRuns,
        maxIssuedLeases: maxIssued,
      ),
      layoutId: 'formal-nested',
      width: width,
      height: height,
      textScaler: scaler,
      maxNativeEntriesPerPage: pageEntries,
      maxNativeEstimatedBytesPerPage: pageBytes,
    );
    addTearDown(() {
      session.close();
      cache.close();
    });
  }

  late final ForumBodyParagraphCache cache;
  late final ForumBodyTextPageSession session;
  void finish() {
    for (var calls = 0; !session.isComplete && calls < 10000; calls++) {
      final step = session.advance(maxEvents: 1, maxLines: 1);
      expect(step.layoutsBuilt, lessThanOrEqualTo(1));
      expect(step.formatUnitsPrepared, lessThanOrEqualTo(32));
      expect(step.madeProgress, isTrue);
      expect(step.waitingForLayoutBudget, isFalse);
    }
    expect(session.isComplete, isTrue);
  }

  List<ForumBodyPreparedTextFragment> prepare(int page) {
    final job = session.openPagePreparation(page);
    try {
      for (var calls = 0; !job.isReady && calls < 10000; calls++) {
        final step = job.advance(maxParts: 1, maxFragments: 1);
        expect(step.layoutsBuilt + step.picturesBuilt, lessThanOrEqualTo(1));
        expect(step.waitingForLayoutBudget, isFalse);
      }
      return job.takeFragments();
    } finally {
      job.close();
    }
  }
}

Future<List<int>> _pixels(void Function(Canvas) paint, int ratio) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder)..scale(ratio.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(100 * ratio, 160 * ratio);
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List().toList();
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });

  test(
    'actual entry budget seals native rows before dense adjacent pages starve',
    () {
      final html = [
        for (final note in 'abcdefghijkl'.split(''))
          '<p><ruby><rb>L<ruby>A<rt>x</rt></ruby>R</rb><rt>$note</rt></ruby></p>',
      ].join();
      final unrestricted = _Fixture(html, height: 600)..finish();
      expect(unrestricted.session.snapshot, hasLength(1));
      final f = _Fixture(
        html,
        width: 100,
        height: 600,
        cacheEntries: 10,
        pageEntries: 4,
      );
      f.finish();
      expect(f.session.snapshot.length, greaterThan(1));
      List<ForumBodyPreparedTextFragment> previous = [];
      try {
        for (var page = 0; page < f.session.snapshot.length; page++) {
          final current = f.prepare(page);
          expect(current.every((fragment) => fragment.isActive), isTrue);
          expect(previous.every((fragment) => fragment.isActive), isTrue);
          expect(f.cache.entryCount, lessThanOrEqualTo(10));
          validateForumBodyPreparedTextPageBinding(
            snapshot: f.session.snapshot,
            pageIndex: page,
            layoutId: 'formal-nested',
            fragments: current,
          );
          for (final fragment in previous) {
            fragment.close();
          }
          previous = current;
        }
      } finally {
        for (final fragment in previous) {
          fragment.close();
        }
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test('byte admission seals mixed rows so actual adjacent pages coexist', () {
    final html = List.filled(
      24,
      '<p><ruby><rb>L<ruby>A<rt>x</rt></ruby>R</rb><rt>z</rt></ruby></p>',
    ).join();
    final f = _Fixture(
      html,
      width: 120,
      height: 1000,
      cacheBytes: 200000,
      pageBytes: 60000,
    );
    f.finish();
    expect(f.session.snapshot.length, greaterThan(2));
    final prefix = f.session.snapshot.first;
    List<ForumBodyPreparedTextFragment> previous = [];
    try {
      for (var p = 0; p < f.session.snapshot.length; p++) {
        final current = f.prepare(p);
        expect(current.every((v) => v.isActive), isTrue);
        expect(previous.every((v) => v.isActive), isTrue);
        expect(f.cache.estimatedRetainedBytes, lessThanOrEqualTo(200000));
        validateForumBodyPreparedTextPageBinding(
          snapshot: f.session.snapshot,
          pageIndex: p,
          layoutId: 'formal-nested',
          fragments: current,
        );
        for (final old in previous) {
          old.close();
        }
        previous = current;
      }
    } finally {
      for (final old in previous) {
        old.close();
      }
    }
    expect(f.cache.activeLeases, 0);
    expect(f.session.snapshot.first, same(prefix));
    final replay = _Fixture(
      html,
      width: 120,
      height: 1000,
      pageBytes: 60000,
      sharedCache: f.cache,
    );
    replay.finish();
    Object partitions(_Fixture value) => [
      for (final p in value.session.snapshot)
        [
          for (final fragment in p.fragments)
            (fragment.paragraphIndex, fragment.startLine, fragment.endLine),
        ],
    ];
    expect(partitions(replay), partitions(f));
  });

  test(
    'byte cost deduplicates the entire shared band across repeated rows',
    () {
      final f = _Fixture(
        List.filled(12, '<ruby>A<rt>x</rt></ruby>').join(),
        width: 100,
        height: 1000,
        pageBytes: 200000,
      );
      f.finish();
      expect(f.session.snapshot, hasLength(1));
      f.cache.clearUnpinned();
      final current = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(current.nativeLeases, hasLength(25));
        expect(f.cache.entryCount, 2);
      } finally {
        current.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'ordinary native paragraphs obey the same byte seal and pair budget',
    () {
      final f = _Fixture(
        List.filled(6, '<p>${'A' * 1000}</p>').join(),
        width: 1000,
        height: 1000,
        cacheBytes: 500000,
        pageBytes: 140000,
      );
      f.finish();
      expect(f.session.snapshot, hasLength(6));
      var previous = f.prepare(0);
      try {
        for (var p = 1; p < 6; p++) {
          final next = f.prepare(p);
          expect(previous.every((v) => v.isActive), isTrue);
          for (final old in previous) {
            old.close();
          }
          previous = next;
        }
      } finally {
        for (final old in previous) {
          old.close();
        }
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'overflowing fractional fonts keep the existing aggregate cache budget',
    () {
      final f = _Fixture(
        '<p style="font-size:2px">${'A' * 1000}</p>',
        width: 100,
        height: 1000,
        cacheBytes: 500000,
      );
      // The natural 2px native rows round differently from their font boxes.
      // Complete row paint needs more resources than the ordinary font alone.
      expect(f.finish, throwsA(isA<ForumBodyParagraphBudgetException>()));
      expect(f.cache.layoutBuildCount, 1);
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'indivisible native rows fail the explicit byte cap without a fake page',
    () {
      final f = _Fixture(
        '<ruby><rb>L<ruby>A<rt>x</rt></ruby>R</rb><rt>z</rt></ruby>',
        pageBytes: 1,
      );
      expect(
        f.finish,
        throwsA(
          isA<ForumBodyTextPageException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageFailure.nativeByteLimit,
          ),
        ),
      );
      expect(f.session.snapshot, isEmpty);
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'shared band deduplicates actual keys without lowering logical handle limits',
    () {
      final f = _Fixture(
        List.filled(12, '<ruby>A<rt>x</rt></ruby>').join(),
        width: 100,
        height: 600,
        pageEntries: 2,
      );
      f.finish();
      expect(f.session.snapshot, hasLength(1));
      f.cache.clearUnpinned();
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(prepared.nativeLeases, hasLength(25));
        expect(f.cache.entryCount, 2);
      } finally {
        prepared.close();
      }
    },
  );

  test(
    'an indivisible native group cannot exceed its explicit entry budget',
    () {
      final f = _Fixture(
        '<ruby><rb>L<ruby>A<rt>x</rt></ruby>R</rb><rt>z</rt></ruby>',
        pageEntries: 1,
      );
      expect(
        f.finish,
        throwsA(
          isA<ForumBodyTextPageException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyTextPageFailure.nativeEntryLimit,
          ),
        ),
      );
      expect(f.session.snapshot, isEmpty);
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'retirement while indexing real request keys releases its pending parent',
    () {
      late final _Fixture f;
      var retiredWhilePinned = false;
      f = _Fixture(
        '<ruby>A<rt>x</rt></ruby>',
        pageEntries: 4,
        scaler: _CallbackScaler((size) {
          if (f.cache.activeLeases != 0) {
            retiredWhilePinned = true;
            f.session.close();
          }
          return size;
        }),
      );
      expect(f.finish, throwsStateError);
      expect(retiredWhilePinned, isTrue);
      expect(f.session.state, ForumBodyTextPageSessionState.closed);
      expect(f.cache.activeLeases, 0);
      expect(f.session.snapshot, isEmpty);
    },
  );

  for (final direction in TextDirection.values) {
    for (final ratio in [1, 3]) {
      test(
        'nested input paginates and paints as single-level ruby $direction DPR$ratio',
        () async {
          const root = '<ruby style="background:rgba(255,0,0,.2)">';
          const baseStyle = 'font-size:16px;color:red';
          const text = '<span style="background:yellow">A</span>';
          const note = '<rt style="font-size:10px;color:blue">z</rt>';
          const nested =
              '$root<rb>L<ruby style="$baseStyle">'
              '$text<rt>omit</rt></ruby>R</rb>$note</ruby>';
          const flat =
              '$root<rb>L<span style="$baseStyle">$text</span>R</rb>$note</ruby>';
          _Fixture fixture(String ruby) => _Fixture(
            List.filled(5, '<p>P${ruby}Q</p>').join(),
            width: 95,
            height: 65,
            direction: direction,
          )..finish();
          final authored = fixture(nested);
          final explicit = fixture(flat);
          expect(authored.session.snapshot.length, greaterThan(1));
          expect(
            authored.session.snapshot.length,
            explicit.session.snapshot.length,
          );
          final visible = StringBuffer();

          for (var page = 0; page < authored.session.snapshot.length; page++) {
            final actual = authored.prepare(page);
            final expected = explicit.prepare(page);
            try {
              expect(actual, hasLength(expected.length));
              for (final (i, fragment) in actual.indexed) {
                final a = fragment as ForumBodyPreparedInlineFragment;
                final b = expected[i] as ForumBodyPreparedInlineFragment;
                visible.write(a.projection.text);
                expect(a.projection.text, b.projection.text);
                expect(
                  a.nativeLeases.whereType<ForumBodyInlineParagraphLease>(),
                  hasLength(1),
                );
                expect(a.nativeLeases, hasLength(b.nativeLeases.length));
                expect(
                  await _pixels(
                    (canvas) => a.view.paint(canvas, Offset.zero),
                    ratio,
                  ),
                  await _pixels(
                    (canvas) => b.view.paint(canvas, Offset.zero),
                    ratio,
                  ),
                );
              }
            } finally {
              for (final fragment in [...actual, ...expected]) {
                fragment.close();
              }
            }
          }
          expect(visible.toString(), 'PLARzQ' * 5);
          expect(authored.cache.activeLeases, 0);
          expect(explicit.cache.activeLeases, 0);
        },
      );
    }
  }

  test(
    'multi-column source, numeric and visible cancellation retires partial work',
    () {
      const html =
          '<ruby><rb>L<ruby>A<rt>x</rt></ruby>R</rb>\n<rb>B</rb>'
          '<rtc>shared</rtc><rtc style="ruby-position:under"><rt>u</rt> <rt>v</rt></rtc></ruby>';
      for (final cancelAfter in [1, 5, 30, 60, 120, 240, 480]) {
        final f = _Fixture(html, width: 300);
        for (var i = 0; i < cancelAfter && !f.session.isComplete; i++) {
          f.session.advance(maxEvents: 1, maxLines: 1);
        }
        f.session.close();
        expect(f.cache.activeLeases, 0);
        final builds = f.cache.layoutBuildCount;
        expect(
          () => f.session.advance(maxEvents: 1, maxLines: 1),
          throwsStateError,
        );
        expect(f.cache.layoutBuildCount, builds);
      }
      for (final cancelAfter in [1, 5, 30, 60, 120]) {
        final f = _Fixture(html, width: 300);
        f.finish();
        final job = f.session.openPagePreparation(0);
        for (var i = 0; i < cancelAfter && !job.isReady; i++) {
          job.advance(maxParts: 1, maxFragments: 1);
        }
        f.session.close();
        expect(
          () => job.advance(maxParts: 1, maxFragments: 1),
          throwsStateError,
        );
        expect(f.cache.activeLeases, 0);
        job.close();
      }
    },
  );

  test(
    'retirement during retained annotation scaling cannot publish a late row',
    () {
      late final _Fixture f;
      f = _Fixture(
        '<ruby><rb>L<ruby>A<rt style="font-size:10px">x</rt></ruby>R</rb>'
        '<rt style="font-size:8px">z</rt></ruby>',
        scaler: _CallbackScaler((size) {
          expect(size, isNot(10));
          if (size == 8) f.session.close();
          return size;
        }),
      );
      expect(f.finish, throwsStateError);
      expect(f.session.state, ForumBodyTextPageSessionState.closed);
      expect(f.session.snapshot, isEmpty);
      expect(f.cache.activeLeases, 0);
    },
  );

  test('nested retained counts fail before any native shape', () {
    for (final textLimit in [false, true]) {
      final f = _Fixture(
        '<ruby><rb><ruby>AB<rt>xy</rt></ruby></rb><rt>zz</rt></ruby>',
        maxText: textLimit ? 2 : 100000,
        maxRuns: textLimit ? 10000 : 1,
      );
      expect(
        () {
          for (var count = 0; count < 10000 && !f.session.isComplete; count++) {
            f.session.advance(maxEvents: 1, maxLines: 1);
          }
        },
        throwsA(
          isA<ForumBodyTextPageSessionException>().having(
            (e) => e.failure,
            'failure',
            textLimit
                ? ForumBodyTextPageSessionFailure.textLimit
                : ForumBodyTextPageSessionFailure.runLimit,
          ),
        ),
      );
      expect(f.cache.layoutBuildCount, 0);
      expect(f.cache.activeLeases, 0);
    }
  });

  test(
    'closing during cooperative source preparation admits no late native work',
    () {
      var html = 'A';
      for (var depth = 0; depth < 30; depth++) {
        html =
            '<ruby style="font-size:20px"><rb>$html</rb><rt style="font-size:1px">x</rt></ruby>';
      }
      final f = _Fixture(html);
      for (var count = 0; count < 20; count++) {
        final step = f.session.advance(maxEvents: 1, maxLines: 1);
        expect(step.madeProgress, isTrue);
      }
      expect(f.session.snapshot, isEmpty);
      expect(f.cache.layoutBuildCount, 0);
      f.session.close();
      expect(f.cache.activeLeases, 0);
      expect(
        () => f.session.advance(maxEvents: 1, maxLines: 1),
        throwsStateError,
      );
      expect(f.cache.layoutBuildCount, 0);
    },
  );

  test(
    'closing during visible ruby preparation retires the borrowed leases',
    () {
      final f = _Fixture(
        '<ruby><rb><ruby>AB<rt>xy</rt></ruby></rb><rt>zz</rt></ruby>',
      );
      f.finish();
      final job = f.session.openPagePreparation(0);
      for (var count = 0; f.cache.activeLeases < 2 && count < 10000; count++) {
        job.advance(maxParts: 1, maxFragments: 1);
      }
      expect(f.cache.activeLeases, greaterThanOrEqualTo(2));
      f.session.close();
      expect(f.cache.activeLeases, 0);
      expect(() => job.advance(maxFragments: 1, maxParts: 1), throwsStateError);
      job.close();
    },
  );
}

final class _CallbackScaler extends TextScaler {
  const _CallbackScaler(this.callback);
  final double Function(double) callback;
  @override
  double scale(double fontSize) => callback(fontSize);
  @override
  double get textScaleFactor => scale(20) / 20;
}
