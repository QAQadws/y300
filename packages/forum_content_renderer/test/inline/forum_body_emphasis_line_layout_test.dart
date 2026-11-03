import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _html =
    '<p style="text-emphasis:\'X\' red;line-height:.4;">'
    '<span style="text-emphasis:none;font-size:28px;">大</span>ffi '
    '<b>é</b> 中 <span style="text-emphasis-color:blue;text-emphasis-position:under;">'
    'العربية 👩‍👩‍👧‍👦</span><span style="visibility:hidden">隐</span></p>';

ForumBodyEmphasisTextInput _input({
  String html = _html,
  ForumBodyParagraphLayoutMode mode =
      ForumBodyParagraphLayoutMode.intrinsicSingleLine,
  TextDirection direction = TextDirection.ltr,
}) {
  final doc = const ForumBodyParser().parse(
    html: html,
    sourceId: 'emphasis-line',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    doc,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontSize: 20,
        fontFamily: 'Ahem',
        color: Color(0xff123456),
      ),
      fontRevision: 'emphasis-line',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
    ),
  );
  final content = const ForumBodyParagraphContentBuilder().build(
    document: doc,
    styles: styles,
    path: '0',
    layoutMode: mode,
  );
  final job = ForumBodyEmphasisTextPreparation(content: content);
  while (!job.isReady) {
    job.advance(maxParts: 3);
  }
  return job.takeInput();
}

ForumBodyParagraphCache _cache({int entries = 16, int bytes = 1 << 24}) {
  final value = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: bytes,
  );
  addTearDown(value.close);
  return value;
}

ForumBodyEmphasisLineLayout _finish(
  ForumBodyEmphasisLinePreparation job, {
  int quantum = 1,
  bool cachedOnly = false,
}) {
  var count = 0;
  while (!job.isReady) {
    final step = job.advance(maxParts: quantum, cachedOnly: cachedOnly);
    expect(step.partsPrepared, lessThanOrEqualTo(quantum));
    expect(
      step.nativeLayoutsBuilt + step.picturesRecorded,
      lessThanOrEqualTo(1),
    );
    expect(step.waitingForLayoutBudget, isFalse);
    expect(job.cacheMiss, isFalse);
    expect(++count, lessThan(10000));
  }
  return job.takeLayout();
}

final class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double size) => size < 20 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use per-size values');
}

