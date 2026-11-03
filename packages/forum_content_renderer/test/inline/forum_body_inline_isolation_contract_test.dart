import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_inline_fixture.dart';
import 'test_support/mixed_emphasis_parent_fixture.dart';

const _dimensions = [
  PlaceholderDimensions(
    size: Size(35.25, 40.75),
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    baselineOffset: 30.125,
  ),
];
ForumBodyParagraphCache _cache({int entries = 8}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(cache.close);
  return cache;
}

({ForumBodyInlineRowReference value, int parts}) _reference(
  ForumBodyInlineParagraphLease natural,
  ForumBodyInlineParagraphLease isolated, {
  int quantum = 1,
}) {
  final work = ForumBodyInlineRowReferencePreparation(
    natural: natural,
    isolated: isolated,
    ensureOwner: () {},
  );
  var parts = 0;
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(30000));
      final used = work.advance(maxParts: quantum);
      expect(used, inInclusiveRange(1, quantum));
      parts += used;
    }
    expect(work.advance(maxParts: 1), 0);
    return (value: work.takeReference(), parts: parts);
  } finally {
    work.close();
  }
}

List<Object?> _line(ForumBodyParagraphLine l) => [
  l.startUtf16,
  l.endUtf16,
  l.coverageStartUtf16,
  l.coverageEndUtf16,
  l.engineStartUtf16,
  l.engineEndUtf16,
  l.engineCoverageStartUtf16,
  l.engineCoverageEndUtf16,
  l.canBreakBefore,
  l.canBreakAfter,
  l.unpaintedTrailingSpaceStartUtf16,
  l.engineUnpaintedTrailingSpaceStartUtf16,
  l.left,
  l.width,
];
Future<Uint8List> _raster(
  void Function(Canvas) draw,
  Size size,
  double dpr,
) async {
  final recorder = ui.PictureRecorder(), canvas = Canvas(recorder)..scale(dpr);
  draw(canvas);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(
      (size.width * dpr).ceil(),
      (size.height * dpr).ceil(),
    );
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
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
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
      for (final width in [70.0, 300.0]) {
        for (final align in [TextAlign.center, TextAlign.justify]) {
          for (final indent in [false, true]) {
            for (final pitch in [128.0, 256.0]) {
              test(
                'independent native isolation $direction/$scaler/$width/$align/$indent/$pitch',
                () {
                  final content = mixedInlineInput(
                    prefix: 'ffi <span style="font-size:31px">é</span> 中\nAB ',
                    suffix: ' Z\n',
                    direction: direction.name,
                    paragraphStyle: 'white-space:pre-wrap;line-height:.4',
                    reader: ForumBodyReaderStyle(
                      textStyle: const TextStyle(
                        fontFamily: 'Ahem',
                        fontSize: 20,
                      ),
                      fontRevision: 'isolation',
                      linkColor: const Color(0xff0000ff),
                      textDirection: direction,
                      textAlign: align,
                      firstLineIndent: ForumBodyLength(
                        indent ? 1.5 : 0,
                        ForumBodyLengthUnit.em,
                      ),
                    ),
                  ).content;
                  final cache = _cache(),
                      natural = cache.acquireInline(
                        content: content,
                        width: width,
                        dimensions: _dimensions,
                        textScaler: scaler,
                      );
                  addTearDown(natural.release);
                  final request = ForumBodyInlineParagraphRequest(
                    content: content,
                    dimensions: _dimensions,
                    rowIsolationPitch: pitch,
                  );
                  final before = (
                    cache.layoutBuildCount,
                    cache.pictureBuildCount,
                    cache.hitCount,
                  );
                  expect(
                    request.acquire(
                      cache,
                      width: width,
                      textScaler: scaler,
                      cachedOnly: true,
                    ),
                    isNull,
                  );
                  final probe = cache.createBudgetProbe();
                  try {
                    request.includeBudget(
                      probe,
                      width: width,
                      textScaler: scaler,
                      minimumLineCount: natural.layout.lineCount,
                    );
                    expect(probe.snapshotNativeIdentities(), hasLength(1));
                  } finally {
                    probe.close();
                  }
                  expect((
                    cache.layoutBuildCount,
                    cache.pictureBuildCount,
                    cache.hitCount,
                  ), before);
                  final isolated = request.acquire(
                    cache,
                    width: width,
                    textScaler: scaler,
                    cachedOnly: false,
                  )!;
                  addTearDown(isolated.release);
                  expect(
                    isolated.hasSameSourceAndInputsExceptRowIsolation(natural),
                    isTrue,
                  );
                  expect(
                    isolated.nativeInputIdentity,
                    isNot(natural.nativeInputIdentity),
                  );
                  final input = isolated.layout,
                      innerWidth = width - 2 * content.horizontalInset;
                  final raw =
                      TextPainter(
                          text: content.textSpanWithDimensions(
                            _dimensions,
                            firstLineIndent:
                                input.firstLineIndent.appliedAdvance,
                          ),
                          textDirection: direction,
                          textAlign: align,
                          textScaler: scaler,
                          strutStyle: StrutStyle.fromTextStyle(
                            content.style.textStyle,
                            height: pitch / scaler.scale(20),
                            leading: 0,
                            forceStrutHeight: true,
                          ),
                        )
                        ..setPlaceholderDimensions(_dimensions)
                        ..layout(minWidth: innerWidth, maxWidth: innerWidth);
                  addTearDown(raw.dispose);
                  final origin = Offset(
                    content.horizontalInset,
                    input.lines.first.baseline -
                        raw.computeLineMetrics().first.baseline,
                  );
                  expect(input.lineCount, raw.computeLineMetrics().length);
                  for (final (i, row) in input.lines.indexed) {
                    expect(
                      row.baseline,
                      raw.computeLineMetrics()[i].baseline + origin.dy,
                    );
                    expect(_line(row), _line(natural.layout.lines[i]));
                  }
                  final expected = raw.inlinePlaceholderBoxes!.single
                      .toRect()
                      .shift(origin);
                  expect(input.atomBoxes.single.toRect(), expected);
                  final snapshot = _reference(natural, isolated).value,
                      batched = _reference(natural, isolated, quantum: 7).value;
                  expect(snapshot.naturalLines, same(natural.layout.lines));
                  expect(snapshot.isolatedLines, same(input.lines));
                  expect(snapshot.atomLineIndices, batched.atomLineIndices);
                  expect(snapshot.isolatedAtomBoxes, same(input.atomBoxes));
                  final warm = request.acquire(
                    cache,
                    width: width,
                    textScaler: scaler,
                    cachedOnly: true,
                  )!;
                  try {
                    expect(
                      warm.nativeInputIdentity,
                      isolated.nativeInputIdentity,
                    );
                  } finally {
                    warm.release();
                  }
                  expect(
                    () => input.fragment(0, input.lineCount),
                    throwsA(isA<ForumBodyParagraphLayoutException>()),
                  );
                  final recorder = ui.PictureRecorder();
                  try {
                    expect(
                      () => input.paintParent(Canvas(recorder), Offset.zero),
                      throwsStateError,
                    );
                  } finally {
                    recorder.endRecording().dispose();
                  }
                  final pictures = cache.pictureBuildCount;
                  expect(cache.prepareInlineParentPaint(isolated), isTrue);
                  expect(cache.prepareInlineParentPaint(isolated), isFalse);
                  expect(cache.prepareInlineParentPaint(natural), isFalse);
                  expect(cache.pictureBuildCount, pictures + 1);
                  expect(
                    () => snapshot.atomLineIndices.clear(),
                    throwsUnsupportedError,
                  );
                  natural.release();
                  isolated.release();
                  cache.clearUnpinned();
                  expect(cache.activeLeases, 0);
                  expect(snapshot.isolatedAtomBoxes.single.toRect(), expected);
                },
              );
            }
          }
        }
      }
    }
  }
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
      for (final (index, html) in mixedEmphasisChildren.indexed) {
        test(
          'actual complete child plans keep physical rows when isolated $index/$direction/$scaler',
          () {
            final f = MixedEmphasisParentFixture(html, direction: direction),
                cache = _cache(entries: 512);
            final ready = f.finish(f.open(cache, scaler: scaler), cache).value;
            addTearDown(ready.lease.release);
            final isolated =
                ForumBodyInlineParagraphRequest(
                  content: ready.glyphInput.glyphs,
                  dimensions: ready.plan.dimensions,
                  rowIsolationPitch: 256,
                ).acquire(
                  cache,
                  width: 300,
                  textScaler: scaler,
                  cachedOnly: false,
                )!;
            addTearDown(isolated.release);
            final before = (
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.hitCount,
              cache.activeLeases,
            );
            final ref = _reference(ready.lease, isolated).value;
            expect(ref.content, same(ready.glyphInput.glyphs));
            expect(ref.dimensions, ready.plan.dimensions);
            expect(ref.atomLineIndices, hasLength(ready.plan.rubyAtoms.length));
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
  test(
    'isolated parent pixels match independent Flutter drawing at DPR1/3',
    () async {
      for (final direction in TextDirection.values) {
        final content = mixedInlineInput(
          prefix: 'AB\n<span style="font-size:31px">é</span> ',
          suffix: ' Z',
          direction: direction.name,
          paragraphStyle: 'white-space:pre-wrap;line-height:.4',
          reader: ForumBodyReaderStyle(
            textStyle: const TextStyle(
              fontFamily: 'Ahem',
              fontSize: 20,
              color: Color(0xff123456),
              shadows: [
                Shadow(
                  color: Color(0x802233ff),
                  offset: Offset(.25, .5),
                  blurRadius: 1.1,
                ),
              ],
            ),
            fontRevision: 'isolation-pixels',
            linkColor: const Color(0xff0000ff),
            textDirection: direction,
            textAlign: TextAlign.center,
          ),
        ).content;
        final cache = _cache(),
            isolated = cache.acquireInline(
              content: content,
              width: 140,
              dimensions: _dimensions,
              rowIsolationPitch: 128,
            );
        addTearDown(isolated.release);
        final raw =
            TextPainter(
                text: content.textSpan,
                textDirection: direction,
                textAlign: TextAlign.center,
                strutStyle: StrutStyle.fromTextStyle(
                  content.style.textStyle,
                  height: 128 / 20,
                  leading: 0,
                  forceStrutHeight: true,
                ),
              )
              ..setPlaceholderDimensions(_dimensions)
              ..layout(minWidth: 140, maxWidth: 140);
        addTearDown(raw.dispose);
        final origin = Offset(
          content.horizontalInset,
          isolated.layout.lines.first.baseline -
              raw.computeLineMetrics().first.baseline,
        );
        cache.prepareInlineParentPaint(isolated);
        final stage = ui.PictureRecorder();
        raw.paint(Canvas(stage), origin);
        stage.endRecording().dispose();
        for (final dpr in [1.0, 3.0]) {
          final size = Size(160, isolated.layout.height + 16),
              offset = const Offset(3.25, 5.75);
          final actual = await _raster(
                (c) => isolated.layout.paintParent(c, offset),
                size,
                dpr,
              ),
              expected = await _raster(
                (c) => raw.paint(c, origin + offset),
                size,
                dpr,
              );
          expect(actual.any((v) => v != 0), isTrue);
          expect(actual, orderedEquals(expected));
        }
      }
    },
  );
  test(
    'natural/isolated probes and native entries use distinct pitch keys',
    () {
      final content = mixedInlineInput().content, cache = _cache();
      final natural = cache.acquireInline(
            content: content,
            width: 140,
            dimensions: _dimensions,
          ),
          first = cache.acquireInline(
            content: content,
            width: 140,
            dimensions: _dimensions,
            rowIsolationPitch: 128,
          ),
          second = cache.acquireInline(
            content: content,
            width: 140,
            dimensions: _dimensions,
            rowIsolationPitch: 256,
          );
      addTearDown(natural.release);
      addTearDown(first.release);
      addTearDown(second.release);
      expect({
        natural.nativeInputIdentity,
        first.nativeInputIdentity,
        second.nativeInputIdentity,
      }, hasLength(3));
      final before = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.hitCount,
        cache.estimatedRetainedBytes,
      );
      final probe = cache.createBudgetProbe();
      try {
        for (final lease in [natural, first, second]) {
          probe.includeLease(lease);
        }
        for (final pitch in [null, 128.0, 256.0]) {
          ForumBodyInlineParagraphRequest(
            content: content,
            dimensions: _dimensions,
            rowIsolationPitch: pitch,
          ).includeBudget(probe, width: 140, textScaler: TextScaler.noScaling);
        }
        expect(probe.snapshotNativeIdentities(), hasLength(3));
      } finally {
        probe.close();
      }
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.hitCount,
        cache.estimatedRetainedBytes,
      ), before);
    },
  );
  test(
    'invalid isolation modes/pitches and oversized height retain no native handle',
    () {
      final content = mixedInlineInput().content, cache = _cache();
      for (final pitch in [0.0, -1.0, double.nan, double.infinity, 16385.0]) {
        final request = ForumBodyInlineParagraphRequest(
          content: content,
          dimensions: _dimensions,
          rowIsolationPitch: pitch,
        );
        final probe = cache.createBudgetProbe();
        try {
          expect(
            () => request.includeBudget(
              probe,
              width: 140,
              textScaler: TextScaler.noScaling,
            ),
            throwsA(isA<ForumBodyParagraphLayoutException>()),
          );
        } finally {
          probe.close();
        }
        expect(
          () => request.acquire(
            cache,
            width: 140,
            textScaler: TextScaler.noScaling,
            cachedOnly: true,
          ),
          throwsA(isA<ForumBodyParagraphLayoutException>()),
        );
      }
      expect(
        () => cache.acquireInline(
          content: content,
          width: 140,
          dimensions: _dimensions,
          rowIsolationPitch: 128,
          layoutMode: ForumBodyParagraphLayoutMode.fitSingleLine,
        ),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
      expect(cache.layoutBuildCount, 0);
      expect(cache.entryCount, 0);
      final long = mixedInlineInput(
        prefix: 'A\n' * 70,
        paragraphStyle: 'white-space:pre-wrap',
      ).content;
      expect(
        () => cache.acquireInline(
          content: long,
          width: 140,
          dimensions: _dimensions,
          rowIsolationPitch: 16384,
        ),
        throwsA(
          isA<ForumBodyParagraphLayoutException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphLayoutFailure.isolation,
          ),
        ),
      );
      expect(cache.activeLeases, 0);
      expect(cache.entryCount, 0);
    },
  );
  test(
    'row reference rejects foreign cache/source and differing actual native inputs',
    () {
      final content = mixedInlineInput().content,
          other = mixedInlineInput().content,
          cache = _cache(),
          foreign = _cache();
      final natural = cache.acquireInline(
        content: content,
        width: 140,
        dimensions: _dimensions,
      );
      addTearDown(natural.release);
      final variants = [
        foreign.acquireInline(
          content: content,
          width: 140,
          dimensions: _dimensions,
          rowIsolationPitch: 256,
        ),
        cache.acquireInline(
          content: other,
          width: 140,
          dimensions: _dimensions,
          rowIsolationPitch: 256,
        ),
        cache.acquireInline(
          content: content,
          width: 150,
          dimensions: _dimensions,
          rowIsolationPitch: 256,
        ),
        cache.acquireInline(
          content: content,
          width: 140,
          dimensions: _dimensions,
          rowIsolationPitch: 256,
          textScaler: TextScaler.linear(1.1),
        ),
        cache.acquireInline(
          content: content,
          width: 140,
          dimensions: [
            const PlaceholderDimensions(
              size: Size(35.5, 40.75),
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              baselineOffset: 30.125,
            ),
          ],
          rowIsolationPitch: 256,
        ),
        cache.acquireInline(
          content: content,
          width: 140,
          dimensions: _dimensions,
        ),
      ];
      for (final isolated in variants) {
        addTearDown(isolated.release);
        expect(
          () => ForumBodyInlineRowReferencePreparation(
            natural: natural,
            isolated: isolated,
            ensureOwner: () {},
          ),
          throwsA(
            isA<ForumBodyParagraphRowReferenceException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphRowReferenceFailure.source,
            ),
          ),
        );
      }
      expect(natural.isActive, isTrue);
      expect(() => foreign.prepareInlineParentPaint(natural), throwsStateError);
    },
  );
  test(
    'all row/slot/ready boundaries retire reference work without releasing callers',
    () {
      final content = mixedInlineInput(
            prefix: 'A\nB\n',
            paragraphStyle: 'white-space:pre-wrap',
          ).content,
          cache = _cache();
      final natural = cache.acquireInline(
            content: content,
            width: 140,
            dimensions: _dimensions,
          ),
          isolated = cache.acquireInline(
            content: content,
            width: 140,
            dimensions: _dimensions,
            rowIsolationPitch: 256,
          );
      addTearDown(natural.release);
      addTearDown(isolated.release);
      final parts = _reference(natural, isolated).parts;
      for (var boundary = 0; boundary <= parts; boundary++) {
        var active = true;
        final work = ForumBodyInlineRowReferencePreparation(
          natural: natural,
          isolated: isolated,
          ensureOwner: () {
            if (!active) {
              throw StateError('Retired');
            }
          },
        );
        for (var n = 0; n < boundary; n++) {
          work.advance(maxParts: 1);
        }
        active = false;
        expect(
          work.isReady ? work.takeReference : () => work.advance(maxParts: 1),
          throwsStateError,
        );
        work.close();
        expect(cache.activeLeases, 2);
      }
      for (final (lines, atoms) in [(1, 512), (4096, 0)]) {
        expect(
          () => ForumBodyInlineRowReferencePreparation(
            natural: natural,
            isolated: isolated,
            ensureOwner: () {},
            maxLines: lines,
            maxAtoms: atoms,
          ),
          throwsA(
            isA<ForumBodyParagraphRowReferenceException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphRowReferenceFailure.limit,
            ),
          ),
        );
      }
      final ready = ForumBodyInlineRowReferencePreparation(
        natural: natural,
        isolated: isolated,
        ensureOwner: () {},
      );
      while (!ready.isReady) {
        ready.advance(maxParts: 1);
      }
      isolated.release();
      expect(ready.takeReference, throwsStateError);
      expect(cache.activeLeases, 1);
    },
  );
  test('row callbacks cannot reenter or revive closed/ready references', () {
    final content = mixedInlineInput().content, cache = _cache();
    final natural = cache.acquireInline(
          content: content,
          width: 140,
          dimensions: _dimensions,
        ),
        isolated = cache.acquireInline(
          content: content,
          width: 140,
          dimensions: _dimensions,
          rowIsolationPitch: 256,
        );
    addTearDown(natural.release);
    addTearDown(isolated.release);
    for (final mode in [0, 1, 2]) {
      var armed = false;
      late ForumBodyInlineRowReferencePreparation work;
      work = ForumBodyInlineRowReferencePreparation(
        natural: natural,
        isolated: isolated,
        ensureOwner: () {
          if (!armed) {
            return;
          }
          if (mode == 0 || mode == 2 && work.isReady) {
            work.close();
          } else if (mode == 1) {
            work.advance(maxParts: 1);
          }
        },
      );
      armed = true;
      expect(() => _finishReference(work), throwsStateError);
      expect(work.isReady, isFalse);
      expect(cache.activeLeases, 2);
    }
  });
  test(
    'owned natural parent and isolated request share the same finite cache budget',
    () {
      final content = mixedInlineInput().content, cache = _cache(entries: 1);
      final natural = cache.acquireInline(
        content: content,
        width: 140,
        dimensions: _dimensions,
      );
      addTearDown(natural.release);
      final request = ForumBodyInlineParagraphRequest(
            content: content,
            dimensions: _dimensions,
            rowIsolationPitch: 256,
          ),
          before = (
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            cache.entryCount,
            cache.activeLeases,
          );
      final probe = cache.createBudgetProbe();
      try {
        probe.includeLease(natural);
        expect(
          () => request.includeBudget(
            probe,
            width: 140,
            textScaler: TextScaler.noScaling,
          ),
          throwsA(
            isA<ForumBodyParagraphBudgetException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphBudgetFailure.content,
            ),
          ),
        );
      } finally {
        probe.close();
      }
      expect(
        () => request.acquire(
          cache,
          width: 140,
          textScaler: TextScaler.noScaling,
          cachedOnly: false,
        ),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.pinned,
          ),
        ),
      );
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.entryCount,
        cache.activeLeases,
      ), before);
      natural.release();
      final isolated = request.acquire(
        cache,
        width: 140,
        textScaler: TextScaler.noScaling,
        cachedOnly: false,
      )!;
      isolated.release();
      expect(cache.activeLeases, 0);
      expect(cache.entryCount, 1);
    },
  );
}

void _finishReference(ForumBodyInlineRowReferencePreparation work) {
  try {
    while (!work.isReady) {
      work.advance(maxParts: 1);
    }
    work.takeReference();
  } finally {
    work.close();
  }
}
