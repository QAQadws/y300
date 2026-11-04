import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

typedef _Input = ({
  ForumBodyInlineEmphasisRowAllocation allocation,
  ForumBodyInlineParagraphLease natural,
  ForumBodyInlineParagraphLease source,
  ForumBodyInlinePaintInput paint,
  List<ForumBodyInlineParagraphLease> phases,
});

const _font = TextStyle(
  fontFamily: 'Ahem',
  fontSize: 20,
  color: Color(0xff123456),
);
ForumBodyParagraphCache _cache() {
  final c = ForumBodyParagraphCache(
    maxEntries: 512,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(c.close);
  return c;
}

_Input _input(
  ForumBodyParagraphCache cache, {
  String? child,
  double width = 70,
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  TextStyle style = _font,
  String prefix = 'ffi é中 ',
  String suffix = ' QQ',
  String parentStyle = 'text-emphasis:circle;line-height:.4',
  ForumBodyParagraphLayoutMode? layoutMode,
}) {
  final fixture = MixedEmphasisParentFixture(
    child ?? mixedEmphasisChildren[1],
    width: width,
    direction: direction,
    readerTextStyle: style,
    prefix: prefix,
    suffix: suffix,
    parentStyle: parentStyle,
    layoutMode: layoutMode,
  );
  final p = ForumBodyInlineEmphasisParentPreparation(
    input: fixture.input,
    cache: cache,
    textScaler: scaler,
    ensureOwner: () {},
  );
  try {
    while (!p.isReady) {
      p.advance(maxParts: 32);
    }
    final natural = p.takeMeasurement();
    addTearDown(natural.parent.release);
    final iso = ForumBodyInlineEmphasisIsolationPreparation(
      metrics: natural.metrics,
      natural: natural.parent,
      cache: cache,
      ensureOwner: () {},
    );
    try {
      while (!iso.isReady) {
        iso.advance(maxParts: 32);
      }
      final isolated = iso.takeMeasurement();
      addTearDown(isolated.parent.release);
      final work = ForumBodyInlineEmphasisRowAllocationPreparation(
        input: isolated.metrics,
        natural: natural.parent,
        isolated: isolated.parent,
        ensureOwner: () {},
      );
      try {
        while (!work.isReady) {
          work.advance(maxParts: 32);
        }
        final allocation = work.takeAllocation(),
            paint = ForumBodyInlinePaintInput(isolated.parent.content);
        final phases = [paint.background, paint.foreground, paint.decoration]
            .map((content) {
              final lease = cache.acquireInline(
                content: content,
                width: width,
                dimensions: isolated.parent.layout.dimensions,
                textScaler: natural.metrics.textScaler,
                layoutMode: isolated.metrics.request.layoutMode,
                rowIsolationPitch: isolated.parent.layout.rowIsolationPitch,
              );
              addTearDown(lease.release);
              return lease;
            })
            .toList();
        return (
          allocation: allocation,
          natural: natural.parent,
          source: isolated.parent,
          paint: paint,
          phases: phases,
        );
      } finally {
        work.close();
      }
    } finally {
      iso.close();
    }
  } finally {
    p.close();
  }
}

ForumBodyInlineEmphasisPaintReferencePreparation _work(
  _Input input, {
  List<ForumBodyInlineParagraphLease>? phases,
  void Function()? guard,
  int maxLines = 4096,
  int maxAtoms = 512,
  int maxBoxes = 32768,
  int maxGlyphQueries = 65536,
}) => ForumBodyInlineEmphasisPaintReferencePreparation(
  allocation: input.allocation,
  paintInput: input.paint,
  source: input.source,
  phases: phases ?? input.phases,
  ensureOwner: guard ?? () {},
  maxLines: maxLines,
  maxAtoms: maxAtoms,
  maxBoxes: maxBoxes,
  maxGlyphQueries: maxGlyphQueries,
);

({ForumBodyInlineEmphasisPaintReference reference, int parts}) _finish(
  ForumBodyInlineEmphasisPaintReferencePreparation work,
  ForumBodyParagraphCache cache, {
  int quantum = 1,
}) {
  final before = (
    cache.layoutBuildCount,
    cache.pictureBuildCount,
    cache.hitCount,
    cache.activeLeases,
  );
  var parts = 0;
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(200000));
      final used = work.advance(maxParts: quantum);
      expect(used, inInclusiveRange(1, quantum));
      parts += used;
    }
    expect(work.advance(maxParts: 1), 0);
    final reference = work.takeReference();
    expect((
      cache.layoutBuildCount,
      cache.pictureBuildCount,
      cache.hitCount,
      cache.activeLeases,
    ), before);
    return (reference: reference, parts: parts);
  } finally {
    work.close();
  }
}