Future<List<int>> _pixels(
  ForumBodyEmphasisLineLayout line,
  int dpr,
  void Function(Canvas) draw,
) async {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec)..scale(dpr.toDouble()));
  final pic = rec.endRecording();
  try {
    final image = await pic.toImage(
      (line.width.ceil() + 60) * dpr,
      (line.height.ceil() + 60) * dpr,
    );
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List().toList();
    } finally {
      image.dispose();
    }
  } finally {
    pic.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  test('delivered fitted line keeps the persistent reader guard', () {
    final input = _input(mode: ForumBodyParagraphLayoutMode.fitSingleLine),
        cache = _cache();
    var preparing = true, reading = true;
    final job = ForumBodyEmphasisLinePreparation(
      input: input,
      cache: cache,
      width: 80,
      ensureOwner: () {
        if (!preparing) throw StateError('Preparation retired');
      },
      ensureVisibleOwner: () {
        if (!reading) throw StateError('Reader retired');
      },
    );
    final line = _finish(job);
    addTearDown(line.close);
    preparing = false;
    job.close();
    line.ensureActive();
    expect(
      line.sourceAt(Offset.zero).displayUtf16,
      inInclusiveRange(0, line.projection.text.length),
    );
    expect(line.selectionBoxes(0, line.projection.text.length), isNotEmpty);
    final shapes = cache.layoutBuildCount, pictures = cache.pictureBuildCount;
    final recorder = ui.PictureRecorder();
    line.paint(Canvas(recorder), Offset.zero);
    recorder.endRecording().dispose();
    expect(cache.layoutBuildCount, shapes);
    expect(cache.pictureBuildCount, pictures);
    final native = (line.nativeLeases.first as ForumBodyParagraphLease)
        .layout
        .lines
        .single;
    expect(line.metrics.paragraphLine, same(native));
    expect(native.coverageStartUtf16, 0);
    expect(native.coverageEndUtf16, input.content.projection.text.length);
    reading = false;
    expect(line.ensureActive, throwsStateError);
    expect(() => line.sourceAt(Offset.zero), throwsStateError);
    line.close();
    expect(cache.activeLeases, 0);
  });

  for (final cancelTransaction in [false, true]) {
    test('visible owner is rechecked at line transfer: $cancelTransaction', () {
      final input = _input(mode: ForumBodyParagraphLayoutMode.fitSingleLine),
          cache = _cache();
      var calls = 0;
      late final ForumBodyEmphasisLinePreparation job;
      job = ForumBodyEmphasisLinePreparation(
        input: input,
        cache: cache,
        width: 80,
        ensureOwner: () {},
        ensureVisibleOwner: () {
          if (++calls == 2) {
            if (cancelTransaction) {
              job.close();
            } else {
              throw StateError('Reader retired');
            }
          }
        },
      );
      for (var n = 0; !job.isReady; n++) {
        expect(n, lessThan(10000));
        job.advance(maxParts: 1);
      }
      expect(calls, 1);
      expect(job.takeLayout, throwsStateError);
      expect(cache.activeLeases, 0);
      job.close();
    });
  }
  for (final mode in ForumBodyParagraphLayoutMode.values) {
    for (final direction in TextDirection.values) {
      for (final dpr in [1, 3]) {
        test('prepared native emphasis $mode $direction DPR$dpr', () async {
          final input = _input(mode: mode, direction: direction),
              cache = _cache();
          final width = mode == ForumBodyParagraphLayoutMode.wrap
              ? 900.0
              : 140.0;
          final line = _finish(
            ForumBodyEmphasisLinePreparation(
              input: input,
              cache: cache,
              width: width,
              ensureOwner: () {},
              textScaler: const _Nonlinear(),
            ),
          );
          addTearDown(line.close);
          expect(line.projection, same(input.content.projection));
          expect(line.marks, hasLength(input.units.length));
          expect(cache.activeLeases, 2);
          expect(line.nativeLeases, hasLength(2));
          cache.clearUnpinned();
          expect(cache.entryCount, 2);
          final base =
              TextPainter(
                text: input.glyphInput.glyphs.textSpan,
                textDirection: direction,
                textScaler: const _Nonlinear(),
              )..layout(
                minWidth:
                    mode == ForumBodyParagraphLayoutMode.intrinsicSingleLine
                    ? 0
                    : width,
                maxWidth: mode == ForumBodyParagraphLayoutMode.wrap
                    ? width
                    : double.infinity,
              );
          final fit = mode == ForumBodyParagraphLayoutMode.fitSingleLine
              ? width / base.width
              : 1.0;
          final controls = <TextPainter>[];
          try {
            for (final mark in line.marks) {
              final style = input
                  .content
                  .runs[input.units[mark.unitIndex].runIndex]
                  .style;
              controls.add(
                TextPainter(
                  text: TextSpan(
                    text: 'X',
                    style: TextStyle(
                      inherit: false,
                      fontFamily: 'Ahem',
                      fontSize: style.textStyle.fontSize! * .5,
                      fontWeight: style.textStyle.fontWeight,
                      fontStyle: style.textStyle.fontStyle,
                      color: style.visibilityHidden
                          ? const Color(0x00000000)
                          : style.textEmphasis.color,
                      height: kTextHeightNone,
                      decoration: TextDecoration.none,
                      fontFeatures: const [FontFeature.enable('ruby')],
                    ),
                  ),
                  textDirection: direction,
                  textScaler: const _Nonlinear(),
                )..layout(),
              );
              expect(mark.fitScale, fit);
            }
            final baselines = <ForumBodyEmphasisSide, double>{};
            for (var i = 0; i < line.marks.length; i++) {
              final mark = line.marks[i];
              final unit = input.units[mark.unitIndex];
              final side =
                  input.content.runs[unit.runIndex].style.textEmphasis.side;
              final baseline =
                  mark.offset.dy +
                  controls[i].computeDistanceToActualBaseline(
                        TextBaseline.alphabetic,
                      ) *
                      fit;
              final shared = baselines.putIfAbsent(side, () => baseline);
              expect(baseline, closeTo(shared, 1e-6));
            }
            final builds = cache.layoutBuildCount,
                pictures = cache.pictureBuildCount;
            final actual = await _pixels(
              line,
              dpr,
              (c) => line.paint(c, const Offset(20, 20)),
            );
            final expected = await _pixels(line, dpr, (c) {
              c.save();
              c.translate(20 + line.baseOffset.dx, 20 + line.baseOffset.dy);
              c.scale(fit, fit);
              base.paint(c, Offset.zero);
              c.restore();
              for (var i = 0; i < line.marks.length; i++) {
                final at = line.marks[i].offset;
                c.save();
                c.translate(20 + at.dx, 20 + at.dy);
                c.scale(fit, fit);
                controls[i].paint(c, Offset.zero);
                c.restore();
              }
            });
            expect(actual, expected);
            expect(cache.layoutBuildCount, builds);
            expect(cache.pictureBuildCount, pictures);
            // Include the larger unmarked prefix as well as decorated text.
            for (final box in line.selectionBoxes(
              0,
              line.projection.text.length,
            )) {
              expect(box.top, greaterThanOrEqualTo(0));
              expect(box.bottom, lessThanOrEqualTo(line.height));
            }
            for (final unit in input.units) {
              final expectedBoxes = base.getBoxesForSelection(
                TextSelection(
                  baseOffset: unit.startUtf16,
                  extentOffset: unit.endUtf16,
                ),
              );
              final actualBoxes = line.selectionBoxes(
                unit.startUtf16,
                unit.endUtf16,
              );
              expect(actualBoxes, hasLength(expectedBoxes.length));
              for (var i = 0; i < actualBoxes.length; i++) {
                final expected = expectedBoxes[i];
                expect(
                  actualBoxes[i].toRect(),
                  Rect.fromLTRB(
                    expected.left * fit,
                    expected.top * fit + line.baseOffset.dy,
                    expected.right * fit,
                    expected.bottom * fit + line.baseOffset.dy,
                  ),
                );
              }
            }
            for (final mark in line.marks) {
              final hit = line.sourceAt(mark.fontBounds.center),
                  unit = input.units[mark.unitIndex];
              expect(
                hit.sourceRune,
                input.content.projection
                    .sourceAtUtf16(unit.governingUtf16)
                    .sourceRune,
              );
              expect(hit.isExact, isFalse);
            }
            expect(() => line.marks.clear(), throwsUnsupportedError);
          } finally {
            base.dispose();
            for (final text in controls) {
              text.dispose();
            }
          }
          line.close();
          cache.clearUnpinned();
          expect(cache.activeLeases, 0);
          expect(cache.entryCount, 0);
        });
      }
    }
  }
  test('Ahem placement uses complete base font frame and both sides', () {
    final input = _input(
      html:
          '<p style="text-emphasis:\'X\' red;line-height:.4;">'
          'A<span style="text-emphasis-position:under;">B</span></p>',
    );
    final cache = _cache();
    final line = _finish(
      ForumBodyEmphasisLinePreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
      ),
    );
    addTearDown(line.close);
    expect(line.width, 40);
    // Proportional author leading leaves a fractional font edge. The frame
    // rounds outwards while glyphs keep their actual native position.
    expect(line.height, 41);
    expect(line.baseOffset, const Offset(0, 20));
    expect(
      line.marks[0].fontBounds,
      rectMoreOrLessEquals(const Rect.fromLTWH(5, .4, 10, 10), epsilon: 1e-5),
    );
    expect(
      line.marks[1].fontBounds,
      rectMoreOrLessEquals(
        const Rect.fromLTWH(25, 30.4, 10, 10),
        epsilon: 1e-5,
      ),
    );
    expect(
      line.selectionBoxes(0, 2).single.toRect(),
      rectMoreOrLessEquals(const Rect.fromLTWH(0, 10.4, 40, 20), epsilon: 1e-5),
    );
  });
  test(
    'band request retains its local source and prepares one shared picture',
    () {
      final whole = _input(html: '<p style="text-emphasis:\'X\' red;">AB</p>'),
          cache = _cache();
      final source = ForumBodyEmphasisTextPreparation(
        content: whole.content.displayWindow(startUtf16: 0, endUtf16: 1),
      );
      while (!source.isReady) {
        source.advance(maxParts: 1);
      }
      final input = source.takeInput();
      final band = ForumBodyTextBandContent(
        contexts: [
          input.glyphInput.glyphs,
          whole.glyphInput.glyphs.displayWindow(startUtf16: 1, endUtf16: 2),
        ],
      );
      final request = ForumBodyTextRequest.bandChild(band: band, childIndex: 0);
      final line = _finish(
        ForumBodyEmphasisLinePreparation(
          input: input,
          baseRequest: request,
          cache: cache,
          ensureOwner: () {},
        ),
      );
      addTearDown(line.close);
      expect(line.marks, hasLength(1));
      expect(cache.layoutBuildCount, 2);
      expect(cache.pictureBuildCount, 2);
      expect(cache.activeLeases, 2);
      expect(line.projection, same(input.content.projection));
    },
  );
  test('warm cached-only transaction reuses native resources and scene', () {
    final input = _input(), cache = _cache();
    final first = _finish(
      ForumBodyEmphasisLinePreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
      ),
    );
    final builds = cache.layoutBuildCount, pictures = cache.pictureBuildCount;
    final second = _finish(
      ForumBodyEmphasisLinePreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
      ),
      cachedOnly: true,
    );
    expect(
      second.nativeLeases.last.nativeInputIdentity,
      first.nativeLeases.last.nativeInputIdentity,
    );
    expect(cache.layoutBuildCount, builds);
    expect(cache.pictureBuildCount, pictures);
    first.close();
    second.close();
    expect(cache.activeLeases, 0);
  });
  test('cached-only miss resumes same preparation without native work', () {
    final input = _input(), cache = _cache();
    final job = ForumBodyEmphasisLinePreparation(
      input: input,
      cache: cache,
      ensureOwner: () {},
    );
    while (!job.cacheMiss) {
      job.advance(maxParts: 1, cachedOnly: true);
    }
    expect(cache.layoutBuildCount, 0);
    expect(cache.pictureBuildCount, 0);
    final line = _finish(job);
    line.close();
    expect(cache.activeLeases, 0);
  });
  test('external pins wait without reshaping then resume the same scene', () {
    final input = _input(html: '<p style="text-emphasis:\'X\' red;">AB</p>'),
        cache = _cache(entries: 3);
    final foreignInput = _input(html: '<p>other</p>');
    final foreign = cache.acquire(
      content: foreignInput.glyphInput.glyphs,
      width: 100,
    );
    final job = ForumBodyEmphasisLinePreparation(
      input: input,
      cache: cache,
      ensureOwner: () {},
    );
    var waiting = false;
    while (!waiting) {
      waiting = job.advance(maxParts: 1).waitingForLayoutBudget;
    }
    final builds = cache.layoutBuildCount, pictures = cache.pictureBuildCount;
    expect(job.advance(maxParts: 1).waitingForLayoutBudget, isTrue);
    expect(cache.layoutBuildCount, builds);
    expect(cache.pictureBuildCount, pictures);
    foreign.release();
    final line = _finish(job);
    line.close();
    expect(cache.activeLeases, 0);
  });
  test('own complete footprint cannot become a permanent wait', () {
    final input = _input(), cache = _cache(entries: 1);
    final job = ForumBodyEmphasisLinePreparation(
      input: input,
      cache: cache,
      ensureOwner: () {},
    );
    expect(
      () {
        while (!job.isReady) {
          job.advance(maxParts: 1);
        }
      },
      throwsA(
        isA<ForumBodyParagraphBudgetException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyParagraphBudgetFailure.content,
        ),
      ),
    );
    expect(cache.activeLeases, 0);
    expect(cache.layoutBuildCount, 0);
  });
  test('multiline base is explicitly rejected and every resource released', () {
    final input = _input(mode: ForumBodyParagraphLayoutMode.wrap),
        cache = _cache();
    final job = ForumBodyEmphasisLinePreparation(
      input: input,
      cache: cache,
      width: 40,
      ensureOwner: () {},
    );
    expect(
      () {
        while (!job.isReady) {
          job.advance(maxParts: 1);
        }
      },
      throwsA(
        isA<ForumBodyEmphasisLineException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyEmphasisLineFailure.lines,
        ),
      ),
    );
    expect(cache.activeLeases, 0);
  });
  test('source mismatch fails without adopting a foreign request', () {
    final input = _input(), other = _input(), cache = _cache();
    expect(
      () => ForumBodyEmphasisLinePreparation(
        input: input,
        cache: cache,
        baseRequest: ForumBodyTextRequest.paragraph(other.glyphInput.glyphs),
        ensureOwner: () {},
      ),
      throwsA(isA<ForumBodyEmphasisLineException>()),
    );
    expect(cache.activeLeases, 0);
    expect(cache.entryCount, 0);
  });
  test(
    'scale callbacks run once per actual full/half size before native work',
    () {
      final input = _input(), cache = _cache();
      final samples = <double>[];
      final scaler = _OnceScaler((size) {
        expect(samples, isNot(contains(size)));
        expect(cache.layoutBuildCount, 0);
        samples.add(size);
        return size < 20 ? size * 1.4 : size * 1.1;
      });
      final line = _finish(
        ForumBodyEmphasisLinePreparation(
          input: input,
          cache: cache,
          textScaler: scaler,
          ensureOwner: () {},
        ),
      );
      expect(samples, containsAll([20.0, 28.0, 10.0]));
      // Job cleanup cannot clear the map retained by the actual native painter.
      final recorder = ui.PictureRecorder();
      try {
        line.paint(Canvas(recorder), Offset.zero);
      } finally {
        recorder.endRecording().dispose();
        line.close();
      }
    },
  );
  test('cancellation at every work boundary releases only owned resources', () {
    final input = _input(html: '<p style="text-emphasis:\'X\' red;">AB</p>');
    final initial = _cache();
    final first = ForumBodyEmphasisLinePreparation(
      input: input,
      cache: initial,
      ensureOwner: () {},
    );
    var steps = 0;
    while (!first.isReady) {
      first.advance(maxParts: 1);
      steps++;
    }
    first.takeLayout().close();
    for (var cut = 0; cut <= steps; cut++) {
      final cache = _cache();
      final job = ForumBodyEmphasisLinePreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
      );
      for (var i = 0; i < cut && !job.isReady; i++) {
        job.advance(maxParts: 1);
      }
      job.close();
      job.close();
      expect(cache.activeLeases, 0, reason: 'cut=$cut');
      cache.clearUnpinned();
      expect(cache.entryCount, 0, reason: 'cut=$cut');
      expect(job.takeLayout, throwsStateError);
    }
  });
  for (final kind in ['cache', 'generation', 'source']) {
    for (final ready in [false, true]) {
      test('$kind retirement ready=$ready prevents late publication', () {
        final input = _input(), cache = _cache();
        var current = true;
        final job = ForumBodyEmphasisLinePreparation(
          input: input,
          cache: cache,
          ensureOwner: () {
            if (!current) throw StateError('Retired generation');
          },
        );
        if (ready) {
          while (!job.isReady) {
            job.advance(maxParts: 1);
          }
        } else {
          while (job.nativeLeases.whereType<ForumBodyTextLease>().isEmpty) {
            job.advance(maxParts: 1);
          }
        }
        switch (kind) {
          case 'cache':
            cache.close();
          case 'generation':
            current = false;
          case 'source':
            job.nativeLeases.whereType<ForumBodyTextLease>().first.release();
        }
        expect(
          ready ? job.takeLayout : () => job.advance(maxParts: 1),
          throwsStateError,
        );
        job.close();
        expect(cache.activeLeases, 0);
      });
    }
  }
  test(
    'scaler reentry or owner cancellation cannot deliver partial geometry',
    () {
      final input = _input(), cache = _cache();
      ForumBodyEmphasisLinePreparation? job;
      job = ForumBodyEmphasisLinePreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
        textScaler: _OnceScaler((size) {
          job!.close();
          return size;
        }),
      );
      expect(() => job!.advance(maxParts: 1), throwsStateError);
      expect(cache.activeLeases, 0);
      job = ForumBodyEmphasisLinePreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
        textScaler: _OnceScaler((size) {
          job!.advance(maxParts: 1);
          return size;
        }),
      );
      expect(() => job!.advance(maxParts: 1), throwsStateError);
      expect(cache.activeLeases, 0);
      job.close();
    },
  );
  test(
    'native recording cancellation cannot install a late composed picture',
    () {
      final input = _input(), cache = _cache();
      final job = ForumBodyEmphasisLinePreparation(
        input: input,
        cache: cache,
        ensureOwner: () {},
      );
      final previous = ui.Picture.onCreate;
      ui.Picture.onCreate = (_) => job.close();
      try {
        expect(() => _finish(job), throwsStateError);
      } finally {
        ui.Picture.onCreate = previous;
        job.close();
      }
      expect(cache.activeLeases, 0);
      expect(cache.pictureBuildCount, 0);
    },
  );
  test('empty and inactive input do not invent marks or copy text', () {
    for (final html in [
      '<p></p>',
      '<p>ordinary</p>',
      '<p style="text-emphasis:dot">，，</p>',
    ]) {
      final input = _input(html: html), cache = _cache();
      final line = _finish(
        ForumBodyEmphasisLinePreparation(
          input: input,
          cache: cache,
          ensureOwner: () {},
        ),
      );
      expect(line.marks, isEmpty);
      expect(line.projection.text, input.content.projection.text);
      line.close();
      expect(cache.activeLeases, 0);
    }
  });
  test(
    'prepared view remains source-bound and stops when its generation retires',
    () {
      final input = _input(), cache = _cache();
      var current = true;
      final line = _finish(
        ForumBodyEmphasisLinePreparation(
          input: input,
          cache: cache,
          ensureOwner: () {
            if (!current) throw StateError('Retired');
          },
        ),
      );
      current = false;
      expect(() => line.sourceAt(Offset.zero), throwsStateError);
      expect(() => line.selectionBoxes(0, 1), throwsStateError);
      final recorder = ui.PictureRecorder();
      try {
        expect(
          () => line.paint(Canvas(recorder), Offset.zero),
          throwsStateError,
        );
      } finally {
        recorder.endRecording().dispose();
        line.close();
      }
      expect(cache.activeLeases, 0);
    },
  );
  test('engine-only first-line indent never becomes marker source text', () {
    final input = _input(
          html: '<p style="text-emphasis:\'X\' red;text-indent:1em;">AB</p>',
          mode: ForumBodyParagraphLayoutMode.wrap,
        ),
        cache = _cache();
    final line = _finish(
      ForumBodyEmphasisLinePreparation(
        input: input,
        cache: cache,
        width: 160,
        ensureOwner: () {},
      ),
    );
    try {
      expect(line.projection.text, 'AB');
      expect(line.selectionBoxes(0, 1).single.left, 20);
      expect(line.marks.first.offset.dx, 25);
      final hit = line.sourceAt(line.marks.first.fontBounds.center);
      expect(
        hit.sourceRune,
        input.content.projection.sourceAtUtf16(0).sourceRune,
      );
      expect(hit.isExact, isFalse);
    } finally {
      line.close();
    }
  });
  for (final side in ['over', 'under']) {
    test('mixed-size $side marks share one annotation baseline', () {
      final input = _input(
            html:
                '<p style="text-emphasis:\'X\' red;text-emphasis-position:$side;line-height:.4;">'
                'A<span style="font-size:30px">B</span></p>',
          ),
          cache = _cache();
      final line = _finish(
        ForumBodyEmphasisLinePreparation(
          input: input,
          cache: cache,
          ensureOwner: () {},
        ),
      );
      final native = <TextPainter>[];
      try {
        for (final mark in line.marks) {
          native.add(
            TextPainter(
              text: TextSpan(
                text: mark.input.mark,
                style: mark.input.textStyle,
              ),
              textDirection: TextDirection.ltr,
            )..layout(),
          );
        }
        expect(line.marks, hasLength(2));
        expect(
          line.marks[0].fontBounds.height,
          lessThan(line.marks[1].fontBounds.height),
        );
        final first =
            line.marks[0].offset.dy +
            native[0].computeDistanceToActualBaseline(TextBaseline.alphabetic);
        final second =
            line.marks[1].offset.dy +
            native[1].computeDistanceToActualBaseline(TextBaseline.alphabetic);
        expect(first, closeTo(second, 1e-6));
        final boxes = line.selectionBoxes(0, line.projection.text.length);
        final edge = side == 'over'
            ? boxes.map((box) => box.top).reduce((a, b) => a < b ? a : b)
            : boxes.map((box) => box.bottom).reduce((a, b) => a > b ? a : b);
        for (final mark in line.marks) {
          expect(
            side == 'over' ? mark.fontBounds.bottom : mark.fontBounds.top,
            side == 'over'
                ? lessThanOrEqualTo(edge + 1e-5)
                : greaterThanOrEqualTo(edge - 1e-5),
          );
        }
      } finally {
        for (final painter in native) {
          painter.dispose();
        }
        line.close();
      }
    });
  }
}

final class _OnceScaler extends TextScaler {
  const _OnceScaler(this.sample);
  final double Function(double) sample;
  @override
  double scale(double size) => sample(size);
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}
