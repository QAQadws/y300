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
      final f = _Fixture(
        List.filled(
          12,
          '<ruby><rb>L<ruby>A<rt>x</rt></ruby>R</rb><rt>z</rt></ruby>',
        ).join(),
        width: 100,
        height: 600,
        cacheEntries: 10,
        pageEntries: 4,
      );
      f.finish();
      expect(f.session.snapshot.length, greaterThan(1));
      ForumBodyPreparedTextFragment? previous;
      try {
        for (var page = 0; page < f.session.snapshot.length; page++) {
          final current = f.prepare(page).single;
          expect(current.isActive, isTrue);
          expect(previous?.isActive ?? true, isTrue);
          expect(f.cache.entryCount, lessThanOrEqualTo(10));
          validateForumBodyPreparedTextPageBinding(
            snapshot: f.session.snapshot,
            pageIndex: page,
            layoutId: 'formal-nested',
            fragments: [current],
          );
          previous?.close();
          previous = current;
        }
      } finally {
        previous?.close();
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
        List.filled(6, '<p style="font-size:2px">${'A' * 1000}</p>').join(),
        width: 100,
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

  for (final ratio in [1, 3]) {
    for (final backgrounds in [false, true]) {
      test(
        'formal mixed parent paints once and binds every source DPR$ratio backgrounds=$backgrounds',
        () async {
          final f = _Fixture(
            '<ruby style="color:red;${backgrounds ? 'background:rgba(255,0,0,.2)' : ''}">'
            '<rb>L'
            '<ruby style="${backgrounds ? 'background:rgba(0,255,0,.4)' : ''}">A'
            '<rt style="font-size:10px;color:blue">x</rt></ruby>R</rb>'
            '<rt style="font-size:10px;color:green">z</rt></ruby>',
          );
          f.finish();
          final job = f.session.openPagePreparation(0);
          expect(job.expectedNativeLeaseCount, 5);
          job.close();
          final prepared =
              f.prepare(0).single as ForumBodyPreparedInlineFragment;
          final painters = <TextPainter>[];
          try {
            expect(prepared.projection.text, 'LAxRz');
            expect(prepared.nativeLeases, hasLength(5));
            expect(
              prepared.nativeLeases.whereType<ForumBodyInlineParagraphLease>(),
              hasLength(2),
            );
            expect(
              prepared.nativeLeases.whereType<ForumBodyTextLease>().map(
                (l) => l.content.projection.text,
              ),
              unorderedEquals(['A', 'x', 'z']),
            );
            for (final (text, size, color) in [
              ('LAR', 20.0, const Color(0xffff0000)),
              ('x', 10.0, const Color(0xff0000ff)),
              ('z', 10.0, const Color(0xff008000)),
            ]) {
              painters.add(
                TextPainter(
                  text: TextSpan(
                    text: text,
                    style: TextStyle(
                      fontFamily: 'Ahem',
                      fontSize: size,
                      height: 1,
                      color: color,
                    ),
                  ),
                  textDirection: TextDirection.ltr,
                )..layout(),
              );
            }
            final actual = await _pixels(
              (canvas) => prepared.view.paint(canvas, Offset.zero),
              ratio,
            );
            if (backgrounds) {
              expect(prepared.view.containerBackgrounds, [
                (
                  rect: const Rect.fromLTWH(0, 20, 60, 20),
                  color: const Color(0x33ff0000),
                ),
                (
                  rect: const Rect.fromLTWH(20, 20, 20, 20),
                  color: const Color(0x6600ff00),
                ),
              ]);
            }
            final expected = await _pixels((canvas) {
              if (backgrounds) {
                for (final (rect, color) in [
                  (const Rect.fromLTWH(0, 20, 60, 20), const Color(0x33ff0000)),
                  (
                    const Rect.fromLTWH(20, 20, 20, 20),
                    const Color(0x6600ff00),
                  ),
                ]) {
                  canvas.drawRect(rect, Paint()..color = color);
                }
              }
              painters[0].paint(canvas, const Offset(0, 20));
              painters[1].paint(canvas, const Offset(25, 10));
              painters[2].paint(canvas, const Offset(25, 0));
            }, ratio);
            expect(actual, expected);
            if (backgrounds) {
              expect(prepared.view.containerBackgrounds, hasLength(2));
              final surfaces = await _pixels(
                (canvas) => prepared.view.paintContainerBackgrounds(
                  canvas,
                  Offset.zero,
                ),
                ratio,
              );
              final reference = await _pixels((canvas) {
                canvas.drawRect(
                  const Rect.fromLTWH(0, 20, 60, 20),
                  Paint()..color = const Color(0x33ff0000),
                );
                canvas.drawRect(
                  const Rect.fromLTWH(20, 20, 20, 20),
                  Paint()..color = const Color(0x6600ff00),
                );
              }, ratio);
              expect(surfaces, reference);
            }
            final builds = f.cache.layoutBuildCount;
            final pictures = f.cache.pictureBuildCount;
            for (
              var start = 0;
              start < prepared.projection.text.length;
              start++
            ) {
              final box = prepared.glyphBoxes(start, start + 1).single;
              final hit = prepared.view.sourceAt(
                Offset(box.left + .1, box.toRect().center.dy),
              );
              expect(hit.isExact, isTrue);
              expect(
                hit.sourceRune,
                prepared.projection.sourceAtUtf16(start).sourceRune,
              );
              expect(hit.displayUtf16, start);
            }
            expect(f.cache.layoutBuildCount, builds);
            expect(f.cache.pictureBuildCount, pictures);
          } finally {
            prepared.close();
            for (final painter in painters) {
              painter.dispose();
            }
          }
          expect(f.cache.activeLeases, 0);
        },
      );
    }
  }

  for (final direction in TextDirection.values) {
    for (final ratio in [1, 3]) {
      test(
        'actual outer span and under rank share original columns $direction DPR$ratio',
        () async {
          final f = _Fixture(
            '<ruby style="color:red"><rb><ruby>A<rt style="font-size:10px;color:blue">x</rt></ruby></rb>'
            '<rb>B</rb><rtc style="font-size:8px;color:green">uvwxyz</rtc>'
            '<rtc style="font-size:6px;color:orange;ruby-position:under">pq</rtc></ruby>',
            width: 100,
            direction: direction,
          );
          f.finish();
          final prepared =
              f.prepare(0).single as ForumBodyPreparedInlineFragment;
          final painters = <TextPainter>[];
          try {
            expect(prepared.projection.text, 'AxBuvwxyzpq');
            expect(prepared.nativeLeases, hasLength(6));
            final parent =
                prepared.nativeLeases.first as ForumBodyInlineParagraphLease;
            final origin = parent.layout.atomBoxes.single.toRect().topLeft;
            // The real 48px anonymous span allocates 24px per column. The 12px
            // under annotation shares both columns without widening either one.
            final a = direction == TextDirection.ltr ? 2.0 : 26.0;
            final b = direction == TextDirection.ltr ? 26.0 : 2.0;
            final expected = [
              ('A', 20.0, const Color(0xffff0000), Offset(a, 18)),
              ('x', 10.0, const Color(0xff0000ff), Offset(a + 5, 8)),
              ('B', 20.0, const Color(0xffff0000), Offset(b, 18)),
              ('uvwxyz', 8.0, const Color(0xff008000), Offset.zero),
              ('pq', 6.0, const Color(0xffffa500), const Offset(18, 38)),
            ];
            for (final (text, size, color, _) in expected) {
              painters.add(
                TextPainter(
                  text: TextSpan(
                    text: text,
                    style: TextStyle(
                      fontFamily: 'Ahem',
                      fontSize: size,
                      height: 1,
                      color: color,
                    ),
                  ),
                  textDirection: direction,
                )..layout(),
              );
            }
            final actual = await _pixels(
              (canvas) => prepared.view.paint(canvas, Offset.zero),
              ratio,
            );
            final reference = await _pixels((canvas) {
              // The visible parent clips ink to its independently known 44px
              // line frame, including tiny-font descender rounding at the edge.
              canvas.clipRect(
                const Rect.fromLTWH(0, 0, 100, 44),
                doAntiAlias: false,
              );
              for (final (i, item) in expected.indexed) {
                painters[i].paint(canvas, origin + item.$4);
              }
            }, ratio);
            expect(actual, reference);
            for (var i = 0; i < prepared.projection.text.length; i++) {
              final box = prepared.glyphBoxes(i, i + 1).single;
              final hit = prepared.view.sourceAt(
                Offset(box.left + .1, box.toRect().center.dy),
              );
              expect(hit.displayUtf16, i);
              expect(
                hit.sourceRune,
                prepared.projection.sourceAtUtf16(i).sourceRune,
              );
            }
          } finally {
            prepared.close();
            for (final painter in painters) {
              painter.dispose();
            }
          }
          expect(f.cache.activeLeases, 0);
        },
      );
    }
    for (final ratio in [1, 3]) {
      test(
        'outer original columns position nested children $direction DPR$ratio',
        () async {
          final f = _Fixture(
            '<ruby style="color:red"><rb><ruby>A<rt style="font-size:10px;color:blue">x</rt></ruby></rb>'
            '<rb>B</rb><rtc style="font-size:8px;color:green"><rt>a</rt><rt>b</rt></rtc></ruby>',
            width: 100,
            direction: direction,
          );
          f.finish();
          final prepared =
              f.prepare(0).single as ForumBodyPreparedInlineFragment;
          final painters = <TextPainter>[];
          try {
            expect(prepared.projection.text, 'AxBab');
            expect(prepared.nativeLeases, hasLength(6));
            final parent =
                prepared.nativeLeases.first as ForumBodyInlineParagraphLease;
            final origin = parent.layout.atomBoxes.single.toRect().topLeft;
            final rtl = direction == TextDirection.rtl;
            final a = rtl ? 20.0 : 0.0, b = rtl ? 0.0 : 20.0;
            final expected = [
              ('A', 20.0, const Color(0xffff0000), Offset(a, 18)),
              ('x', 10.0, const Color(0xff0000ff), Offset(a + 5, 8)),
              ('B', 20.0, const Color(0xffff0000), Offset(b, 18)),
              ('a', 8.0, const Color(0xff008000), Offset(a + 6, 0)),
              ('b', 8.0, const Color(0xff008000), Offset(b + 6, 0)),
            ];
            for (final (text, size, color, _) in expected) {
              painters.add(
                TextPainter(
                  text: TextSpan(
                    text: text,
                    style: TextStyle(
                      fontFamily: 'Ahem',
                      fontSize: size,
                      height: 1,
                      color: color,
                    ),
                  ),
                  textDirection: direction,
                )..layout(),
              );
            }
            final actual = await _pixels(
              (canvas) => prepared.view.paint(canvas, Offset.zero),
              ratio,
            );
            final reference = await _pixels((canvas) {
              for (final (i, item) in expected.indexed) {
                painters[i].paint(canvas, origin + item.$4);
              }
            }, ratio);
            expect(actual, reference);
            for (var i = 0; i < prepared.projection.text.length; i++) {
              final box = prepared.glyphBoxes(i, i + 1).single;
              final hit = prepared.view.sourceAt(
                Offset(box.left + .1, box.toRect().center.dy),
              );
              expect(
                hit.sourceRune,
                prepared.projection.sourceAtUtf16(i).sourceRune,
              );
              expect(hit.displayUtf16, i);
              expect(hit.isExact, isTrue);
            }
          } finally {
            prepared.close();
            for (final painter in painters) {
              painter.dispose();
            }
          }
          expect(f.cache.activeLeases, 0);
        },
      );
    }

    test(
      'mixed nested multi-column source order remains explicit $direction',
      () {
        final f = _Fixture(
          '<ruby><rb>L<ruby><rb>A</rb><rb>B</rb>'
          '<rtc><rt>x</rt><rt>y</rt></rtc></ruby>R</rb><rt>z</rt></ruby>',
          direction: direction,
          width: 200,
        );
        f.finish();
        final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
        try {
          expect(prepared.projection.text, 'LABxyRz');
          expect(prepared.nativeLeases, hasLength(7));
          final exactHits = <bool>[];
          for (var i = 0; i < prepared.projection.text.length; i++) {
            final box = prepared.glyphBoxes(i, i + 1).single;
            final hit = prepared.view.sourceAt(
              Offset(
                box.left +
                    (box.right - box.left) *
                        (box.direction == TextDirection.ltr ? .2 : .8),
                box.toRect().center.dy,
              ),
            );
            exactHits.add(hit.isExact);
            expect(
              hit.sourceRune,
              prepared.projection.sourceAtUtf16(i).sourceRune,
            );
            expect(hit.displayUtf16, i);
          }
          // Reordering shares raw endpoints between independent native windows.
          // Matching a glyph must not promote that ambiguous inverse to exact.
          expect(exactHits, [true, true, false, false, false, true, true]);
        } finally {
          prepared.close();
        }
        expect(f.cache.activeLeases, 0);
      },
    );
  }

  for (final ratio in [1, 3]) {
    test(
      'actual inner anonymous span widens both original columns DPR$ratio',
      () async {
        final f = _Fixture(
          '<ruby style="color:red"><rb>L<ruby><rb>A</rb><rb>B</rb>'
          '<rtc style="font-size:10px;color:blue">uvwxyz</rtc></ruby>R</rb>'
          '<rt style="font-size:10px;color:green">z</rt></ruby>',
          width: 200,
        );
        f.finish();
        final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
        final painters = <TextPainter>[];
        try {
          expect(prepared.projection.text, 'LABuvwxyzRz');
          expect(prepared.nativeLeases, hasLength(6));
          // A 60px annotation spans two 20px bases: both receive 30px columns.
          // Merely retaining an unparsed rbspan attribute would instead allocate
          // a 60px first column and a 20px second column, at different positions.
          final expected = [
            ('L', 20.0, const Color(0xffff0000), const Offset(0, 20)),
            ('A', 20.0, const Color(0xffff0000), const Offset(25, 20)),
            ('B', 20.0, const Color(0xffff0000), const Offset(55, 20)),
            ('uvwxyz', 10.0, const Color(0xff0000ff), const Offset(20, 10)),
            ('R', 20.0, const Color(0xffff0000), const Offset(80, 20)),
            ('z', 10.0, const Color(0xff008000), const Offset(45, 0)),
          ];
          for (final (text, size, color, _) in expected) {
            painters.add(
              TextPainter(
                text: TextSpan(
                  text: text,
                  style: TextStyle(
                    fontFamily: 'Ahem',
                    fontSize: size,
                    height: 1,
                    color: color,
                  ),
                ),
                textDirection: TextDirection.ltr,
              )..layout(),
            );
          }
          final actual = await _pixels(
            (canvas) => prepared.view.paint(canvas, Offset.zero),
            ratio,
          );
          final reference = await _pixels((canvas) {
            for (final (i, item) in expected.indexed) {
              painters[i].paint(canvas, item.$4);
            }
          }, ratio);
          expect(actual, reference);
          expect(prepared.glyphBoxes(1, 2).single.left, 25);
          expect(prepared.glyphBoxes(2, 3).single.left, 55);
          expect(prepared.glyphBoxes(3, 9).single.left, 20);
          expect(prepared.glyphBoxes(3, 9).single.right, 80);
          for (var i = 0; i < prepared.projection.text.length; i++) {
            final box = prepared.glyphBoxes(i, i + 1).single;
            final hit = prepared.view.sourceAt(
              Offset(box.left + .1, box.toRect().center.dy),
            );
            expect(hit.displayUtf16, i);
            expect(
              hit.sourceRune,
              prepared.projection.sourceAtUtf16(i).sourceRune,
            );
            expect(hit.isExact, isTrue);
          }
        } finally {
          prepared.close();
          for (final painter in painters) {
            painter.dispose();
          }
        }
        expect(f.cache.activeLeases, 0);
      },
    );
  }

  for (final annotation in [false, true]) {
    test('deep mixed original windows remain distinct RT=$annotation', () {
      var html = 'A';
      var expected = 'A';
      for (var depth = 0; depth < 8; depth++) {
        html = annotation
            ? '<ruby style="font-size:20px">B<rt style="font-size:20px">'
                  'L${html}R</rt></ruby>'
            : '<ruby style="font-size:20px"><rb>L${html}R</rb>'
                  '<rt style="font-size:10px">x</rt></ruby>';
        expected = annotation ? 'BL${expected}R' : 'L${expected}Rx';
      }
      final f = _Fixture(html, width: 500, height: 500);
      f.finish();
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(prepared.projection.text, expected);
        expect(prepared.nativeLeases, hasLength(17));
        for (var i = 0; i < expected.length; i++) {
          final box = prepared.glyphBoxes(i, i + 1).single;
          final hit = prepared.view.sourceAt(
            Offset(box.left + .1, box.toRect().center.dy),
          );
          expect(hit.isExact, isTrue, reason: 'depth source $i');
          expect(hit.displayUtf16, i);
          expect(
            hit.sourceRune,
            prepared.projection.sourceAtUtf16(i).sourceRune,
          );
        }
      } finally {
        prepared.close();
      }
      expect(f.cache.activeLeases, 0);
    });
  }

  for (final (html, expected) in [
    ('<ruby>A<rt>a</rt><rt><ruby>B<rt>b</rt></ruby></rt></ruby>', 'AaBb'),
    (
      '<ruby><rb><ruby>中<rt>latin</rt></ruby></rb>\n<rb>文</rb>'
          '<rtc><rt>a</rt>\n<rt>b</rt></rtc></ruby>',
      '中latin文a b',
    ),
    (
      '<ruby> \n<rb><ruby>A<rt>x</rt></ruby></rb>\n <rb>B</rb> \n'
          '<rtc><rt>a</rt><rt>b</rt></rtc></ruby>',
      'Ax Bab',
    ),
    (
      '<ruby><rb><ruby>A<rt>x</rt></ruby></rb>'
          '<rtc><rt>a</rt><rt>b</rt><rt>c</rt></rtc></ruby>',
      'Axabc',
    ),
    (
      '<ruby><rb><ruby>A<rt>x</rt></ruby></rb><rb>B</rb>'
          '<rtc><rt>L<ruby>C<rt>c</rt></ruby>R</rt> <rt>D</rt></rtc></ruby>',
      'AxBLCcR D',
    ),
    (
      '<ruby><rb><ruby>A<rt>x</rt></ruby></rb><rb>B</rb><rtc>uvwxyz</rtc></ruby>',
      'AxBuvwxyz',
    ),
  ]) {
    for (final direction in TextDirection.values) {
      test(
        'original multi-column structure retains gaps and nested annotations $direction: $expected',
        () {
          final f = _Fixture(
            html,
            width: 300,
            height: 300,
            direction: direction,
          );
          f.finish();
          final prepared =
              f.prepare(0).single as ForumBodyPreparedInlineFragment;
          try {
            expect(prepared.projection.text, expected);
            validateForumBodyPreparedTextPageBinding(
              snapshot: f.session.snapshot,
              pageIndex: 0,
              layoutId: 'formal-nested',
              fragments: [prepared],
            );
            for (var i = 0; i < expected.length; i++) {
              final box = prepared.glyphBoxes(i, i + 1).single;
              final hit = prepared.view.sourceHitAt(
                Offset(
                  box.left +
                      (box.right - box.left) *
                          (box.direction == TextDirection.ltr ? .2 : .8),
                  box.toRect().center.dy,
                ),
              );
              expect(hit.position.displayUtf16, i);
              final window = hit.window!;
              final local = window.content.projection.sourceAtUtf16(
                i - window.startUtf16,
              );
              expect(hit.position.sourceRune, local.sourceRune);
              if (!prepared.projection.sourceAtUtf16(i).isExact) {
                expect(hit.position.isExact, isFalse);
              }
            }
          } finally {
            prepared.close();
          }
          expect(f.cache.activeLeases, 0);
        },
      );
    }
  }

  for (final html in [
    '<ruby><rb>L<ruby><rb>A</rb><rb>B</rb>'
        '<rtc>xy</rtc></ruby>R</rb><rt>z</rt></ruby>',
    '<ruby>A<rt>L<ruby>B<rt>b</rt></ruby>R</rt></ruby>',
    '<ruby><rb>L<ruby>A<rt></rt></ruby>R</rb><rt>z</rt></ruby>',
    '<ruby style="line-height:1.35"><rb style="line-height:1.15">'
        'L<ruby>A<rt style="font-size:7.5px">x</rt></ruby>R</rb>'
        '<rt style="font-size:9.5px">z</rt></ruby>',
  ]) {
    test('mixed span, RT, empty rank and fractional native frame: $html', () {
      final f = _Fixture(html, width: 300, height: 200);
      f.finish();
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        validateForumBodyPreparedTextPageBinding(
          snapshot: f.session.snapshot,
          pageIndex: 0,
          layoutId: 'formal-nested',
          fragments: [prepared],
        );
        expect(prepared.projection.text, isNotEmpty);
        for (var i = 0; i < prepared.projection.text.length; i++) {
          final boxes = prepared.glyphBoxes(i, i + 1);
          expect(boxes, hasLength(1), reason: 'actual glyph $i');
          final box = boxes.single;
          final hit = prepared.view.sourceAt(
            Offset(box.left + .1, box.toRect().center.dy),
          );
          expect(
            hit.sourceRune,
            prepared.projection.sourceAtUtf16(i).sourceRune,
          );
          expect(hit.displayUtf16, i);
        }
      } finally {
        prepared.close();
      }
      expect(f.cache.activeLeases, 0);
    });
  }

  for (final direction in TextDirection.values) {
    test(
      'deep outer multi-column groups retain original native windows $direction',
      () {
        var html = '<ruby>A<rt>x</rt></ruby>';
        var expected = 'Ax';
        for (var i = 0; i < 8; i++) {
          html =
              '<ruby><rb>L$html'
              'R</rb><rb>B</rb><rtc><rt>z</rt><rt>y</rt></rtc></ruby>';
          expected = 'L${expected}RBzy';
        }
        final f = _Fixture(
          html,
          width: 1000,
          height: 1000,
          direction: direction,
          cacheEntries: 128,
        );
        f.finish();
        final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
        try {
          expect(prepared.projection.text, expected);
          for (var i = 0; i < expected.length; i++) {
            final box = prepared.glyphBoxes(i, i + 1).single;
            final hit = prepared.view.sourceHitAt(
              Offset(box.left + .1, box.toRect().center.dy),
            );
            expect(hit.position.displayUtf16, i);
            final window = hit.window!;
            expect(
              hit.position.sourceRune,
              window.content.projection
                  .sourceAtUtf16(i - window.startUtf16)
                  .sourceRune,
            );
          }
        } finally {
          prepared.close();
        }
        expect(f.cache.activeLeases, 0);
      },
    );
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

  test('intermediate mixed projections count against pre-native limits', () {
    for (final textLimit in [false, true]) {
      final f = _Fixture(
        '<ruby><rb>L<ruby>A<rt>x</rt></ruby>R</rb><rt>z</rt></ruby>',
        // Display is five characters/runs; the retained LAxR child adds four.
        maxText: textLimit ? 5 : 100000,
        maxRuns: textLimit ? 10000 : 5,
      );
      expect(
        f.finish,
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

  test('mixed logical handle limit includes its real inner parent', () {
    final f = _Fixture(
      '<ruby><rb>L<ruby>A<rt>x</rt></ruby>R</rb><rt>z</rt></ruby>',
      maxIssued: 4,
    );
    f.finish();
    final page = f.session.snapshot.first;
    expect(
      () => f.session.openPagePreparation(0),
      throwsA(
        isA<ForumBodyTextPageSessionException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyTextPageSessionFailure.leaseLimit,
        ),
      ),
    );
    expect(f.session.snapshot.first, same(page));
    expect(f.session.activeIssuedLeases, 0);
    expect(f.cache.activeLeases, 0);
  });

  test('retirement in mixed native scaling cannot publish a late child', () {
    late final _Fixture f;
    f = _Fixture(
      '<ruby><rb>L<ruby>A<rt style="font-size:10px">x</rt></ruby>R</rb>'
      '<rt style="font-size:8px">z</rt></ruby>',
      scaler: _CallbackScaler((size) {
        if (size == 10) f.session.close();
        return size;
      }),
    );
    expect(f.finish, throwsStateError);
    expect(f.session.state, ForumBodyTextPageSessionState.closed);
    expect(f.session.snapshot, isEmpty);
    expect(f.cache.activeLeases, 0);
  });

  test(
    'mixed cooperative source and metric cancellation releases partial work',
    () {
      for (final cancelAfter in [1, 5, 30, 60, 120, 240, 480]) {
        final f = _Fixture(
          '<ruby><rb>L<ruby><rb>M<ruby>A<rt>x</rt></ruby>N</rb>'
          '<rt>y</rt></ruby>R</rb><rt>z</rt></ruby>',
        );
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
    },
  );

  for (final ratio in [1, 3]) {
    test(
      'formal nested original IR publishes a source-bound visible page DPR$ratio',
      () async {
        final f = _Fixture(
          '<ruby style="color:red"><rb><ruby>AB'
          '<rt style="font-size:10px;color:blue">xy</rt></ruby></rb>'
          '<rt style="font-size:8px;color:green">WXYZAB</rt></ruby>',
        );
        f.finish();
        expect(f.session.snapshot.length, 1);
        expect(f.cache.activeLeases, 0);
        final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
        final painters = <TextPainter>[];
        try {
          validateForumBodyPreparedTextPageBinding(
            snapshot: f.session.snapshot,
            pageIndex: 0,
            layoutId: 'formal-nested',
            fragments: [prepared],
          );
          expect(prepared.projection.text, 'ABxyWXYZAB');
          expect(prepared.nativeLeases, hasLength(4));
          final children = prepared.nativeLeases
              .skip(1)
              .cast<ForumBodyTextLease>()
              .toList();
          expect(children.map((c) => c.content.projection.text), [
            'AB',
            'xy',
            'WXYZAB',
          ]);
          for (final child in children) {
            painters.add(
              TextPainter(
                text: TextSpan(
                  text: child.content.projection.text,
                  style: child.content.runs.single.style.textStyle,
                ),
                textDirection: TextDirection.ltr,
              )..layout(),
            );
          }
          final actual = await _pixels(
            (canvas) => prepared.view.paint(canvas, Offset.zero),
            ratio,
          );
          final expected = await _pixels((canvas) {
            painters[0].paint(canvas, const Offset(4, 18));
            painters[1].paint(canvas, const Offset(14, 8));
            painters[2].paint(canvas, Offset.zero);
          }, ratio);
          expect(actual, expected);
          for (final start in [0, 2, 4]) {
            final box = prepared.glyphBoxes(start, start + 1).single;
            final hit = prepared.view.sourceAt(
              Offset(box.left + .1, box.toRect().center.dy),
            );
            expect(hit.isExact, isTrue);
            expect(
              hit.sourceRune,
              prepared.projection.sourceAtUtf16(start).sourceRune,
            );
          }
        } finally {
          prepared.close();
          for (final painter in painters) {
            painter.dispose();
          }
        }
        expect(f.cache.activeLeases, 0);
      },
    );
  }
  for (final ratio in [1, 3]) {
    test(
      'same root aligns flat/nested columns and paints its alpha once DPR$ratio',
      () async {
        final f = _Fixture(
          '<ruby style="background:rgba(255,0,0,0.5)">'
          '<rb><ruby><rb>A </rb><rt>a</rt></ruby></rb><rt>x</rt>'
          '<rb> B</rb><rt>y</rt></ruby>',
        );
        f.finish();
        final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
        final painters = <TextPainter>[];
        try {
          expect(prepared.view.atomIndices, [0, 1]);
          expect(prepared.view.containerBackgrounds, hasLength(1));
          expect(
            prepared.view.containerBackgrounds.single.rect,
            const Rect.fromLTWH(0, 20, 80, 20),
          );
          final children = prepared.nativeLeases
              .skip(1)
              .cast<ForumBodyTextLease>()
              .toList();
          expect(children.map((c) => c.content.projection.text), [
            'A ',
            'a',
            'x',
            ' B',
            'y',
          ]);
          final offsets = [
            const Offset(0, 20),
            const Offset(15, 10),
            const Offset(15, 0),
            const Offset(40, 20),
            const Offset(55, 0),
          ];
          for (final child in children) {
            painters.add(
              TextPainter(
                text: TextSpan(
                  text: child.content.projection.text,
                  style: child.content.runs.single.style.textStyle,
                ),
                textDirection: TextDirection.ltr,
              )..layout(),
            );
          }
          final actual = await _pixels(
            (canvas) => prepared.view.paint(canvas, Offset.zero),
            ratio,
          );
          final expected = await _pixels((canvas) {
            canvas.drawRect(
              const Rect.fromLTWH(0, 20, 80, 20),
              Paint()..color = const Color(0x80ff0000),
            );
            for (var index = 0; index < painters.length; index++) {
              painters[index].paint(canvas, offsets[index]);
            }
          }, ratio);
          expect(actual, expected);
        } finally {
          prepared.close();
          for (final p in painters) {
            p.dispose();
          }
        }
        expect(f.cache.activeLeases, 0);
      },
    );
  }

  for (final direction in TextDirection.values) {
    for (final nestedRT in [false, true]) {
      test(
        'formal source windows preserve original nested order $direction RT=$nestedRT',
        () {
          final html = nestedRT
              ? '<ruby>AB<rt><ruby>CD<rt>ef</rt></ruby></rt></ruby>'
              : '<ruby><rb><ruby>AB<rt>cd</rt></ruby></rb><rt>ef</rt></ruby>';
          final f = _Fixture(html, direction: direction);
          f.finish();
          final prepared =
              f.prepare(0).single as ForumBodyPreparedInlineFragment;
          try {
            expect(prepared.projection.text, nestedRT ? 'ABCDef' : 'ABcdef');
            for (final start in [0, 2, 4]) {
              final box = prepared.glyphBoxes(start, start + 1).single;
              final x = box.direction == TextDirection.ltr
                  ? box.left + .1
                  : box.right - .1;
              final hit = prepared.view.sourceAt(
                Offset(x, box.toRect().center.dy),
              );
              expect(hit.isExact, isTrue);
              expect(
                hit.sourceRune,
                prepared.projection.sourceAtUtf16(start).sourceRune,
              );
            }
            validateForumBodyPreparedTextPageBinding(
              snapshot: f.session.snapshot,
              pageIndex: 0,
              layoutId: 'formal-nested',
              fragments: [prepared],
            );
          } finally {
            prepared.close();
          }
          expect(f.cache.activeLeases, 0);
        },
      );
    }
  }

  test(
    'multi-page tree preparation owns only visible leaves and records only their pictures',
    () {
      final html = [
        for (var i = 0; i < 6; i++)
          '<ruby><rb><ruby>AB<rt style="font-size:10px">xy</rt></ruby></rb>'
              '<rt style="font-size:8px">WXYZAB</rt></ruby>',
      ].join();
      final f = _Fixture(html, width: 48, height: 40);
      f.finish();
      expect(f.session.snapshot.length, 6);
      expect(f.cache.preparedPictureCount, 0);
      for (var page = 0; page < 6; page++) {
        final prepared =
            f.prepare(page).single as ForumBodyPreparedInlineFragment;
        try {
          expect(prepared.view.atomIndices, [page]);
          expect(prepared.nativeLeases, hasLength(4));
          expect(f.cache.activeLeases, 4);
          if (page == 0) expect(f.cache.preparedPictureCount, 3);
          validateForumBodyPreparedTextPageBinding(
            snapshot: f.session.snapshot,
            pageIndex: page,
            layoutId: 'formal-nested',
            fragments: [prepared],
          );
          final start = page * 10;
          for (final offset in [start, start + 2, start + 4]) {
            final box = prepared.glyphBoxes(offset, offset + 1).single;
            final hit = prepared.view.sourceAt(
              Offset(box.left + .1, box.toRect().center.dy),
            );
            expect(hit.isExact, isTrue);
            expect(
              hit.sourceRune,
              prepared.projection.sourceAtUtf16(offset).sourceRune,
            );
          }
        } finally {
          prepared.close();
        }
        expect(f.cache.activeLeases, 0);
      }
    },
  );

  test(
    'root leading is approximate in the actual parent view; glyph coverage is unchanged',
    () {
      final f = _Fixture(
        '<ruby style="line-height:6"><rb style="line-height:1"><ruby style="line-height:1">AB'
        '<rt style="font-size:10px">xy</rt></ruby></rb><rt style="font-size:8px">WXYZAB</rt></ruby>',
        height: 160,
      );
      f.finish();
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(prepared.view.height, greaterThanOrEqualTo(120));
        expect(prepared.view.sourceAt(const Offset(5, 1)).isExact, isFalse);
        for (final start in [0, 2, 4]) {
          final box = prepared.glyphBoxes(start, start + 1).single;
          expect(
            prepared.view
                .sourceAt(Offset(box.left + .1, box.toRect().center.dy))
                .isExact,
            isTrue,
          );
        }
      } finally {
        prepared.close();
      }
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
      var sourceStarted = false;
      for (var count = 0; !sourceStarted && count < 10000; count++) {
        sourceStarted =
            f.session.advance(maxEvents: 1, maxLines: 1).formatUnitsPrepared >
            0;
      }
      expect(sourceStarted, isTrue);
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
    'closing during visible tree preparation retires its bound/unbound leaves',
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

  test(
    'deep visible page binds identical annotations to distinct original windows',
    () {
      var html = 'A';
      for (var depth = 0; depth < 30; depth++) {
        html =
            '<ruby style="font-size:20px"><rb>$html</rb><rt style="font-size:1px">x</rt></ruby>';
      }
      final f = _Fixture(html, height: 80);
      f.finish();
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(prepared.nativeLeases, hasLength(32));
        expect(prepared.projection.text.length, 31);
        for (var start = 0; start < 31; start++) {
          final box = prepared.glyphBoxes(start, start + 1).single;
          final hit = prepared.view.sourceAt(
            Offset(box.left + .1, box.toRect().center.dy),
          );
          expect(hit.isExact, isTrue);
          expect(
            hit.sourceRune,
            prepared.projection.sourceAtUtf16(start).sourceRune,
          );
        }
      } finally {
        prepared.close();
      }
      expect(f.cache.activeLeases, 0);
    },
  );

  test(
    'ordinary parent text stays source-bound beside an opaque nested tree',
    () {
      final f = _Fixture(
        'P<ruby><rb><ruby>AB<rt>xy</rt></ruby></rb><rt>zz</rt></ruby>Q',
      );
      f.finish();
      final prepared = f.prepare(0).single as ForumBodyPreparedInlineFragment;
      try {
        expect(prepared.projection.text, 'PABxyzzQ');
        expect(prepared.nativeLeases, hasLength(4));
        for (var start = 0; start < prepared.projection.text.length; start++) {
          final box = prepared.glyphBoxes(start, start + 1).single;
          final hit = prepared.view.sourceAt(
            Offset(box.left + .1, box.toRect().center.dy),
          );
          expect(hit.isExact, isTrue);
          expect(
            hit.sourceRune,
            prepared.projection.sourceAtUtf16(start).sourceRune,
          );
        }
      } finally {
        prepared.close();
      }
      expect(f.cache.activeLeases, 0);
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
