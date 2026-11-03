import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_emphasis_parent_fixture.dart';
import 'test_support/mixed_inline_fixture.dart';

ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 512,
    maxEstimatedBytes: 1 << 26,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyInlineEmphasisTextGeometry _geometry(
  ForumBodyInlineEmphasisTextInput input,
  ForumBodyInlineParagraphLease parent,
) {
  final work = ForumBodyInlineEmphasisGeometryPreparation(
    input: input,
    parent: parent,
    ensureOwner: () {},
  );
  try {
    while (!work.isReady) {
      work.advance(maxParts: 1);
    }
    return work.takeGeometry();
  } finally {
    work.close();
  }
}

({ForumBodyInlineParentRows rows, int parts}) _finish(
  ForumBodyInlineParentRowPreparation work, {
  int quantum = 1,
}) {
  var parts = 0;
  try {
    for (var n = 0; !work.isReady; n++) {
      expect(n, lessThan(50000));
      final used = work.advance(maxParts: quantum);
      expect(used, inInclusiveRange(1, quantum));
      parts += used;
    }
    expect(work.advance(maxParts: 1), 0);
    return (rows: work.takeRows(), parts: parts);
  } finally {
    work.close();
  }
}

({ForumBodyInlineParagraphLease parent, ForumBodyInlineEmphasisTextInput input})
_parent(
  ForumBodyParagraphCache cache, {
  double pitch = 256,
  double width = 140,
  String prefix = 'A\nB\n',
  String suffix = ' Q\nZ',
  TextStyle style = const TextStyle(
    fontFamily: 'Ahem',
    fontSize: 20,
    color: Color(0xff123456),
  ),
  List<PlaceholderDimensions>? dimensions,
}) {
  final content = mixedInlineInput(
    prefix: prefix,
    suffix: suffix,
    paragraphStyle: 'white-space:pre-wrap;line-height:.4',
    reader: ForumBodyReaderStyle(
      textStyle: style,
      fontRevision: 'parent-rows',
      linkColor: const Color(0xff0000ff),
    ),
  ).content;
  final text = ForumBodyInlineEmphasisTextPreparation(
    content: content,
    ensureOwner: () {},
  );
  late ForumBodyInlineEmphasisTextInput input;
  try {
    while (!text.isReady) {
      text.advance(maxParts: 1);
    }
    input = text.takeInput();
  } finally {
    text.close();
  }
  final parent = cache.acquireInline(
    content: input.glyphInput.glyphs,
    width: width,
    dimensions:
        dimensions ??
        const [
          PlaceholderDimensions(
            size: Size(35.25, 40.75),
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            baselineOffset: 30.125,
          ),
        ],
    rowIsolationPitch: pitch,
  );
  addTearDown(parent.release);
  return (parent: parent, input: input);
}

