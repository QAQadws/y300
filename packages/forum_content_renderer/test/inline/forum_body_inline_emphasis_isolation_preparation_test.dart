import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

typedef _Natural = ({
  ForumBodyInlineEmphasisParentMetrics metrics,
  ForumBodyInlineParagraphLease parent,
});
typedef _Isolated = ({
  ForumBodyInlineEmphasisIsolationMetrics metrics,
  ForumBodyInlineParagraphLease parent,
});

ForumBodyParagraphCache _cache({int entries = 512}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(cache.close);
  return cache;
}

_Natural _measure(
  MixedEmphasisParentFixture fixture,
  ForumBodyParagraphCache cache, {
  TextScaler scaler = TextScaler.noScaling,
}) {
  final work = ForumBodyInlineEmphasisParentPreparation(
    input: fixture.input,
    cache: cache,
    textScaler: scaler,
    ensureOwner: () {},
  );
  try {
    while (!work.isReady) {
      work.advance(maxParts: 32);
    }
    final value = work.takeMeasurement();
    addTearDown(value.parent.release);
    return value;
  } finally {
    work.close();
  }
}

ForumBodyInlineEmphasisIsolationPreparation _work(
  _Natural input,
  ForumBodyParagraphCache cache, {
  double pitch = 256,
  void Function()? guard,
  Iterable<ForumBodyNativeParagraphLease> Function()? owned,
}) => ForumBodyInlineEmphasisIsolationPreparation(
  metrics: input.metrics,
  natural: input.parent,
  cache: cache,
  ensureOwner: guard ?? () {},
  rowIsolationPitch: pitch,
  additionalOwnedLeases: owned,
);

({int parts, _Isolated value}) _finish(
  ForumBodyInlineEmphasisIsolationPreparation work,
  ForumBodyParagraphCache cache, {
  int quantum = 1,
  bool cachedOnly = false,
}) {
  var parts = 0;
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(200000));
      final before = (cache.layoutBuildCount, cache.pictureBuildCount);
      final s = work.advance(maxParts: quantum, cachedOnly: cachedOnly);
      expect(s.partsPrepared, inInclusiveRange(1, quantum));
      expect(s.nativeLayoutsBuilt, cache.layoutBuildCount - before.$1);
      expect(s.nativeLayoutsBuilt, inInclusiveRange(0, 1));
      expect(s.waitingForLayoutBudget, isFalse);
      expect(work.cacheMiss, isFalse);
      expect(s.picturesRecorded, 0);
      expect(cache.pictureBuildCount, before.$2);
      parts += s.partsPrepared;
    }
    expect(work.advance(maxParts: 1).partsPrepared, 0);
    final value = work.takeMeasurement();
    expect(work.nativeLeases, isEmpty);
    return (parts: parts, value: value);
  } finally {
    work.close();
  }
}

ForumBodyInlineFlowContent _flow(
  String body, {
  TextStyle? style,
  TextDirection direction = TextDirection.ltr,
  String whiteSpace = 'pre-wrap',
}) {
  final doc = const ForumBodyParser().parse(
    html:
        '<p dir="${direction.name}" style="text-emphasis:circle;white-space:$whiteSpace;line-height:.4">$body</p>',
    sourceId: 'isolated-parent',
    conversionIdentity: 'none',
  );
  final cursor = ForumBodyTextFlowCursor(
    document: doc,
    reader: ForumBodyReaderStyle(
      textStyle:
          style ??
          const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            color: Color(0xff123456),
          ),
      fontRevision: 'isolated-parent',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
    ),
  );
  try {
    while (!cursor.isComplete) {
      cursor.advance(maxEvents: 1);
      if (cursor.current case ForumBodyTextFlowInline(:final content)) {
        return content;
      }
    }
    throw StateError('Expected actual mixed flow');
  } finally {
    cursor.close();
  }
}

_Natural _fromFlow(
  ForumBodyInlineFlowContent flow,
  ForumBodyParagraphCache cache, {
  double width = 300,
  TextScaler scaler = TextScaler.noScaling,
}) {
  final job = ForumBodyInlineEmphasisParentPreparation.fromFlow(
    input: flow,
    width: width,
    cache: cache,
    textScaler: scaler,
    ensureOwner: () {},
  );
  try {
    while (!job.isReady) {
      job.advance(maxParts: 32);
    }
    final value = job.takeMeasurement();
    addTearDown(value.parent.release);
    return value;
  } finally {
    job.close();
  }
}

