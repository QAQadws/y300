import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

const _style = TextStyle(
  fontFamily: 'Ahem',
  fontSize: 20,
  color: Color(0xff123456),
  shadows: [
    Shadow(color: Color(0xffaa0000), offset: Offset(2, -3), blurRadius: 2),
  ],
);
ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 512,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(cache.close);
  return cache;
}

({
  ForumBodyInlineParagraphLease parent,
  ForumBodyInlineEmphasisIsolationMetrics metrics,
})
_source(
  ForumBodyParagraphCache cache, {
  String? child,
  TextStyle style = _style,
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  double width = 70,
  String? prefix,
  String? suffix,
}) {
  final fixture = MixedEmphasisParentFixture(
    child ?? mixedEmphasisChildren[1],
    width: width,
    direction: direction,
    readerTextStyle: style,
    prefix:
        prefix ??
        '<span style="background-color:rgba(0,255,0,.4);text-decoration:underline">ffi é 中 </span>'
            '<span style="font-size:31px;color:red;text-decoration:overline">P</span>',
    suffix:
        suffix ??
        '<span style="visibility:hidden;background-color:red">hidden</span>QQ',
  );
  final parent = ForumBodyInlineEmphasisParentPreparation(
    input: fixture.input,
    cache: cache,
    textScaler: scaler,
    ensureOwner: () {},
  );
  try {
    while (!parent.isReady) {
      parent.advance(maxParts: 32);
    }
    final natural = parent.takeMeasurement();
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
      final value = iso.takeMeasurement();
      addTearDown(value.parent.release);
      return (parent: value.parent, metrics: value.metrics);
    } finally {
      iso.close();
    }
  } finally {
    parent.close();
  }
}