Future<Uint8List> _raster(
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
  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const MixedEmphasisCurve()]) {
      for (final width in [70.0, 300.0]) {
        for (final pitch in [128.0, 256.0]) {
          for (final (index, child) in mixedEmphasisChildren.indexed) {
            test(
              'actual parent glyph strips $index/$direction/$scaler/$width/$pitch',
              () {
                final cache = _cache(),
                    fixture = MixedEmphasisParentFixture(
                      child,
                      direction: direction,
                      width: width,
                      prefix: '<span style="font-size:31px">é</span>P',
                    );
                final actual = fixture
                    .finish(fixture.open(cache, scaler: scaler), cache)
                    .value;
                addTearDown(actual.lease.release);
                final parent = cache.acquireInline(
                  content: actual.glyphInput.glyphs,
                  width: width,
                  dimensions: actual.plan.dimensions,
                  textScaler: scaler,
                  rowIsolationPitch: pitch,
                );
                addTearDown(parent.release);
                final geometry = _geometry(fixture.text, parent);
                final before = (
                  cache.layoutBuildCount,
                  cache.pictureBuildCount,
                  cache.hitCount,
                  cache.activeLeases,
                );
                final result = _finish(
                  ForumBodyInlineParentRowPreparation(
                    parent: parent,
                    geometry: geometry,
                    ensureOwner: () {},
                  ),
                );
                final grouped = _finish(
                  ForumBodyInlineParentRowPreparation(
                    parent: parent,
                    geometry: geometry,
                    ensureOwner: () {},
                  ),
                  quantum: 7,
                );
                expect(result.parts, grouped.parts);
                expect(
                  result.rows.rows.map((r) => r.selector),
                  grouped.rows.rows.map((r) => r.selector),
                );
                expect(result.rows.geometry, same(geometry));
                expect(result.rows.rows, hasLength(parent.layout.lineCount));
                var largest = 0.0;
                Rect? previous;
                for (final (i, row) in result.rows.rows.indexed) {
                  expect(row.selector.startLine, i);
                  expect(row.selector.endLine, i + 1);
                  expect(row.fontBounds, geometry.parentFontBounds[i]);
                  if (row.fontBounds case final font?) {
                    if (font.height > largest) largest = font.height;
                    expect(row.paintBounds!.contains(font.topLeft), isTrue);
                    expect(
                      row.paintBounds!.bottom,
                      greaterThanOrEqualTo(font.bottom),
                    );
                    expect(
                      row.selector.clipTop,
                      lessThanOrEqualTo(row.paintBounds!.top),
                    );
                    expect(
                      row.selector.clipBottom,
                      greaterThanOrEqualTo(row.paintBounds!.bottom),
                    );
                    if (previous != null) {
                      expect(
                        row.paintBounds!.top - previous.bottom,
                        greaterThanOrEqualTo(1),
                      );
                    }
                    previous = row.paintBounds;
                  }
                }
                expect(result.rows.fontClearance, largest);
                expect((
                  cache.layoutBuildCount,
                  cache.pictureBuildCount,
                  cache.hitCount,
                  cache.activeLeases,
                ), before);
                expect(() => result.rows.rows.clear(), throwsUnsupportedError);
                final view = ForumBodyInlineParentRowView.bind(
                  parent: parent,
                  rows: result.rows,
                  ensureOwner: () {},
                );
                final recorder = ui.PictureRecorder(),
                    canvas = Canvas(recorder);
                try {
                  expect(
                    () => view.paintParentRow(canvas, Offset.zero, 0),
                    throwsStateError,
                  );
                  cache.prepareInlineParentPaint(parent);
                  for (final (i, row) in result.rows.rows.indexed) {
                    view.paintParentRow(
                      canvas,
                      Offset(0, row.selector.originY),
                      i,
                    );
                  }
                } finally {
                  recorder.endRecording().dispose();
                }
                expect(cache.pictureBuildCount, before.$2 + 1);
                expect(
                  () => parent.layout.fragment(0, parent.layout.lineCount),
                  throwsA(isA<ForumBodyParagraphLayoutException>()),
                );
              },
            );
          }
        }
      }
    }
  }
  test(
    'parent row composition equals whole native drawing at DPR1/3',
    () async {
      for (final kind in ['plain', 'decoration', 'shadow', 'background']) {
        final style = TextStyle(
          fontFamily: 'Ahem',
          fontSize: 20,
          color: const Color(0xff123456),
          decoration: kind == 'decoration'
              ? TextDecoration.combine([
                  TextDecoration.underline,
                  TextDecoration.overline,
                ])
              : null,
          decorationStyle: TextDecorationStyle.wavy,
          decorationThickness: 1.5,
          backgroundColor: kind == 'background'
              ? const Color(0x6044ff33)
              : null,
          shadows: kind == 'shadow'
              ? const [
                  Shadow(
                    color: Color(0xffaa0000),
                    offset: Offset(2, -3),
                    blurRadius: 2,
                  ),
                ]
              : null,
        );
        final cache = _cache(),
            actual = _parent(cache, style: style),
            parent = actual.parent;
        final result = _finish(
          ForumBodyInlineParentRowPreparation(
            parent: parent,
            geometry: _geometry(actual.input, parent),
            ensureOwner: () {},
          ),
        ).rows;
        final view = ForumBodyInlineParentRowView.bind(
          parent: parent,
          rows: result,
          ensureOwner: () {},
        );
        cache.prepareInlineParentPaint(parent);
        final size = Size(
          parent.layout.width + 120,
          parent.layout.height + 120,
        );
        for (final dpr in [1.0, 3.0]) {
          final whole = await _raster(
            (c) => parent.layout.paintParent(c, const Offset(60, 60)),
            size,
            dpr,
          );
          final split = await _raster(
            (c) {
              for (final (i, row) in result.rows.indexed) {
                view.paintParentRow(
                  c,
                  Offset(60, 60 + row.selector.originY),
                  i,
                );
              }
            },
            size,
            dpr,
          );
          expect(split, orderedEquals(whole), reason: '$kind/$dpr');
          expect(
            [
              for (var i = 3; i < whole.length; i += 4) whole[i],
            ].any((a) => a != 0),
            isTrue,
          );
        }
      }
    },
  );
  test('actual tall opaque slots do not become parent font clearance', () {
    final cache = _cache(),
        actual = _parent(
          cache,
          dimensions: const [
            PlaceholderDimensions(
              size: Size(35.25, 1000),
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              baselineOffset: 500,
            ),
          ],
        );
    final rows = _finish(
      ForumBodyInlineParentRowPreparation(
        parent: actual.parent,
        geometry: _geometry(actual.input, actual.parent),
        ensureOwner: () {},
      ),
    ).rows;
    expect(
      actual.parent.layout.nativeFontClearance,
      greaterThanOrEqualTo(1000),
    );
    expect(rows.fontClearance, lessThan(100));
    expect(actual.parent.layout.dimensions.single.size.height, 1000);
  });
  test('opaque-only input creates no parent glyph or source claim', () async {
    final cache = _cache(), actual = _parent(cache, prefix: '', suffix: '');
    final rows = _finish(
      ForumBodyInlineParentRowPreparation(
        parent: actual.parent,
        geometry: _geometry(actual.input, actual.parent),
        ensureOwner: () {},
      ),
    ).rows;
    expect(rows.fontClearance, 0);
    expect(
      rows.rows.every((row) => row.isEmpty && row.paintBounds == null),
      isTrue,
    );
    final view = ForumBodyInlineParentRowView.bind(
      parent: actual.parent,
      rows: rows,
      ensureOwner: () {},
    );
    cache.prepareInlineParentPaint(actual.parent);
    final pixels = await _raster(
      (canvas) {
        for (var i = 0; i < rows.rows.length; i++) {
          view.paintParentRow(canvas, Offset.zero, i);
        }
      },
      const Size(140, 300),
      1,
    );
    expect(pixels.every((byte) => byte == 0), isTrue);
    expect(actual.parent.content.projection.atoms, hasLength(1));
  });
  test(
    'physical painting preserves a grapheme spanning multiple native rows',
    () async {
      final cache = _cache(),
          actual = _parent(
            cache,
            prefix: '👩‍👩‍👧‍👦é',
            suffix: 'Z',
            width: 1,
            dimensions: const [
              PlaceholderDimensions(
                size: Size(.5, 40.75),
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                baselineOffset: 30.125,
              ),
            ],
          );
      final parent = actual.parent;
      expect(
        parent.layout.lines.any(
          (row) => !row.canBreakBefore || !row.canBreakAfter,
        ),
        isTrue,
      );
      final rows = _finish(
        ForumBodyInlineParentRowPreparation(
          parent: parent,
          geometry: _geometry(actual.input, parent),
          ensureOwner: () {},
        ),
      ).rows;
      final view = ForumBodyInlineParentRowView.bind(
        parent: parent,
        rows: rows,
        ensureOwner: () {},
      );
      cache.prepareInlineParentPaint(parent);
      final size = Size(100, parent.layout.height + 120);
      final whole = await _raster(
        (c) => parent.layout.paintParent(c, const Offset(40, 60)),
        size,
        1,
      );
      final split = await _raster(
        (c) {
          for (final (i, row) in rows.rows.indexed) {
            view.paintParentRow(c, Offset(40, 60 + row.selector.originY), i);
          }
        },
        size,
        1,
      );
      expect(split, orderedEquals(whole));
      expect(
        [for (var i = 3; i < whole.length; i += 4) whole[i]].any((a) => a != 0),
        isTrue,
      );
      expect(
        parent.content.projection.display.text,
        actual.input.content.projection.display.text,
      );
      expect(
        () => parent.layout.fragment(0, parent.layout.lineCount),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
    },
  );
  test(
    'unsupported parent paint expansion is rejected without native work',
    () {
      final cache = _cache(),
          actual = _parent(
            cache,
            style: TextStyle(
              fontFamily: 'Ahem',
              fontSize: 20,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3,
            ),
          );
      final geometry = _geometry(actual.input, actual.parent);
      final before = (
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.hitCount,
        cache.activeLeases,
      );
      expect(
        () => _finish(
          ForumBodyInlineParentRowPreparation(
            parent: actual.parent,
            geometry: geometry,
            ensureOwner: () {},
          ),
        ),
        throwsA(
          isA<ForumBodyParagraphRowException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphRowFailure.geometry,
          ),
        ),
      );
      expect((
        cache.layoutBuildCount,
        cache.pictureBuildCount,
        cache.hitCount,
        cache.activeLeases,
      ), before);
    },
  );
  test(
    'insufficient pitch fails explicitly and requires new actual geometry on retry',
    () {
      final cache = _cache(),
          actual = _parent(cache, pitch: 32),
          parent = actual.parent,
          geometry = _geometry(actual.input, actual.parent);
      final work = ForumBodyInlineParentRowPreparation(
        parent: parent,
        geometry: geometry,
        ensureOwner: () {},
      );
      late double required;
      try {
        _finish(work);
        fail('Insufficient pitch was accepted');
      } on ForumBodyParagraphRowException catch (e) {
        expect(e.failure, ForumBodyParagraphRowFailure.isolation);
        required = e.requiredPitch!;
        expect(required, greaterThan(32));
      }
      final next = cache.acquireInline(
        content: parent.content,
        width: 140,
        dimensions: parent.layout.dimensions,
        rowIsolationPitch: required,
      );
      addTearDown(next.release);
      expect(
        () => ForumBodyInlineParentRowPreparation(
          parent: next,
          geometry: geometry,
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
      final rows = _finish(
        ForumBodyInlineParentRowPreparation(
          parent: next,
          geometry: _geometry(actual.input, next),
          ensureOwner: () {},
        ),
      ).rows;
      expect(rows.rows, hasLength(next.layout.lineCount));
      expect(cache.activeLeases, 2);
    },
  );
  test(
    'foreign, natural, stale native rows and other original source are rejected',
    () {
      final cache = _cache(),
          actual = _parent(cache),
          parent = actual.parent,
          geometry = _geometry(actual.input, actual.parent);
      final rows = _finish(
        ForumBodyInlineParentRowPreparation(
          parent: parent,
          geometry: geometry,
          ensureOwner: () {},
        ),
      ).rows;
      final foreign = _cache();
      final variants = [
        foreign.acquireInline(
          content: parent.content,
          width: 140,
          dimensions: parent.layout.dimensions,
          rowIsolationPitch: 256,
        ),
        cache.acquireInline(
          content: parent.content,
          width: 140,
          dimensions: parent.layout.dimensions,
        ),
        _parent(cache).parent,
      ];
      for (final other in variants) {
        addTearDown(other.release);
        expect(
          () => ForumBodyInlineParentRowPreparation(
            parent: other,
            geometry: geometry,
            ensureOwner: () {},
          ),
          throwsA(isA<ForumBodyParagraphRowException>()),
        );
        expect(
          () => ForumBodyInlineParentRowView.bind(
            parent: other,
            rows: rows,
            ensureOwner: () {},
          ),
          throwsA(isA<ForumBodyParagraphRowException>()),
        );
      }
      for (final other in variants) {
        other.release();
      }
      final dimensions = parent.layout.dimensions;
      parent.release();
      cache.clearUnpinned();
      final next = cache.acquireInline(
        content: parent.content,
        width: 140,
        dimensions: dimensions,
        rowIsolationPitch: 256,
      );
      addTearDown(next.release);
      expect(next.nativeInputIdentity, geometry.nativeInputIdentity);
      expect(
        () => ForumBodyInlineParentRowView.bind(
          parent: next,
          rows: rows,
          ensureOwner: () {},
        ),
        throwsA(isA<ForumBodyParagraphRowException>()),
      );
    },
  );
  test(
    'all row preparation boundaries retire borrowed work and preserve caller',
    () {
      final cache = _cache(),
          actual = _parent(cache),
          parent = actual.parent,
          geometry = _geometry(actual.input, parent);
      final parts = _finish(
        ForumBodyInlineParentRowPreparation(
          parent: parent,
          geometry: geometry,
          ensureOwner: () {},
        ),
      ).parts;
      for (var boundary = 0; boundary <= parts; boundary++) {
        var active = true;
        final work = ForumBodyInlineParentRowPreparation(
          parent: parent,
          geometry: geometry,
          ensureOwner: () {
            if (!active) throw StateError('Retired');
          },
        );
        for (var n = 0; n < boundary; n++) {
          work.advance(maxParts: 1);
        }
        active = false;
        expect(
          work.isReady ? work.takeRows : () => work.advance(maxParts: 1),
          throwsStateError,
        );
        work.close();
        expect(cache.activeLeases, 1);
      }
      expect(
        () => ForumBodyInlineParentRowPreparation(
          parent: parent,
          geometry: geometry,
          ensureOwner: () {},
          maxLines: 1,
        ),
        throwsA(
          isA<ForumBodyParagraphRowException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphRowFailure.limit,
          ),
        ),
      );
      for (final mode in [0, 1, 2]) {
        var armed = false;
        late ForumBodyInlineParentRowPreparation work;
        work = ForumBodyInlineParentRowPreparation(
          parent: parent,
          geometry: geometry,
          ensureOwner: () {
            if (armed) {
              if (mode == 0 || mode == 2 && work.isReady) {
                work.close();
              } else if (mode == 1) {
                work.advance(maxParts: 1);
              }
            }
          },
        );
        armed = true;
        expect(() => _finish(work), throwsStateError);
        expect(work.isReady, isFalse);
        expect(cache.activeLeases, 1);
      }
    },
  );
  test(
    'borrowed view checks owner, input, preparation and arguments before painting',
    () {
      final cache = _cache(),
          actual = _parent(cache),
          parent = actual.parent,
          geometry = _geometry(actual.input, parent);
      final rows = _finish(
        ForumBodyInlineParentRowPreparation(
          parent: parent,
          geometry: geometry,
          ensureOwner: () {},
        ),
      ).rows;
      var active = true;
      final view = ForumBodyInlineParentRowView.bind(
        parent: parent,
        rows: rows,
        ensureOwner: () {
          if (!active) throw StateError('Retired');
        },
      );
      final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
      try {
        expect(
          () => view.paintParentRow(canvas, Offset.zero, 0),
          throwsStateError,
        );
        cache.prepareInlineParentPaint(parent);
        expect(
          () => view.paintParentRow(canvas, const Offset(double.nan, 0), 0),
          throwsArgumentError,
        );
        expect(
          () => view.paintParentRow(canvas, Offset.zero, -1),
          throwsRangeError,
        );
        expect(
          () => view.paintParentRow(canvas, Offset.zero, rows.rows.length),
          throwsRangeError,
        );
        active = false;
        expect(
          () => view.paintParentRow(canvas, Offset.zero, 0),
          throwsStateError,
        );
        active = true;
        late ForumBodyInlineParentRowView reentrant;
        var armed = false;
        reentrant = ForumBodyInlineParentRowView.bind(
          parent: parent,
          rows: rows,
          ensureOwner: () {
            if (armed) reentrant.paintParentRow(canvas, Offset.zero, 0);
          },
        );
        armed = true;
        expect(
          () => reentrant.paintParentRow(canvas, Offset.zero, 0),
          throwsStateError,
        );
        armed = false;
        reentrant.paintParentRow(canvas, Offset.zero, 0);
        parent.release();
        expect(
          () => view.paintParentRow(canvas, Offset.zero, 0),
          throwsStateError,
        );
      } finally {
        recorder.endRecording().dispose();
      }
    },
  );
}