ForumBodyParagraphLease _pin(ForumBodyParagraphCache cache) {
  final doc = const ForumBodyParser().parse(
    html: '<p>pin</p>',
    sourceId: 'pin',
    conversionIdentity: 'none',
  );
  final pin = cache.acquire(
    content: const ForumBodyParagraphContentBuilder().build(
      document: doc,
      styles: const ForumBodyStyleResolver().resolve(
        doc,
        ForumBodyReaderStyle(
          textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
          fontRevision: 'pin',
          linkColor: const Color(0xff0000ff),
        ),
      ),
      path: '0',
    ),
    width: 300,
  );
  addTearDown(pin.release);
  return pin;
}

Future<Uint8List> _raster(
  void Function(Canvas) paint,
  Size size,
  double dpr,
) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder)..scale(dpr));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      (size.width * dpr).ceil(),
      (size.height * dpr).ceil(),
    );
    try {
      return (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
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
  for (final (index, child) in mixedEmphasisChildren.indexed) {
    for (final side in ['over', 'under']) {
      for (final direction in TextDirection.values) {
        for (final scaler in [
          TextScaler.noScaling,
          const MixedEmphasisCurve(),
        ]) {
          for (final width in [70.0, 300.0]) {
            test(
              'final parent isolation $index/$side/$direction/$scaler/$width',
              () {
                final cache = _cache();
                final input = _measure(
                  MixedEmphasisParentFixture(
                    child,
                    width: width,
                    direction: direction,
                    parentStyle:
                        'text-emphasis:circle;text-emphasis-position:$side;line-height:.4',
                    prefix:
                        '<span style="font-size:120px;text-emphasis:none">W</span>P',
                    suffix: 'Q<br>R',
                  ),
                  cache,
                  scaler: scaler,
                );
                final before = cache.layoutBuildCount;
                final result = _finish(
                  _work(input, cache, pitch: 32),
                  cache,
                  quantum: index.isEven ? 1 : 17,
                ).value;
                addTearDown(result.parent.release);
                expect(
                  cache.layoutBuildCount - before,
                  greaterThanOrEqualTo(1),
                );
                expect(result.metrics.natural, same(input.metrics));
                expect(
                  result.metrics.reference.naturalLines,
                  same(input.parent.layout.lines),
                );
                expect(
                  result.metrics.geometry.lines,
                  same(result.parent.layout.lines),
                );
                expect(
                  result.metrics.geometry.nativeInputIdentity,
                  result.parent.nativeInputIdentity,
                );
                expect(result.metrics.geometry.input, same(input.metrics.text));
                expect(
                  result.metrics.geometry.atomLineIndices,
                  input.metrics.geometry.atomLineIndices,
                );
                expect(
                  result.metrics.geometry.atomLineIndices,
                  result.metrics.reference.atomLineIndices,
                );
                expect(
                  result.metrics.rows.rows.length,
                  result.parent.layout.lineCount,
                );
                expect(
                  result.metrics.request.dimensions,
                  input.metrics.page.dimensions,
                );
                expect(
                  result.parent.layout.dimensions,
                  input.parent.layout.dimensions,
                );
                expect(
                  result.parent.layout.rowIsolationPitch,
                  result.metrics.request.rowIsolationPitch,
                );
                expect(result.parent.isActive, isTrue);
                expect(input.parent.isActive, isTrue);
                expect(cache.activeLeases, 2);
                expect(result.parent.layout.isPaintPrepared, isFalse);
                expect(cache.pictureBuildCount, 0);
                final key = result.parent.nativeInputIdentity;
                final pitch = result.metrics.reference.rowIsolationPitch;
                result.parent.release();
                final warmBefore = (
                  cache.layoutBuildCount,
                  cache.pictureBuildCount,
                );
                final warm = _finish(
                  _work(input, cache, pitch: pitch),
                  cache,
                  cachedOnly: true,
                ).value;
                addTearDown(warm.parent.release);
                expect(warm.parent.nativeInputIdentity, key);
                expect((
                  cache.layoutBuildCount,
                  cache.pictureBuildCount,
                ), warmBefore);
              },
            );
          }
        }
      }
    }
  }

  for (final (index, child) in mixedEmphasisChildren.indexed) {
    for (final direction in TextDirection.values) {
      for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
        test('intrinsic request width $index/$direction/$scaler', () {
          final cache = _cache(),
              f = _flow(
                'P${child}Q',
                direction: direction,
                whiteSpace: 'normal',
              );
          final input = _fromFlow(
            ForumBodyInlineFlowContent(
              identity: f.identity,
              path: f.path,
              fontRevision: f.fontRevision,
              styleRevision: f.styleRevision,
              style: f.style,
              layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
              parts: f.parts,
              ignored: f.ignored,
              issues: f.issues,
            ),
            cache,
            scaler: scaler,
          );
          expect(input.parent.layout.width, lessThan(300));
          expect(input.metrics.requestWidth, 300);
          final value = _finish(_work(input, cache), cache).value;
          addTearDown(value.parent.release);
          expect(value.parent.layout.width, input.parent.layout.width);
          expect(
            value.parent.hasSameSourceAndInputsExceptRowIsolation(input.parent),
            isTrue,
          );
          expect(value.metrics.reference.lineCount, 1);
          expect(value.metrics.geometry.targets.length, 2);
        });
      }
    }
  }

  test(
    'long paragraph keeps all parent targets through retry and final geometry',
    () {
      final cache = _cache();
      final input = _fromFlow(
        _flow('${List.filled(4200, 'P').join()}${mixedEmphasisChildren[0]}Q'),
        cache,
      );
      final value = _finish(
        _work(input, cache, pitch: 32),
        cache,
        quantum: 53,
      ).value;
      addTearDown(value.parent.release);
      expect(value.metrics.geometry.targets.length, 4201);
      expect(value.metrics.reference.rowIsolationPitch, greaterThan(32));
      expect(
        value.metrics.geometry.atomLineIndices,
        input.metrics.geometry.atomLineIndices,
      );
      expect(cache.activeLeases, 2);
    },
  );

  test('fractional source fonts survive large physical row coordinates', () {
    final cache = _cache();
    final input = _fromFlow(
      _flow(
        '${'P\n' * 300}${mixedEmphasisChildren[1]}Q',
        style: const TextStyle(fontFamily: 'Ahem', fontSize: 31.3),
      ),
      cache,
    );
    final value = _finish(_work(input, cache), cache, quantum: 31).value;
    addTearDown(value.parent.release);
    expect(value.metrics.reference.lineCount, 301);
    expect(value.parent.layout.lines.last.baseline, greaterThan(76000));
    expect(
      value.metrics.geometry.targets.length,
      input.metrics.geometry.targets.length,
    );
    expect(value.metrics.geometry.lines, same(value.parent.layout.lines));
  });

  test(
    'a whole source grapheme spanning physical rows keeps its actual isolated selection',
    () {
      final cache = _cache();
      final input = _fromFlow(
        _flow(
          '👩‍👩‍👧‍👦é<ruby style="font-size:5px;text-emphasis:none">A<rt>x</rt></ruby>Q',
        ),
        cache,
        width: 10,
      );
      final value = _finish(_work(input, cache), cache).value;
      addTearDown(value.parent.release);
      final before = input.metrics.geometry.targets,
          after = value.metrics.geometry.targets;
      expect(
        before.any(
          (target) => target.sourceEndLine > target.sourceStartLine + 1,
        ),
        isTrue,
      );
      for (final (i, target) in after.indexed) {
        expect(target.unit, same(before[i].unit));
        expect(target.sourceStartLine, before[i].sourceStartLine);
        expect(target.sourceEndLine, before[i].sourceEndLine);
      }
      expect(value.metrics.rows.rows.length, input.metrics.geometry.lineCount);
    },
  );

  for (final mode in ['external', 'owned', 'released']) {
    test('actual natural parent and $mode prefix pressure', () {
      final cache = _cache(entries: 2);
      final input = _measure(
        MixedEmphasisParentFixture(mixedEmphasisChildren[1]),
        cache,
      );
      final pin = _pin(cache);
      var captures = 0;
      final work = _work(
        input,
        cache,
        owned: () {
          captures++;
          if (mode == 'released' && captures == 2) pin.release();
          return mode == 'owned' ? [pin] : [];
        },
      );
      addTearDown(work.close);
      if (mode == 'owned') {
        expect(
          () {
            while (!work.isReady) {
              work.advance(maxParts: 1);
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
        expect(pin.isActive, isTrue);
        expect(input.parent.isActive, isTrue);
        return;
      }
      if (mode == 'external') {
        var waiting = false;
        while (!waiting) {
          waiting = work.advance(maxParts: 1).waitingForLayoutBudget;
        }
        final firstCaptures = captures;
        for (var n = 0; n < 3; n++) {
          final s = work.advance(maxParts: 100);
          expect(s.partsPrepared, 0);
          expect(s.waitingForLayoutBudget, isTrue);
          expect(s.nativeLayoutsBuilt, 0);
          expect(captures, firstCaptures);
        }
        pin.release();
      }
      final value = _finish(work, cache).value;
      addTearDown(value.parent.release);
      expect(input.parent.isActive, isTrue);
      expect(cache.activeLeases, 2);
    });
  }

  test('cold cached-only miss resumes the same transaction', () {
    final cache = _cache();
    final input = _measure(
      MixedEmphasisParentFixture(mixedEmphasisChildren[1]),
      cache,
    );
    final before = cache.layoutBuildCount, work = _work(input, cache);
    for (var n = 0; !work.cacheMiss; n++) {
      expect(n, lessThan(10000));
      work.advance(maxParts: 1, cachedOnly: true);
    }
    expect(cache.layoutBuildCount, before);
    final value = _finish(work, cache).value;
    addTearDown(value.parent.release);
  });

  test(
    'owner retirement at every advance and guard boundary releases only the isolated parent',
    () {
      final cache = _cache();
      final input = _measure(
        MixedEmphasisParentFixture(mixedEmphasisChildren[1]),
        cache,
      );
      final first = _finish(_work(input, cache, pitch: 32), cache).value;
      final pitch = first.metrics.reference.rowIsolationPitch;
      first.parent.release();
      var guardCount = 0;
      final baseline = _work(
        input,
        cache,
        pitch: pitch,
        guard: () {
          guardCount++;
        },
      );
      while (!baseline.isReady) {
        baseline.advance(maxParts: 17, cachedOnly: true);
      }
      baseline.takeMeasurement().parent.release();
      for (var stop = 1; stop <= guardCount; stop++) {
        var count = 0;
        ForumBodyInlineEmphasisIsolationPreparation? active;
        void guard() {
          if (++count == stop) {
            active?.close();
            throw StateError('retired');
          }
        }

        try {
          final work = _work(input, cache, pitch: pitch, guard: guard);
          active = work;
          while (!work.isReady) {
            work.advance(maxParts: 17, cachedOnly: true);
          }
          work.takeMeasurement().parent.release();
        } on StateError {
          /* Retired before handing off its new parent. */
        } finally {
          active?.close();
        }
        expect(count, greaterThanOrEqualTo(stop));
        expect(cache.activeLeases, 1, reason: 'guard $stop');
        expect(input.parent.isActive, isTrue);
      }
      final steps = _finish(_work(input, cache, pitch: pitch), cache);
      steps.value.parent.release();
      for (var stop = 0; stop <= steps.parts; stop++) {
        var retired = false;
        final work = _work(
          input,
          cache,
          pitch: pitch,
          guard: () {
            if (retired) throw StateError('retired');
          },
        );
        for (var n = 0; n < stop && !work.isReady; n++) {
          work.advance(maxParts: 1, cachedOnly: true);
        }
        retired = true;
        expect(() => work.advance(maxParts: 1), throwsStateError);
        work.close();
        expect(cache.activeLeases, 1);
      }
    },
  );

  test(
    'released natural parent, foreign source and foreign prefix reject without releasing caller handles',
    () {
      final cache = _cache(), foreign = _cache();
      final fixture = MixedEmphasisParentFixture(mixedEmphasisChildren[1]);
      final input = _measure(fixture, cache),
          other = _measure(fixture, foreign);
      expect(
        () => ForumBodyInlineEmphasisIsolationPreparation(
          metrics: input.metrics,
          natural: other.parent,
          cache: cache,
          ensureOwner: () {},
        ),
        throwsStateError,
      );
      expect(() {
        _finish(_work(input, cache, owned: () => [other.parent]), cache);
      }, throwsStateError);
      expect(other.parent.isActive, isTrue);
      final ready = _work(input, cache);
      while (!ready.isReady) {
        ready.advance(maxParts: 17);
      }
      input.parent.release();
      expect(ready.takeMeasurement, throwsStateError);
      expect(cache.activeLeases, 0);
    },
  );

  for (final budget in ['boxes', 'queries', 'prefix']) {
    test('$budget limit retires only owned work', () {
      final cache = _cache();
      final input = _measure(
        MixedEmphasisParentFixture(mixedEmphasisChildren[1]),
        cache,
      );
      final work = ForumBodyInlineEmphasisIsolationPreparation(
        metrics: input.metrics,
        natural: input.parent,
        cache: cache,
        ensureOwner: () {},
        maxBoxes: budget == 'boxes' ? 0 : 32768,
        maxGlyphQueries: budget == 'queries' ? 0 : 16384,
        maxOwnedLeases: budget == 'prefix' ? 1 : 32768,
        additionalOwnedLeases: budget == 'prefix' ? () => [input.parent] : null,
      );
      expect(() {
        while (!work.isReady) {
          work.advance(maxParts: 1);
        }
      }, throwsA(isA<ForumBodyEmphasisGeometryException>()));
      expect(cache.activeLeases, 1);
      expect(input.parent.isActive, isTrue);
    });
  }

  test(
    'insufficient maximum pitch fails instead of delivering overlapping strips',
    () {
      final cache = _cache();
      final input = _fromFlow(
        _flow(
          'P\n${mixedEmphasisChildren[0]}Q',
          style: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            shadows: [Shadow(blurRadius: 5000)],
          ),
        ),
        cache,
      );
      final work = _work(input, cache, pitch: 16384);
      expect(
        () {
          while (!work.isReady) {
            work.advance(maxParts: 17);
          }
        },
        throwsA(
          isA<ForumBodyParagraphRowException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphRowFailure.isolation,
          ),
        ),
      );
      expect(input.parent.isActive, isTrue);
      expect(cache.activeLeases, 1);
      expect(cache.pictureBuildCount, 0);
    },
  );

  test(
    'actual post-reflow parent strips reproduce the prepared full glyph paint at DPR1 and 3',
    () async {
      final cache = _cache();
      final input = _fromFlow(
        _flow(
          'P\n${mixedEmphasisChildren[1]}Q',
          style: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            color: Color(0xff123456),
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.wavy,
            shadows: [Shadow(blurRadius: 1.5, offset: Offset(2, 3))],
          ),
        ),
        cache,
        width: 70,
      );
      final value = _finish(_work(input, cache, pitch: 32), cache).value;
      addTearDown(value.parent.release);
      final view = ForumBodyInlineParentRowView.bind(
        parent: value.parent,
        rows: value.metrics.rows,
        ensureOwner: () {},
      );
      expect(view.isPaintPrepared, isFalse);
      cache.prepareInlineParentPaint(value.parent);
      final size = Size(170, value.parent.layout.height + 120);
      for (final dpr in [1.0, 3.0]) {
        final whole = await _raster(
          (c) => value.parent.layout.paintParent(c, const Offset(50, 60)),
          size,
          dpr,
        );
        final strips = await _raster(
          (c) {
            for (final (i, row) in value.metrics.rows.rows.indexed) {
              view.paintParentRow(c, Offset(50, 60 + row.selector.originY), i);
            }
          },
          size,
          dpr,
        );
        expect(strips, orderedEquals(whole));
        expect(
          [
            for (var i = 3; i < whole.length; i += 4) whole[i],
          ].any((a) => a != 0),
          isTrue,
        );
      }
    },
  );
}
