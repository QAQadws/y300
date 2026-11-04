import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

ForumBodyParagraphCache _cache({int entries = 512}) {
  final c = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(c.close);
  return c;
}

MixedEmphasisAllocatedSource _source(
  ForumBodyParagraphCache cache, {
  String? child,
  String prefix = 'P',
  String suffix = 'Q',
  TextScaler scaler = TextScaler.noScaling,
  TextDirection direction = TextDirection.ltr,
  double width = 300,
  String style = 'text-emphasis:circle;line-height:.4',
}) => measureMixedEmphasisAllocatedSource(
  MixedEmphasisParentFixture(
    child ?? mixedEmphasisChildren.first,
    prefix: prefix,
    suffix: suffix,
    parentStyle: style,
    direction: direction,
    width: width,
  ),
  cache,
  scaler: scaler,
);

ForumBodyInlineEmphasisMarkerPreparation _work(
  MixedEmphasisAllocatedSource s,
  ForumBodyParagraphCache c, {
  TextScaler scaler = TextScaler.noScaling,
  int start = 0,
  int? end,
  int marks = 32768,
  int fonts = 2048,
  int handles = 32768,
  void Function()? guard,
  void Function()? visible,
  Iterable<ForumBodyNativeParagraphLease> Function()? owned,
}) => ForumBodyInlineEmphasisMarkerPreparation(
  allocation: s.allocation,
  natural: s.natural,
  cache: c,
  expectedTextScaler: scaler,
  ensureOwner: guard ?? () {},
  ensureVisibleOwner: visible,
  additionalOwnedLeases: owned ?? () => [s.source],
  startLine: start,
  endLine: end,
  maxMarks: marks,
  maxFonts: fonts,
  maxOwnedLeases: handles,
);

({ForumBodyInlineEmphasisMarkerBinding binding, int parts}) _finish(
  ForumBodyInlineEmphasisMarkerPreparation work,
  ForumBodyParagraphCache c, {
  int quantum = 1,
  bool cachedOnly = false,
}) {
  var used = 0;
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(100000));
      final before = (c.layoutBuildCount, c.pictureBuildCount),
          step = work.advance(maxParts: quantum, cachedOnly: cachedOnly);
      expect(step.partsPrepared, inInclusiveRange(1, quantum));
      expect(step.nativeLayoutsBuilt, c.layoutBuildCount - before.$1);
      expect(step.nativeLayoutsBuilt, lessThanOrEqualTo(1));
      expect(step.picturesRecorded, 0);
      expect(c.pictureBuildCount, before.$2);
      expect(step.waitingForLayoutBudget, isFalse);
      expect(work.cacheMiss, isFalse);
      used += step.partsPrepared;
    }
    final binding = work.takeBinding();
    expect(work.nativeLeases, isEmpty);
    return (binding: binding, parts: used);
  } finally {
    work.close();
  }
}

ForumBodyTextPictureLease _scene(
  MixedEmphasisAllocatedSource s,
  ForumBodyInlineEmphasisMarkerBinding binding,
  ForumBodyParagraphCache c,
) {
  ForumBodyTextPicturePreparation? job;
  job = ForumBodyTextPicturePreparation.cooperative(
    cache: c,
    input: binding.pictureInput!,
    text: const [],
    marks: binding.fonts,
    ensureOwner: () {},
    additionalOwnedLeases: () => [
      s.natural,
      s.source,
      ...binding.nativeLeases,
      ...?job?.nativeLeases,
    ],
  );
  try {
    for (var n = 0; !job.isReady; n++) {
      expect(n, lessThan(100000));
      final before = c.layoutBuildCount, step = job.advance(maxParts: 1);
      expect(c.layoutBuildCount, before);
      expect(step.picturesRecorded, lessThanOrEqualTo(1));
      expect(step.waitingForLayoutBudget, isFalse);
    }
    return job.takeLease();
  } finally {
    job.close();
  }
}

