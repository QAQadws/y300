import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';

typedef _Source = ({
  ForumBodyInlineEmphasisIsolationMetrics metrics,
  ForumBodyInlineParagraphLease parent,
});

const _parentStyle =
    'text-emphasis:circle;line-height:.4;white-space:pre-wrap;'
    'background-color:rgba(40,90,120,.4);text-decoration:underline overline line-through';

ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 512,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(cache.close);
  return cache;
}

_Source _source(
  ForumBodyParagraphCache cache, {
  String? child,
  String prefix = 'ffi é中\nP',
  String suffix = 'Q\n<span style="visibility:hidden">hidden</span>R\n',
  String parentStyle = _parentStyle,
  TextDirection direction = TextDirection.ltr,
  TextScaler scaler = TextScaler.noScaling,
  double width = 70,
  double pitch = 256,
  TextStyle readerTextStyle = const TextStyle(
    fontFamily: 'Ahem',
    fontSize: 20,
    color: Color(0xff123456),
    backgroundColor: Color(0x44285a78),
  ),
}) {
  final fixture = MixedEmphasisParentFixture(
    child ?? mixedEmphasisChildren[1],
    width: width,
    direction: direction,
    prefix: prefix,
    suffix: suffix,
    parentStyle: parentStyle,
    readerTextStyle: readerTextStyle,
  );
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
    final natural = work.takeMeasurement();
    addTearDown(natural.parent.release);
    final iso = ForumBodyInlineEmphasisIsolationPreparation(
      metrics: natural.metrics,
      natural: natural.parent,
      cache: cache,
      rowIsolationPitch: pitch,
      ensureOwner: () {},
    );
    try {
      for (var n = 0; !iso.isReady; n++) {
        expect(n, lessThan(200000));
        final before = (cache.layoutBuildCount, cache.pictureBuildCount);
        final step = iso.advance(maxParts: 1);
        expect(step.partsPrepared, 1);
        expect(step.nativeLayoutsBuilt, inInclusiveRange(0, 1));
        expect(step.nativeLayoutsBuilt, cache.layoutBuildCount - before.$1);
        expect(step.waitingForLayoutBudget, isFalse);
        expect(step.picturesRecorded, 0);
        expect(cache.pictureBuildCount, before.$2);
      }
      final result = iso.takeMeasurement();
      addTearDown(result.parent.release);
      return result;
    } finally {
      iso.close();
    }
  } finally {
    work.close();
  }
}