List<ForumBodyInlineSpanContent> _layers(ForumBodyInlinePaintInput value) => [
  value.background,
  value.foreground,
  value.decoration,
];
Future<Uint8List> _pixels(
  void Function(Canvas) draw,
  Size size,
  double dpr,
) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder)..scale(dpr));
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
  for (final (i, child) in mixedEmphasisChildren.indexed) {
    for (final direction in TextDirection.values) {
      for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
        for (final width in [70.0, 300.0]) {
          test(
            'whole mixed phases conserve native paint $i/$direction/$scaler/$width',
            () async {
              final cache = _cache(),
                  source = _source(
                    cache,
                    child: child,
                    direction: direction,
                    scaler: scaler,
                    width: width,
                  );
              final original = source.parent,
                  input = ForumBodyInlinePaintInput(original.content),
                  clones = ForumBodyInlinePaintInput(original.content);
              final parents = <ForumBodyInlineParagraphLease>[];
              addTearDown(() {
                for (final p in parents) {
                  p.release();
                }
              });
              final counts = (
                cache.layoutBuildCount,
                cache.pictureBuildCount,
                cache.hitCount,
                cache.activeLeases,
              );
              for (final layer in _layers(input)) {
                expect(layer.contexts, same(original.content.contexts));
                expect(layer.runs, same(original.content.runs));
                expect(layer.style, same(original.content.style));
                expect(layer.projection, same(original.content.projection));
                expect(
                  layer.projectionForLayout(
                    source.metrics.natural.page.layoutMode,
                  ),
                  same(original.layout.projection),
                );
                expect(layer.horizontalInset, original.content.horizontalInset);
                final probe = cache.createBudgetProbe();
                try {
                  ForumBodyInlineParagraphRequest(
                    content: layer,
                    dimensions: original.layout.dimensions,
                    layoutMode: source.metrics.natural.page.layoutMode,
                    rowIsolationPitch: original.layout.rowIsolationPitch,
                  ).includeBudget(
                    probe,
                    width: source.metrics.natural.requestWidth,
                    textScaler: source.metrics.natural.textScaler,
                    minimumLineCount: original.layout.lineCount,
                  );
                } finally {
                  probe.close();
                }
              }
              expect((
                cache.layoutBuildCount,
                cache.pictureBuildCount,
                cache.hitCount,
                cache.activeLeases,
              ), counts);
              for (final layer in _layers(input)) {
                parents.add(
                  cache.acquireInline(
                    content: layer,
                    width: source.metrics.natural.requestWidth,
                    dimensions: original.layout.dimensions,
                    textScaler: source.metrics.natural.textScaler,
                    layoutMode: source.metrics.natural.page.layoutMode,
                    rowIsolationPitch: original.layout.rowIsolationPitch,
                  ),
                );
              }
              expect({
                original.nativeInputIdentity,
                ...parents.map((p) => p.nativeInputIdentity),
              }, hasLength(4));
              for (final (j, p) in parents.indexed) {
                final clone = cache.tryAcquireInlineCached(
                  content: _layers(clones)[j],
                  width: source.metrics.natural.requestWidth,
                  dimensions: original.layout.dimensions,
                  textScaler: source.metrics.natural.textScaler,
                  layoutMode: source.metrics.natural.page.layoutMode,
                  rowIsolationPitch: original.layout.rowIsolationPitch,
                );
                expect(clone, isNotNull);
                try {
                  expect(clone!.nativeInputIdentity, p.nativeInputIdentity);
                } finally {
                  clone?.release();
                }
                expect(p.layout.lines.length, original.layout.lines.length);
                for (final (index, row) in p.layout.lines.indexed) {
                  final reference = original.layout.lines[index];
                  expect(
                    (row.top, row.bottom, row.baseline, row.left, row.width),
                    (
                      reference.top,
                      reference.bottom,
                      reference.baseline,
                      reference.left,
                      reference.width,
                    ),
                  );
                  expect(
                    (
                      row.engineCoverageStartUtf16,
                      row.engineCoverageEndUtf16,
                      row.canBreakBefore,
                      row.canBreakAfter,
                    ),
                    (
                      reference.engineCoverageStartUtf16,
                      reference.engineCoverageEndUtf16,
                      reference.canBreakBefore,
                      reference.canBreakAfter,
                    ),
                  );
                }
                expect(
                  p.layout.atomBoxes.map((b) => b.toRect()),
                  original.layout.atomBoxes.map((b) => b.toRect()),
                );
                expect(p.layout.nativeFlowTop, original.layout.nativeFlowTop);
                expect(
                  p.layout.nativeFlowBottom,
                  original.layout.nativeFlowBottom,
                );
                expect(
                  p.layout.nativeAlphabeticBaseline,
                  original.layout.nativeAlphabeticBaseline,
                );
                cache.prepareInlineParentPaint(p);
              }
              cache.prepareInlineParentPaint(original);
              final size = Size(width + 200, original.layout.height + 200);
              for (final dpr in [1.0, 3.0]) {
                final all = await _pixels(
                  (c) => original.layout.paintParent(c, const Offset(100, 100)),
                  size,
                  dpr,
                );
                final phases = await _pixels(
                  (c) {
                    for (final p in parents) {
                      p.layout.paintParent(c, const Offset(100, 100));
                    }
                  },
                  size,
                  dpr,
                );
                expect(phases, orderedEquals(all));
                expect(
                  [
                    for (var n = 3; n < all.length; n += 4) all[n],
                  ].any((a) => a != 0),
                  isTrue,
                );
              }
            },
          );
        }
      }
    }
  }
  test('opaque child retains its native parent background phase', () async {
    final cache = _cache(),
        source = _source(
          cache,
          child: mixedEmphasisChildren[0],
          prefix: '',
          suffix: '',
          style: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            backgroundColor: Color(0xffff0000),
          ),
        );
    cache.prepareInlineParentPaint(source.parent);
    final all = await _pixels(
      (c) => source.parent.layout.paintParent(c, const Offset(100, 100)),
      Size(270, source.parent.layout.height + 200),
      1,
    );
    expect(all.any((b) => b != 0), isTrue);
    final phase = cache.acquireInline(
      content: ForumBodyInlinePaintInput(source.parent.content).background,
      width: source.metrics.natural.requestWidth,
      dimensions: source.parent.layout.dimensions,
      textScaler: source.metrics.natural.textScaler,
      layoutMode: source.metrics.natural.page.layoutMode,
      rowIsolationPitch: source.parent.layout.rowIsolationPitch,
    );
    try {
      cache.prepareInlineParentPaint(phase);
      final background = await _pixels(
        (c) => phase.layout.paintParent(c, const Offset(100, 100)),
        Size(270, source.parent.layout.height + 200),
        1,
      );
      expect(background, orderedEquals(all));
    } finally {
      phase.release();
    }
  });
  test('paint-only values cannot qualify font geometry or readable source', () {
    final cache = _cache(), source = _source(cache);
    final input = ForumBodyInlinePaintInput(source.parent.content);
    for (final content in _layers(input)) {
      expect(() => ForumBodyInlinePaintInput(content), throwsArgumentError);
      expect(
        () => content.prepareContextIndex(maxContexts: 1),
        throwsStateError,
      );
      expect(() => content.openAtomicContexts(0), throwsStateError);
      final phase = cache.acquireInline(
        content: content,
        width: source.metrics.natural.requestWidth,
        dimensions: source.parent.layout.dimensions,
        textScaler: source.metrics.natural.textScaler,
        layoutMode: source.metrics.natural.page.layoutMode,
      );
      try {
        expect(
          () => ForumBodyInlineFontGeometryPreparation(
            content: content,
            parent: phase,
            ensureOwner: () {},
          ),
          throwsA(isA<ForumBodyInlineFontGeometryException>()),
        );
        expect(
          () => phase.layout.fragment(0, phase.layout.lineCount),
          throwsA(isA<ForumBodyParagraphLayoutException>()),
        );
        expect(
          () => phase.layout.hitAt(Offset.zero),
          throwsA(isA<ForumBodyParagraphLayoutException>()),
        );
        expect(
          () =>
              phase.layout.selection(0, content.projection.display.text.length),
          throwsA(isA<ForumBodyParagraphLayoutException>()),
        );
        expect(
          () => phase.layout.glyphSelection(
            0,
            content.projection.display.text.length,
          ),
          throwsA(isA<ForumBodyParagraphLayoutException>()),
        );
      } finally {
        phase.release();
      }
    }
  });
  test('ordinary paint phases cannot enter mixed source composition', () {
    final doc = const ForumBodyParser().parse(
      html: '<p>P</p>',
      sourceId: 'phase-compose',
      conversionIdentity: 'none',
    );
    final styles = const ForumBodyStyleResolver().resolve(
      doc,
      ForumBodyReaderStyle(
        textStyle: _style,
        fontRevision: 'phase-compose',
        linkColor: const Color(0xff0000ff),
      ),
    );
    final original = const ForumBodyParagraphContentBuilder().build(
      document: doc,
      styles: styles,
      path: '0',
    );
    final phases = ForumBodyParagraphPaintInput(original);
    for (final context in [
      phases.background,
      phases.foreground,
      phases.decoration,
    ]) {
      expect(
        () => ForumBodyInlineSpanContent.compose(
          identity: original.identity,
          path: '0',
          fontRevision: original.fontRevision,
          styleRevision: original.styleRevision,
          style: original.style,
          contexts: [context],
          atomicRanges: const [],
        ),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
    }
  });
}