Future<List<int>> _pixels(void Function(Canvas) draw, Size size) async {
  const dpr = 1.25;
  final r = ui.PictureRecorder();
  draw(Canvas(r)..scale(dpr));
  final p = r.endRecording();
  try {
    final img = await p.toImage(
      (size.width * dpr).ceil(),
      (size.height * dpr).ceil(),
    );
    try {
      return (await img.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
    } finally {
      img.dispose();
    }
  } finally {
    p.dispose();
  }
}

ForumBodyParagraphLease _pin(ForumBodyParagraphCache c, int i) {
  final d = const ForumBodyParser().parse(
        html: '<p>marker-pin$i</p>',
        sourceId: 'marker-pin$i',
        conversionIdentity: 'none',
      ),
      styles = const ForumBodyStyleResolver().resolve(
        d,
        ForumBodyReaderStyle(
          textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
          fontRevision: 'marker-pin',
          linkColor: const Color(0xff0000ff),
        ),
      ),
      p = c.acquire(
        content: const ForumBodyParagraphContentBuilder().build(
          document: d,
          path: '0',
          styles: styles,
        ),
        width: 300,
      );
  addTearDown(p.release);
  return p;
}

Matcher _failure(ForumBodyEmphasisAllocationFailure f) => throwsA(
  isA<ForumBodyEmphasisAllocationException>().having(
    (e) => e.failure,
    'failure',
    f,
  ),
);

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
        for (final width in [180.0, 300.0]) {
          test(
            'real marker fonts and shared scene $i/$dir/$scaler/$width',
            () async {
              final c = _cache(),
                  s = _source(
                    c,
                    child: child,
                    direction: dir,
                    scaler: scaler,
                    width: width,
                    prefix:
                        '<span style="font-size:33px;text-emphasis:triangle;text-emphasis-position:under">P</span>中',
                  ),
                  before = c.activeLeases;
              c.clearUnpinned();
              final binding = _finish(
                _work(s, c, scaler: scaler),
                c,
                quantum: 512,
              ).binding;
              try {
                expect(
                  binding.pictureInput!.commands,
                  hasLength(s.allocation.marks.length),
                );
                expect(binding.fonts.length, greaterThanOrEqualTo(2));
                expect(() => binding.fonts.clear(), throwsUnsupportedError);
                final leases = {
                      for (final f in binding.fonts) f.nativeInputIdentity: f,
                    },
                    a = s.allocation,
                    m = a.input.natural,
                    placement = m.reflow.children.placement,
                    picture = _scene(s, binding, c);
                try {
                  // Record the independent native reference in logical space.
                  // Applying DPR before recording can change native edge and
                  // shadow rounding by one channel level on the device.
                  final recorder = ui.PictureRecorder(),
                      canvas = Canvas(recorder);
                  canvas.translate(0, -binding.top);
                  for (final mark in placement.marks) {
                    final f = placement.input.fonts.fonts[mark.fontIndex],
                        shift = a.rows[mark.lineIndex].naturalOffset;
                    canvas.save();
                    canvas.translate(shift.dx, shift.dy);
                    canvas.translate(
                      0,
                      m.reflow.baselineDeltas[mark.lineIndex],
                    );
                    canvas.translate(
                      mark.baselineOrigin.dx,
                      mark.baselineOrigin.dy,
                    );
                    leases[f.nativeInputIdentity]!.layout.paint(
                      canvas,
                      mark.fontOffset,
                    );
                    canvas.restore();
                  }
                  final reference = recorder.endRecording();
                  try {
                    final size = Size(width + 100, binding.height + 100),
                        expected = await _pixels((canvas) {
                          canvas.translate(50, 50);
                          canvas.drawPicture(reference);
                        }, size),
                        actual = await _pixels(
                          (canvas) =>
                              picture.paint(canvas, const Offset(50, 50)),
                          size,
                        );
                    expect(expected.where((x) => x != 0), isNotEmpty);
                    expect(actual, orderedEquals(expected));
                    binding.close();
                    // The existing scene owns an independent drawing, not fonts.
                    c.clearUnpinned();
                    expect(
                      await _pixels(
                        (canvas) => picture.paint(canvas, const Offset(50, 50)),
                        size,
                      ),
                      orderedEquals(actual),
                    );
                  } finally {
                    reference.dispose();
                  }
                } finally {
                  picture.release();
                }
              } finally {
                binding.close();
              }
              expect(c.activeLeases, before);
              final warm = _finish(_work(s, c, scaler: scaler), c).binding;
              warm.close();
              final counts = (c.layoutBuildCount, c.pictureBuildCount),
                  cached = _finish(
                    _work(s, c, scaler: scaler),
                    c,
                    cachedOnly: true,
                  ).binding;
              cached.close();
              expect((c.layoutBuildCount, c.pictureBuildCount), counts);
            },
          );
        }
      }
    }
  }

  test(
    'actual legal fragment selects its markers and preserves transform chain',
    () {
      final c = _cache(),
          s = _source(
            c,
            child:
                '${mixedEmphasisChildren.first}\nP${mixedEmphasisChildren.first}\nQ',
            prefix: 'R',
            suffix: '',
            style: 'text-emphasis:circle;line-height:.4;white-space:pre-wrap',
          );
      expect(s.allocation.rows.length, 3);
      for (var row = 0; row < 3; row++) {
        final b = _finish(_work(s, c, start: row, end: row + 1), c).binding,
            selected = s.allocation.marks
                .where((m) => m.lineIndex == row)
                .toList();
        try {
          expect(b.pictureInput!.commands.length, selected.length);
          for (final (i, cmd) in b.pictureInput!.commands.indexed) {
            expect(cmd.sceneOffset, selected[i].offset - Offset(0, b.top));
            expect(cmd.translationDepth, greaterThanOrEqualTo(1));
          }
        } finally {
          b.close();
        }
      }
    },
  );

  test(
    'opaque-only and punctuation-only windows acquire no invented markers',
    () {
      for (final prefix in ['', '，。！？']) {
        final c = _cache(),
            s = _source(c, prefix: prefix, suffix: ''),
            before = (c.layoutBuildCount, c.pictureBuildCount, c.activeLeases),
            b = _finish(_work(s, c, fonts: 0, handles: 1), c).binding;
        expect(b.pictureInput, isNull);
        expect(b.fonts, isEmpty);
        expect(b.isActive, isTrue);
        b.close();
        expect(b.isActive, isFalse);
        expect((
          c.layoutBuildCount,
          c.pictureBuildCount,
          c.activeLeases,
        ), before);
      }
    },
  );

  test(
    'cached miss resumes same worker without native work or lost aliases',
    () {
      final c = _cache(), s = _source(c), before = c.activeLeases;
      c.clearUnpinned();
      final w = _work(s, c), counts = (c.layoutBuildCount, c.pictureBuildCount);
      for (var n = 0; !w.cacheMiss; n++) {
        expect(n, lessThan(10000));
        w.advance(maxParts: 32, cachedOnly: true);
      }
      expect((c.layoutBuildCount, c.pictureBuildCount), counts);
      _finish(w, c).binding.close();
      expect(c.activeLeases, before);
    },
  );

  test('real external pins wait on one revision and resume', () {
    final c = _cache(entries: 16), s = _source(c);
    c.clearUnpinned();
    final pins = [for (var i = 0; i < 14; i++) _pin(c, i)], w = _work(s, c);
    for (var n = 0; ; n++) {
      expect(n, lessThan(10000));
      if (w.advance(maxParts: 32).waitingForLayoutBudget) break;
    }
    final counts = (
      c.layoutBuildCount,
      c.pictureBuildCount,
      c.hitCount,
      c.activeLeases,
    );
    for (var i = 0; i < 4; i++) {
      final step = w.advance();
      expect(step.waitingForLayoutBudget, isTrue);
      expect(step.partsPrepared, 0);
    }
    expect((
      c.layoutBuildCount,
      c.pictureBuildCount,
      c.hitCount,
      c.activeLeases,
    ), counts);
    pins.first.release();
    _finish(w, c).binding.close();
    expect(s.natural.isActive && s.source.isActive, isTrue);
  });

  test(
    'partial warm font prefix survives a later miss without reacquiring it',
    () {
      final c = _cache(),
          s = _source(c, prefix: '<span style="font-size:33px">P</span>'),
          first = _finish(_work(s, c), c).binding,
          held = s
              .allocation
              .input
              .natural
              .reflow
              .children
              .placement
              .input
              .fonts
              .fonts
              .singleWhere(
                (f) =>
                    f.nativeInputIdentity ==
                    first.fonts.first.nativeInputIdentity,
              )
              .request
              .acquire(
                c,
                width: 300,
                textScaler: s.allocation.input.natural.textScaler,
                cachedOnly: true,
              )!;
      first.close();
      addTearDown(held.release);
      c.clearUnpinned();
      final w = _work(s, c), before = c.layoutBuildCount;
      for (var n = 0; !w.cacheMiss; n++) {
        expect(n, lessThan(10000));
        w.advance(maxParts: 32, cachedOnly: true);
      }
      expect(w.nativeLeases, hasLength(1));
      _finish(w, c, quantum: 512).binding.close();
      expect(c.layoutBuildCount - before, 1);
      expect(held.isActive, isTrue);
    },
  );

  test(
    'full font samples freeze once and callback retirement cannot leak aliases',
    () {
      final c = _cache(),
          s = _source(c, prefix: '<span style="font-size:33px">P</span>'),
          before = c.activeLeases,
          scaler = _CountingScaler(),
          b = _finish(_work(s, c, scaler: scaler), c).binding;
      expect(
        scaler.counts.keys.toSet(),
        s.allocation.input.natural.effectiveScales.keys.toSet(),
      );
      expect(scaler.counts.values.every((n) => n == 1), isTrue);
      b.close();
      ForumBodyInlineEmphasisMarkerPreparation? w;
      var retired = false;
      w = _work(
        s,
        c,
        guard: () {
          if (w?.nativeLeases.isNotEmpty == true) {
            retired = true;
            w!.close();
          }
        },
      );
      expect(() => _finish(w!, c), throwsStateError);
      expect(retired, isTrue);
      expect(c.activeLeases, before);
      w = _work(s, c, scaler: _CountingScaler(() => w!.close()));
      expect(() => w!.advance(maxParts: 1), throwsStateError);
      expect(c.activeLeases, before);
    },
  );

  test(
    'future font aliases reserve peak slots before the first acquisition',
    () {
      final c = _cache(),
          s = _source(c, prefix: '<span style="font-size:33px">P</span>'),
          before = (c.layoutBuildCount, c.pictureBuildCount, c.activeLeases);
      expect(
        () => _finish(_work(s, c, handles: 3), c),
        _failure(ForumBodyEmphasisAllocationFailure.limit),
      );
      expect((c.layoutBuildCount, c.pictureBuildCount, c.activeLeases), before);
    },
  );

  test(
    'intrinsic parent uses original request constraint and marker inputs',
    () {
      final c = _cache(),
          s = measureMixedEmphasisAllocatedSource(
            MixedEmphasisParentFixture(
              mixedEmphasisChildren.first,
              width: 800,
              layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
            ),
            c,
          ),
          b = _finish(_work(s, c), c).binding;
      expect(s.natural.layout.width, lessThan(800));
      expect(b.pictureInput!.commands, isNotEmpty);
      b.close();
    },
  );

  test('growing caller prefix is reprobed before the next distinct font', () {
    final c = _cache(),
        s = _source(c, prefix: '<span style="font-size:33px">P</span>'),
        pin = _pin(c, 0),
        before = c.activeLeases;
    c.clearUnpinned();
    ForumBodyInlineEmphasisMarkerPreparation? w;
    w = _work(
      s,
      c,
      handles: 4,
      owned: () => [s.source, if (w?.nativeLeases.isNotEmpty == true) pin],
    );
    expect(
      () => _finish(w!, c),
      _failure(ForumBodyEmphasisAllocationFailure.limit),
    );
    expect(c.activeLeases, before);
    expect(pin.isActive, isTrue);
  });

  test('complete owned prefix fails before marker acquisition', () {
    final c = _cache(entries: 16), s = _source(c);
    c.clearUnpinned();
    final pins = [for (var i = 0; i < 14; i++) _pin(c, i)],
        before = (c.layoutBuildCount, c.pictureBuildCount, c.activeLeases);
    expect(
      () => _finish(_work(s, c, owned: () => [s.source, ...pins]), c),
      throwsA(
        isA<ForumBodyParagraphBudgetException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyParagraphBudgetFailure.content,
        ),
      ),
    );
    expect((c.layoutBuildCount, c.pictureBuildCount, c.activeLeases), before);
  });

  test('limits reserve future handles and reject stale source/scaling', () {
    final c = _cache(),
        s = _source(c),
        before = (c.layoutBuildCount, c.pictureBuildCount, c.activeLeases);
    expect(
      () => _work(s, c, marks: 0),
      _failure(ForumBodyEmphasisAllocationFailure.limit),
    );
    expect(
      () => _finish(_work(s, c, fonts: 0), c),
      _failure(ForumBodyEmphasisAllocationFailure.limit),
    );
    expect(
      () => _finish(_work(s, c, handles: 2), c),
      _failure(ForumBodyEmphasisAllocationFailure.limit),
    );
    expect(
      () => _finish(_work(s, c, scaler: TextScaler.linear(2)), c),
      _failure(ForumBodyEmphasisAllocationFailure.source),
    );
    expect(
      () => ForumBodyInlineEmphasisMarkerPreparation(
        allocation: s.allocation,
        natural: s.source,
        cache: c,
        expectedTextScaler: TextScaler.noScaling,
        ensureOwner: () {},
      ),
      _failure(ForumBodyEmphasisAllocationFailure.source),
    );
    expect((c.layoutBuildCount, c.pictureBuildCount, c.activeLeases), before);
  });

  test('each cancellation part releases only owned marker fonts', () {
    final c = _cache(), s = _source(c), full = _finish(_work(s, c), c);
    full.binding.close();
    final before = c.activeLeases;
    for (var stop = 0; stop <= full.parts; stop++) {
      final w = _work(s, c);
      for (var n = 0; n < stop && !w.isReady; n++) {
        w.advance(maxParts: 1);
      }
      w.close();
      w.close();
      expect(w.nativeLeases, isEmpty);
      expect(() => w.advance(), throwsStateError);
      expect(w.takeBinding, throwsStateError);
      expect(c.activeLeases, before, reason: 'stop $stop');
    }
  });

  test(
    'visible owner outlives preparation; final handoff retirement rolls back',
    () {
      final c = _cache(), s = _source(c), before = c.activeLeases;
      var preparing = true, visible = true;
      final b = _finish(
        _work(
          s,
          c,
          guard: () {
            if (!preparing) throw StateError('preparing');
          },
          visible: () {
            if (!visible) throw StateError('visible');
          },
        ),
        c,
      ).binding;
      preparing = false;
      expect(b.fonts, isNotEmpty);
      visible = false;
      expect(() => b.fonts, throwsStateError);
      b.close();
      expect(c.activeLeases, before);
      var retire = false;
      ForumBodyInlineEmphasisMarkerPreparation? w;
      w = _work(
        s,
        c,
        visible: () {
          if (retire) w!.close();
        },
      );
      while (!w.isReady) {
        w.advance();
      }
      retire = true;
      expect(w.takeBinding, throwsStateError);
      expect(c.activeLeases, before);
    },
  );
}

final class _CountingScaler extends TextScaler {
  _CountingScaler([this.onSample]);
  final void Function()? onSample;
  final counts = <double, int>{};
  @override
  double scale(double size) {
    counts.update(size, (n) => n + 1, ifAbsent: () => 1);
    onSample?.call();
    return size;
  }

  @override
  double get textScaleFactor => throw StateError('Use individual font sizes');
}