ForumBodyInlineEmphasisPaintView _view(
  _Input input,
  ForumBodyInlineEmphasisPaintReference ref, {
  void Function()? guard,
  List<ForumBodyInlineParagraphLease>? phases,
}) => ForumBodyInlineEmphasisPaintView.bind(
  reference: ref,
  source: input.source,
  phases: phases ?? input.phases,
  ensureOwner: guard ?? () {},
);

Future<List<int>> _pixels(
  void Function(Canvas) draw,
  Size size,
  double dpr,
) async {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec)..scale(dpr));
  final pic = rec.endRecording();
  try {
    final image = await pic.toImage(
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
    pic.dispose();
  }
}

Matcher _failure(ForumBodyEmphasisAllocationFailure f) => throwsA(
  isA<ForumBodyEmphasisAllocationException>().having(
    (e) => e.failure,
    'failure',
    f,
  ),
);

({Rect bounds, double mass, double centerY}) _ink(List<int> pixels, int width) {
  var left = width, right = -1, top = pixels.length, bottom = -1;
  double mass = 0, moment = 0;
  for (var n = 3; n < pixels.length; n += 4) {
    final alpha = pixels[n];
    if (alpha == 0) continue;
    final point = n ~/ 4, x = point % width, y = point ~/ width;
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
    mass += alpha;
    moment += alpha * y;
  }
  expect(mass, greaterThan(0));
  return (
    bounds: Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right.toDouble(),
      bottom.toDouble(),
    ),
    mass: mass,
    centerY: moment / mass,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final (i, child) in mixedEmphasisChildren.indexed) {
    for (final dir in TextDirection.values) {
      for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
        for (final width in [70.0, 300.0]) {
          test('current native phase qualification $i/$dir/$scaler/$width', () {
            final cache = _cache(),
                input = _input(
                  cache,
                  child: child,
                  direction: dir,
                  scaler: scaler,
                  width: width,
                  style: _font.copyWith(
                    backgroundColor: const Color(0x44226688),
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.wavy,
                    shadows: const [
                      Shadow(offset: Offset(2, -3), blurRadius: 2),
                    ],
                  ),
                );
            final result = _finish(_work(input), cache), ref = result.reference;
            expect(ref.allocation, same(input.allocation));
            expect(ref.paintInput, same(input.paint));
            expect(ref.sourceLines, same(input.source.layout.lines));
            expect(
              ref.phaseInputIdentities,
              input.phases.map((p) => p.nativeInputIdentity),
            );
            expect(ref.glyphQueries, greaterThan(0));
            expect(ref.glyphQueries % 4, 0);
            expect(ref.nativeFootprint, hasLength(4));
            expect(() => ref.requests.clear(), throwsUnsupportedError);
            final before = (
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.hitCount,
              cache.activeLeases,
            );
            final probe = cache.createBudgetProbe(captureInputEstimates: true);
            try {
              for (final slot in ref.nativeFootprint) {
                slot.request.includeBudget(
                  probe,
                  width: slot.width,
                  textScaler: input.allocation.input.natural.textScaler,
                  minimumLineCount: slot.minimumLineCount,
                );
              }
              expect(probe.snapshotNativeEstimates(), hasLength(4));
            } finally {
              probe.close();
            }
            expect((
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.hitCount,
              cache.activeLeases,
            ), before);
            final view = _view(input, ref);
            expect(view.nativeLeases.toSet(), {input.source, ...input.phases});
            expect(view.isPaintPrepared, isFalse);
            final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
            expect(
              () => view.paintPhaseRow(
                canvas,
                Offset.zero,
                0,
                ForumBodyParagraphPaintLayer.foreground,
              ),
              throwsStateError,
            );
            recorder.endRecording().dispose();
          });
        }
        test(
          'allocated foreground agrees with independent natural native baseline $i/$dir/$scaler',
          () async {
            final cache = _cache(),
                input = _input(
                  cache,
                  child: child,
                  width: 800,
                  direction: dir,
                  scaler: scaler,
                  style: _font.copyWith(
                    shadows: const [
                      Shadow(offset: Offset(2, -3), blurRadius: 2),
                    ],
                  ),
                );
            final ref = _finish(_work(input), cache).reference,
                view = _view(input, ref);
            expect(input.natural.layout.lineCount, 1);
            for (final p in input.phases) {
              cache.prepareInlineParentPaint(p);
            }
            cache.prepareInlineParentPaint(input.natural);
            expect(view.isPaintPrepared, isTrue);
            final row = input.allocation.rows.single,
                natural = input.natural.layout,
                shift =
                    row.line.baseline -
                    (natural.nativeFlowTop +
                        natural.nativeAlphabeticBaseline.roundToDouble());
            final before = (
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.hitCount,
              cache.activeLeases,
            );
            for (final dpr in [1.0, 3.0]) {
              final size = Size(1000, input.allocation.height + 200);
              final expected = await _pixels(
                (c) => natural.paintParent(c, Offset(100, 100 + shift)),
                size,
                dpr,
              );
              final actual = await _pixels(
                (c) => view.paintPhaseRow(
                  c,
                  const Offset(100, 100),
                  0,
                  ForumBodyParagraphPaintLayer.foreground,
                ),
                size,
                dpr,
              );
              expect(actual, expected, reason: 'independent natural/DPR $dpr');
              expect(
                [
                  for (var n = 3; n < actual.length; n += 4) actual[n],
                ].any((a) => a > 0),
                isTrue,
              );
            }
            expect((
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.hitCount,
              cache.activeLeases,
            ), before);
          },
        );
      }
    }
  }

  for (final dir in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
      test(
        'opaque logical phases agree with independent natural parent $dir/$scaler',
        () async {
          final cache = _cache(),
              input = _input(
                cache,
                child: mixedEmphasisChildren.first,
                prefix: '',
                suffix: '',
                width: 300,
                direction: dir,
                scaler: scaler,
                style: _font.copyWith(
                  backgroundColor: const Color(0x44226688),
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.wavy,
                ),
              );
          final ref = _finish(_work(input), cache).reference,
              view = _view(input, ref);
          expect(input.allocation.rows.single.parentFontBounds, isNull);
          for (final p in input.phases) {
            cache.prepareInlineParentPaint(p);
          }
          cache.prepareInlineParentPaint(input.source);
          for (final dpr in [1.0, 3.0]) {
            final size = Size(500, input.allocation.height + 200);
            final expected = await _pixels(
              (c) {
                final offset =
                    const Offset(100, 100) +
                    input.allocation.rows.single.logicalOffset;
                c.translate(offset.dx, offset.dy);
                input.source.layout.paintParent(c, Offset.zero);
              },
              size,
              dpr,
            );
            final actual = await _pixels(
              (c) {
                for (final layer in [
                  ForumBodyParagraphPaintLayer.background,
                  ForumBodyParagraphPaintLayer.foreground,
                  ForumBodyParagraphPaintLayer.decoration,
                ]) {
                  view.paintPhaseRow(c, const Offset(100, 100), 0, layer);
                }
              },
              size,
              dpr,
            );
            expect(
              actual,
              expected,
              reason: 'whole native layer conservation/DPR $dpr',
            );
            for (final i in [0, 2]) {
              final p = cache.acquireInline(
                content: ref.requests[i].content,
                width: input.allocation.input.natural.requestWidth,
                dimensions: input.natural.layout.dimensions,
                textScaler: input.allocation.input.natural.textScaler,
                layoutMode: input.allocation.input.request.layoutMode,
              );
              try {
                cache.prepareInlineParentPaint(p);
                final one = await _pixels(
                  (c) => p.layout.paintParent(
                    c,
                    const Offset(100, 100) +
                        input.allocation.rows.single.naturalOffset,
                  ),
                  size,
                  dpr,
                );
                final two = await _pixels(
                  (c) => view.paintPhaseRow(
                    c,
                    const Offset(100, 100),
                    0,
                    i == 0
                        ? ForumBodyParagraphPaintLayer.background
                        : ForumBodyParagraphPaintLayer.decoration,
                  ),
                  size,
                  dpr,
                );
                if (i == 0) {
                  expect(
                    two,
                    one,
                    reason: 'independent natural background/DPR $dpr',
                  );
                } else {
                  // Wavy paths at different native Float32 origins can choose
                  // different AA tessellation at DPR3. Preserve exact whole-
                  // resource RGBA above; independently verify natural ink
                  // extent, vertical location and integrated coverage here.
                  final a = _ink(one, (size.width * dpr).ceil()),
                      b = _ink(two, (size.width * dpr).ceil());
                  expect(b.bounds, a.bounds);
                  expect(b.centerY, closeTo(a.centerY, .01));
                  expect((b.mass - a.mass).abs() / a.mass, lessThan(.01));
                }
              } finally {
                p.release();
              }
            }
          }
        },
      );
    }
  }

  test(
    'intrinsic parent keeps request width distinct from native output width',
    () {
      final cache = _cache(),
          input = _input(
            cache,
            width: 800,
            layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
          );
      expect(input.source.layout.width, lessThan(800));
      final ref = _finish(_work(input), cache).reference;
      expect(ref.nativeFootprint.every((r) => r.width == 800), isTrue);
      expect(
        ref.requests.every(
          (r) =>
              r.layoutMode == ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        ),
        isTrue,
      );
      expect(_view(input, ref).nativeLeases, hasLength(4));
    },
  );

  test(
    'mechanical indent and hidden/complex scalars retain exact phase inputs',
    () {
      final cache = _cache(),
          input = _input(
            cache,
            width: 300,
            parentStyle: 'text-emphasis:circle;line-height:.4;text-indent:1em',
            prefix: '👩‍👩‍👧‍👦 é',
            suffix: '<span style="visibility:hidden">hidden</span>Q',
          );
      expect(input.source.layout.projection.enginePrefix, isNotEmpty);
      final ref = _finish(_work(input), cache).reference;
      final projection = input.source.layout.projection;
      expect(
        ref.glyphQueries,
        4 *
            (projection.engineText.runes.length -
                projection.enginePrefix.runes.length),
      );
      expect(_view(input, ref).nativeLeases, hasLength(4));
    },
  );

  test(
    'request mismatch, foreign owner and phase ordering preserve borrowed resources',
    () {
      final cache = _cache(),
          input = _input(cache),
          before = cache.activeLeases;
      final reversed = [input.phases[2], input.phases[1], input.phases[0]];
      expect(
        () => _finish(_work(input, phases: reversed), cache),
        _failure(ForumBodyEmphasisAllocationFailure.source),
      );
      for (final mutation in ['width', 'scale', 'pitch', 'dimensions']) {
        final r = input.allocation.input.request;
        final wrong = cache.acquireInline(
          content: input.paint.background,
          width: mutation == 'width'
              ? 100
              : input.allocation.input.natural.requestWidth,
          textScaler: mutation == 'scale'
              ? TextScaler.linear(2)
              : input.allocation.input.natural.textScaler,
          rowIsolationPitch: mutation == 'pitch' ? 512 : r.rowIsolationPitch,
          dimensions: mutation == 'dimensions'
              ? [
                  for (final d in r.dimensions)
                    PlaceholderDimensions(
                      size: Size(d.size.width, d.size.height + 1),
                      alignment: d.alignment,
                      baseline: d.baseline,
                      baselineOffset: d.baselineOffset,
                    ),
                ]
              : r.dimensions,
          layoutMode: r.layoutMode,
        );
        try {
          expect(
            () => _finish(
              _work(input, phases: [wrong, ...input.phases.skip(1)]),
              cache,
            ),
            _failure(ForumBodyEmphasisAllocationFailure.source),
          );
        } finally {
          wrong.release();
        }
      }
      final foreign = _input(_cache());
      expect(() => _work(input, phases: foreign.phases), throwsStateError);
      expect(cache.activeLeases, before);
      expect(
        () => _work(input, phases: []),
        _failure(ForumBodyEmphasisAllocationFailure.source),
      );
    },
  );

  test(
    'all limits and every cancellation slice leave four borrowed inputs active',
    () {
      final cache = _cache(),
          input = _input(cache),
          result = _finish(_work(input), cache),
          before = cache.activeLeases;
      for (final limits in [
        (1, 512, 32768, 65536),
        (4096, 0, 32768, 65536),
        (4096, 512, 0, 65536),
        (4096, 512, 32768, 0),
      ]) {
        expect(
          () => _finish(
            _work(
              input,
              maxLines: limits.$1,
              maxAtoms: limits.$2,
              maxBoxes: limits.$3,
              maxGlyphQueries: limits.$4,
            ),
            cache,
          ),
          _failure(ForumBodyEmphasisAllocationFailure.limit),
        );
      }
      for (var stop = 1; stop <= result.parts; stop++) {
        var alive = true;
        final job = _work(
          input,
          guard: () {
            if (!alive) throw StateError('retired');
          },
        );
        for (var n = 0; n < stop; n++) {
          job.advance(maxParts: 1);
        }
        alive = false;
        expect(() => job.advance(maxParts: 1), throwsStateError);
        expect(job.takeReference, throwsStateError);
        job.close();
      }
      expect(cache.activeLeases, before);
      expect(input.phases.every((p) => p.isActive), isTrue);
    },
  );

  test(
    'eviction requires fresh actual phase line qualification even at same key',
    () {
      final cache = _cache(),
          input = _input(cache),
          ref = _finish(_work(input), cache).reference;
      final oldKey = input.phases[0].nativeInputIdentity;
      input.phases[0].release();
      cache.clearUnpinned();
      final request = ref.requests[0],
          fresh = request.acquire(
            cache,
            width: input.allocation.input.natural.requestWidth,
            textScaler: input.allocation.input.natural.textScaler,
            cachedOnly: false,
          )!;
      addTearDown(fresh.release);
      expect(fresh.nativeInputIdentity, oldKey);
      final parents = [fresh, ...input.phases.skip(1)];
      expect(
        () => _view(input, ref, phases: parents),
        _failure(ForumBodyEmphasisAllocationFailure.source),
      );
      final next = _finish(_work(input, phases: parents), cache).reference;
      expect(_view(input, next, phases: parents).nativeLeases, hasLength(4));
    },
  );

  test(
    'view enforces owner, preparation, finite offsets, layer and row without mutating cache',
    () {
      final cache = _cache(),
          input = _input(cache),
          ref = _finish(_work(input), cache).reference;
      var alive = true;
      final view = _view(
        input,
        ref,
        guard: () {
          if (!alive) throw StateError('retired');
        },
      );
      for (final p in input.phases) {
        cache.prepareInlineParentPaint(p);
      }
      final before = (
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            cache.hitCount,
            cache.activeLeases,
          ),
          recorder = ui.PictureRecorder(),
          canvas = Canvas(recorder);
      try {
        expect(
          () => view.paintPhaseRow(
            canvas,
            const Offset(double.nan, 0),
            0,
            ForumBodyParagraphPaintLayer.background,
          ),
          throwsArgumentError,
        );
        expect(
          () => view.paintPhaseRow(
            canvas,
            Offset.zero,
            0,
            ForumBodyParagraphPaintLayer.all,
          ),
          throwsArgumentError,
        );
        expect(
          () => view.paintPhaseRow(
            canvas,
            Offset.zero,
            -1,
            ForumBodyParagraphPaintLayer.background,
          ),
          throwsRangeError,
        );
        alive = false;
        expect(
          () => view.paintPhaseRow(
            canvas,
            Offset.zero,
            0,
            ForumBodyParagraphPaintLayer.background,
          ),
          throwsStateError,
        );
        alive = true;
        input.phases[1].release();
        expect(view.isPaintPrepared, isFalse);
        expect(
          () => view.paintPhaseRow(
            canvas,
            Offset.zero,
            0,
            ForumBodyParagraphPaintLayer.background,
          ),
          throwsStateError,
        );
      } finally {
        recorder.endRecording().dispose();
      }
      expect(
        (
          cache.layoutBuildCount,
          cache.pictureBuildCount,
          cache.hitCount,
          cache.activeLeases,
        ),
        (before.$1, before.$2, before.$3, before.$4 - 1),
      );
    },
  );

  test(
    'matching current inline request rejects retirement during scaler sampling',
    () {
      final cache = _cache(),
          input = _input(cache),
          p = input.phases[0],
          r = input.allocation.input.request;
      final scaler = _RetiringScaler(p.release);
      expect(
        () => p.matchesNativeInputs(
          content: input.paint.background,
          width: input.allocation.input.natural.requestWidth,
          dimensions: r.dimensions,
          textScaler: scaler,
          layoutMode: r.layoutMode,
          rowIsolationPitch: r.rowIsolationPitch,
        ),
        throwsStateError,
      );
      expect(p.isActive, isFalse);
    },
  );
}

final class _RetiringScaler extends TextScaler {
  const _RetiringScaler(this.retire);
  final void Function() retire;
  @override
  double scale(double size) {
    retire();
    return size;
  }

  @override
  double get textScaleFactor => throw StateError('Use font sizes');
}