Future<List<int>> _pixels(
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

void _strip(
  Canvas canvas,
  ForumBodyInlineParagraphLease parent,
  ForumBodyParagraphRowSelector strip,
) {
  canvas.save();
  try {
    canvas.clipRect(
      Rect.fromLTRB(
        -16384,
        strip.clipTop,
        parent.layout.width + 16384,
        strip.clipBottom,
      ),
      doAntiAlias: false,
    );
    parent.layout.paintParent(canvas, Offset.zero);
  } finally {
    canvas.restore();
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
            'logical strips preserve native paint $i/$direction/$scaler/$width',
            () async {
              final cache = _cache(),
                  source = _source(
                    cache,
                    child: child,
                    direction: direction,
                    scaler: scaler,
                    width: width,
                    parentStyle: i == 5
                        ? _parentStyle.replaceFirst('pre-wrap', 'normal')
                        : _parentStyle,
                  );
              final logical = source.metrics.logicalRows,
                  glyphs = source.metrics.rows;
              expect(logical.hasLogicalPaint, isTrue);
              expect(logical.geometry, same(source.metrics.geometry));
              expect(logical.rows, hasLength(source.parent.layout.lineCount));
              expect(() => logical.rows.clear(), throwsUnsupportedError);
              Rect? previous;
              for (final (n, row) in logical.rows.indexed) {
                expect(
                  (row.selector.startLine, row.selector.endLine),
                  (n, n + 1),
                );
                final paint = row.paintBounds;
                if (paint != null) {
                  expect(row.selector.clipTop, lessThanOrEqualTo(paint.top));
                  expect(
                    row.selector.clipBottom,
                    greaterThanOrEqualTo(paint.bottom),
                  );
                  if (previous != null) {
                    expect(
                      paint.top - previous.bottom,
                      greaterThanOrEqualTo(1),
                    );
                  }
                  previous = paint;
                }
              }
              final input = ForumBodyInlinePaintInput(source.parent.content);
              final phases =
                  [input.background, input.foreground, input.decoration].map((
                    content,
                  ) {
                    final p = cache.acquireInline(
                      content: content,
                      width: source.metrics.natural.requestWidth,
                      dimensions: source.parent.layout.dimensions,
                      textScaler: source.metrics.natural.textScaler,
                      layoutMode: source.metrics.natural.page.layoutMode,
                      rowIsolationPitch: source.parent.layout.rowIsolationPitch,
                    );
                    addTearDown(p.release);
                    cache.prepareInlineParentPaint(p);
                    return p;
                  }).toList();
              cache.prepareInlineParentPaint(source.parent);
              final size = Size(width + 160, source.parent.layout.height + 160);
              for (final dpr in [1.0, 3.0]) {
                for (final layer in [0, 2]) {
                  final full = await _pixels(
                    (c) {
                      c.translate(80, 80);
                      phases[layer].layout.paintParent(c, Offset.zero);
                    },
                    size,
                    dpr,
                  );
                  final rows = await _pixels(
                    (c) {
                      c.translate(80, 80);
                      for (final row in logical.rows) {
                        if (row.bounds != null) {
                          _strip(c, phases[layer], row.selector);
                        }
                      }
                    },
                    size,
                    dpr,
                  );
                  expect(rows, full, reason: 'phase $layer, DPR $dpr');
                }
                final whole = await _pixels(
                  (c) {
                    c.translate(80, 80);
                    source.parent.layout.paintParent(c, Offset.zero);
                  },
                  size,
                  dpr,
                );
                final rows = await _pixels(
                  (c) {
                    c.translate(80, 80);
                    for (var n = 0; n < logical.rows.length; n++) {
                      final logicalRow = logical.rows[n],
                          glyphRow = glyphs.rows[n];
                      if (logicalRow.bounds != null) {
                        _strip(c, phases[0], logicalRow.selector);
                      }
                      if (!glyphRow.isEmpty) {
                        _strip(c, phases[1], glyphRow.selector);
                      }
                      if (logicalRow.bounds != null) {
                        _strip(c, phases[2], logicalRow.selector);
                      }
                    }
                  },
                  size,
                  dpr,
                );
                expect(rows, whole, reason: 'native row order, DPR $dpr');
              }
            },
          );
        }
      }
    }
  }

  test(
    'opaque-only native background survives without a parent glyph',
    () async {
      final cache = _cache(),
          source = _source(
            cache,
            child: mixedEmphasisChildren.first,
            prefix: '',
            suffix: '',
            parentStyle: 'text-emphasis:circle;background-color:red',
          );
      expect(source.metrics.rows.rows.every((r) => r.isEmpty), isTrue);
      final logical = source.metrics.logicalRows;
      expect(logical.rows.single.bounds, isNotNull);
      expect(
        logical.rows.single.bounds!.contains(
          source.parent.layout.atomBoxes.single.toRect().center,
        ),
        isTrue,
      );
      cache.prepareInlineParentPaint(source.parent);
      final pixels = await _pixels(
        (c) {
          c.translate(40, 40);
          _strip(c, source.parent, logical.rows.single.selector);
        },
        Size(150, source.parent.layout.height + 80),
        1,
      );
      expect(
        [
          for (var i = 3; i < pixels.length; i += 4) pixels[i],
        ].any((a) => a > 0),
        isTrue,
      );
    },
  );

  test('tall decorated child retries logical pitch instead of clipping', () {
    const tall =
        '<ruby style="text-emphasis:none">A<rt style="font-size:350px">x</rt></ruby>';
    final cache = _cache(),
        source = _source(
          cache,
          child: '$tall\n$tall',
          prefix: '',
          suffix: '',
          width: 600,
          pitch: 256,
          readerTextStyle: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            color: Color(0xff123456),
            backgroundColor: Color(0x44285a78),
            decoration: TextDecoration.underline,
          ),
        );
    expect(source.parent.layout.rowIsolationPitch, greaterThan(256));
    final row = source.metrics.geometry.atomLineIndices.first,
        logical = source.metrics.logicalRows.rows[row];
    final slot = source.parent.layout.atomBoxes.first.toRect();
    expect(logical.bounds!.top, lessThanOrEqualTo(slot.top));
    expect(logical.bounds!.bottom, greaterThanOrEqualTo(slot.bottom));
    expect(source.metrics.rows.fontClearance, lessThan(50));
  });

  test('no authored logical paint keeps empty strips', () {
    final source = _source(
      _cache(),
      parentStyle: 'text-emphasis:circle;line-height:.4',
      readerTextStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20),
    );
    expect(source.metrics.logicalRows.hasLogicalPaint, isFalse);
    expect(
      source.metrics.logicalRows.rows.every(
        (r) => r.bounds == null && r.paintBounds == null,
      ),
      isTrue,
    );
  });

  test(
    'logical preparation validates scope and limits without releasing parent',
    () {
      final cache = _cache(), first = _source(cache), second = _source(cache);
      final count = cache.activeLeases;
      expect(
        () => ForumBodyInlineLogicalPaintRowPreparation(
          parent: first.parent,
          geometry: second.metrics.geometry,
          ensureOwner: () {},
        ),
        throwsA(
          isA<ForumBodyParagraphRowException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphRowFailure.source,
          ),
        ),
      );
      for (final limits in [(1, 512), (4096, 0)]) {
        expect(
          () => ForumBodyInlineLogicalPaintRowPreparation(
            parent: first.parent,
            geometry: first.metrics.geometry,
            ensureOwner: () {},
            maxLines: limits.$1,
            maxAtoms: limits.$2,
          ),
          throwsA(
            isA<ForumBodyParagraphRowException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphRowFailure.limit,
            ),
          ),
        );
      }
      expect(cache.activeLeases, count);
    },
  );

  test(
    'every logical slice and owner cancellation is bounded and borrowed',
    () {
      final cache = _cache(),
          source = _source(cache),
          before = (
            cache.layoutBuildCount,
            cache.pictureBuildCount,
            cache.hitCount,
            cache.activeLeases,
          );
      ForumBodyInlineLogicalPaintRowPreparation work(void Function() guard) =>
          ForumBodyInlineLogicalPaintRowPreparation(
            parent: source.parent,
            geometry: source.metrics.geometry,
            ensureOwner: guard,
          );
      final full = work(() {});
      var parts = 0;
      while (!full.isReady) {
        expect(full.advance(maxParts: 1), 1);
        parts++;
      }
      expect(full.advance(maxParts: 1), 0);
      final rows = full.takeRows();
      expect(rows.geometry, same(source.metrics.geometry));
      expect(full.takeRows, throwsStateError);
      for (var stop = 1; stop <= parts; stop++) {
        var alive = true;
        final job = work(() {
          if (!alive) throw StateError('retired');
        });
        for (var n = 0; n < stop; n++) {
          job.advance(maxParts: 1);
        }
        alive = false;
        expect(() => job.advance(maxParts: 1), throwsStateError);
        expect(job.takeRows, throwsStateError);
        job.close();
      }
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.hitCount,
        cache.activeLeases,
      ), before);
      expect(source.parent.isActive, isTrue);
    },
  );
}
