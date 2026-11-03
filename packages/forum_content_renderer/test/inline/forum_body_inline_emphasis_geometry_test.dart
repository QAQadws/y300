import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_inline_fixture.dart';
import 'test_support/ruby_soft_space_row_fixture.dart';

const _dimensions = [
  PlaceholderDimensions(
    size: Size(1, 10),
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    baselineOffset: 8,
  ),
];
const _prefix =
    'ffi <b>e</b><span style="font-size:31px">́</span> '
    '<span style="font-size:31px">؀</span>A '
    '👩‍👩‍👧‍👦 <span>👩</span><b>‍👩‍👧‍👦</b> 中';

final class _Curve extends TextScaler {
  const _Curve();
  @override
  double scale(double size) => size < 25 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual font sizes');
}

ForumBodyInlineEmphasisTextInput _input({
  String prefix = _prefix,
  String suffix = '文<br><br>',
  String base = 'AB',
  String annotation = 'xy',
  TextDirection direction = TextDirection.ltr,
  bool indent = false,
}) {
  final content = mixedInlineInput(
    prefix: prefix,
    suffix: suffix,
    base: base,
    annotation: annotation,
    direction: direction.name,
    paragraphStyle: 'text-emphasis:circle;line-height:.4;white-space:pre-wrap',
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        color: Color(0xff123456),
      ),
      fontRevision: 'inline-geometry',
      linkColor: const Color(0xff0000ff),
      textDirection: direction,
      textAlign: TextAlign.center,
      firstLineIndent: ForumBodyLength(indent ? 2 : 0, ForumBodyLengthUnit.em),
    ),
  ).content;
  final work = ForumBodyInlineEmphasisTextPreparation(
    content: content,
    ensureOwner: () {},
  );
  try {
    while (!work.isReady) {
      work.advance(maxParts: 1);
    }
    return work.takeInput();
  } finally {
    work.close();
  }
}

ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 8,
    maxEstimatedBytes: 1 << 24,
  );
  addTearDown(cache.close);
  return cache;
}

({ForumBodyInlineEmphasisTextGeometry value, int parts}) _geometry(
  ForumBodyInlineEmphasisTextInput input,
  ForumBodyInlineParagraphLease parent, {
  int quantum = 1,
  int maxBoxes = 4096,
  int maxGlyphQueries = 16384,
}) {
  final work = ForumBodyInlineEmphasisGeometryPreparation(
    input: input,
    parent: parent,
    ensureOwner: () {},
    maxBoxes: maxBoxes,
    maxGlyphQueries: maxGlyphQueries,
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
    return (value: work.takeGeometry(), parts: parts);
  } finally {
    work.close();
  }
}

List<Object> _values(ForumBodyInlineEmphasisTextGeometry geometry) => [
  geometry.lines,
  geometry.parentFontBounds,
  geometry.atomLineIndices,
  for (final t in geometry.targets)
    [
      t.unit,
      t.lineIndex,
      t.sourceStartLine,
      t.sourceEndLine,
      t.baseline,
      t.fontBounds,
      t.governingFontBounds,
      t.boxes,
    ],
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final width in [1.0, 80.0, 140.0]) {
      for (final scaler in [TextScaler.noScaling, const _Curve()]) {
        test(
          'whole targets and raw governing glyphs match independent native parent $direction/$width/$scaler',
          () {
            final input = _input(direction: direction, indent: width > 1),
                cache = _cache();
            final parent = cache.acquireInline(
              content: input.glyphInput.glyphs,
              width: width,
              dimensions: _dimensions,
              textScaler: scaler,
            );
            addTearDown(parent.release);
            final layout = parent.layout, glyphs = input.glyphInput.glyphs;
            final span = glyphs.textSpanWithDimensions(
              _dimensions,
              firstLineIndent: layout.firstLineIndent.appliedAdvance,
            );
            final builder = ui.ParagraphBuilder(
              glyphs.style.textStyle.getParagraphStyle(
                textAlign: glyphs.style.textAlign,
                textDirection: direction,
                textScaler: scaler,
              ),
            );
            span.build(builder, textScaler: scaler, dimensions: _dimensions);
            final raw = builder.build()
              ..layout(
                ui.ParagraphConstraints(
                  width: width - 2 * glyphs.horizontalInset,
                ),
              );
            addTearDown(raw.dispose);
            final origin = Offset(
              glyphs.horizontalInset,
              layout.lines.first.baseline -
                  raw.computeLineMetrics().first.baseline,
            );
            final before = (
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.hitCount,
              cache.estimatedRetainedBytes,
              cache.activeLeases,
            );
            final geometry = _geometry(input, parent).value,
                batched = _geometry(input, parent, quantum: 7).value;
            expect(geometry.input, same(input));
            expect(
              geometry.nativeInputIdentity,
              same(parent.nativeInputIdentity),
            );
            expect(geometry.lineCount, layout.lineCount);
            expect(geometry.lines, same(layout.lines));
            final expectedFonts = List<Rect?>.filled(layout.lineCount, null);
            final atomOffsets = {
              for (final atom in layout.projection.atoms)
                for (var n = atom.engineUtf16; n < atom.engineEndUtf16; n++) n,
            };
            var offset = 0;
            for (final scalar in layout.projection.engineText.runes) {
              if (offset >= layout.projection.enginePrefix.length &&
                  !atomOffsets.contains(offset)) {
                final glyph = raw.getGlyphInfoAt(offset),
                    row = raw.getLineNumberAt(offset);
                if (glyph != null) {
                  expect(row, isNotNull);
                  final bounds = glyph.graphemeClusterLayoutBounds.shift(
                    origin,
                  );
                  expectedFonts[row!] =
                      expectedFonts[row]?.expandToInclude(bounds) ?? bounds;
                }
              }
              offset += scalar > 0xffff ? 2 : 1;
            }
            expect(geometry.parentFontBounds, expectedFonts);
            expect(geometry.atomLineIndices, [
              for (final atom in layout.projection.atoms)
                raw.getLineNumberAt(atom.engineUtf16),
            ]);
            expect(_values(geometry), _values(batched));
            expect(geometry.targets, hasLength(input.units.length));
            var spanning = 0, governingLater = 0;
            for (final (i, t) in geometry.targets.indexed) {
              expect(t.unit, same(input.units[i]));
              final u = t.unit,
                  start = layout.projection
                      .engineAtDisplayUtf16(u.startUtf16)
                      .engineUtf16,
                  end = layout.projection
                      .engineAtDisplayUtf16(u.endUtf16)
                      .engineUtf16;
              final native = raw.getGlyphInfoAt(
                start + u.governingUtf16 - u.startUtf16,
              )!;
              final line = raw.getLineNumberAt(
                start + u.governingUtf16 - u.startUtf16,
              )!;
              final boxes = [
                for (final b in raw.getBoxesForRange(start, end))
                  TextBox.fromLTRBD(
                    b.left + origin.dx,
                    b.top + origin.dy,
                    b.right + origin.dx,
                    b.bottom + origin.dy,
                    b.direction,
                  ),
              ];
              expect(t.boxes, boxes);
              expect(
                t.fontBounds,
                boxes
                    .skip(1)
                    .fold(
                      boxes.first.toRect(),
                      (Rect r, b) => r.expandToInclude(b.toRect()),
                    ),
              );
              expect(
                t.governingFontBounds,
                native.graphemeClusterLayoutBounds.shift(origin),
              );
              expect(t.lineIndex, line);
              expect(t.baseline, layout.lines[line].baseline);
              expect(t.sourceStartLine, raw.getLineNumberAt(start));
              expect(t.sourceEndLine, raw.getLineNumberAt(end - 1)! + 1);
              spanning += t.sourceEndLine > t.sourceStartLine + 1 ? 1 : 0;
              governingLater += t.lineIndex > t.sourceStartLine ? 1 : 0;
            }
            if (width == 1) {
              expect(spanning, greaterThan(0));
              expect(governingLater, greaterThan(0));
            }
            expect((
              cache.layoutBuildCount,
              cache.pictureBuildCount,
              cache.hitCount,
              cache.estimatedRetainedBytes,
              cache.activeLeases,
            ), before);
            expect(() => geometry.targets.clear(), throwsUnsupportedError);
            expect(() => geometry.lines.clear(), throwsUnsupportedError);
            expect(
              () => geometry.parentFontBounds.clear(),
              throwsUnsupportedError,
            );
            expect(
              () => geometry.atomLineIndices.clear(),
              throwsUnsupportedError,
            );
            expect(
              () => geometry.targets.first.boxes.clear(),
              throwsUnsupportedError,
            );
            parent.release();
            cache.clearUnpinned();
            expect(cache.activeLeases, 0);
            expect(geometry.targets.first.unit, same(input.units.first));
            expect(geometry.parentFontBounds, expectedFonts);
          },
        );
      }
    }
  }
  test(
    'parent-only selection requires whole legal units and rejects any actual child overlap',
    () {
      final input = _input(prefix: 'é', suffix: 'Z'), cache = _cache();
      final parent = cache.acquireInline(
        content: input.glyphInput.glyphs,
        width: 100,
        dimensions: _dimensions,
      );
      addTearDown(parent.release);
      final layout = parent.layout, atom = layout.projection.atoms.single;
      expect(
        layout.parentSelectionBoxes(0, 2),
        layout.selection(0, 2).textBoxes,
      );
      for (final (a, b) in [
        (0, 1),
        (1, 2),
        (atom.displayStartUtf16, atom.displayEndUtf16),
        (0, atom.displayEndUtf16),
        (atom.displayStartUtf16 + 1, atom.displayEndUtf16),
      ]) {
        expect(
          () => layout.parentSelectionBoxes(a, b),
          throwsA(
            isA<ForumBodyParagraphLayoutException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphLayoutFailure.coverage,
            ),
          ),
        );
      }
      expect(layout.parentSelectionBoxes(2, 2), isEmpty);
      expect(() => layout.parentSelectionBoxes(-1, 2), throwsRangeError);
      expect(
        () => layout.parentSelectionBoxes(
          0,
          layout.projection.display.text.length + 1,
        ),
        throwsRangeError,
      );
      parent.release();
      cache.clearUnpinned();
      expect(() => layout.parentSelectionBoxes(0, 2), throwsStateError);
    },
  );
  test(
    'soft glue remains a child range even when excluded from parent targets',
    () {
      final f = RubySoftSpaceRowFixture(gapSize: 10);
      addTearDown(f.close);
      final parent = f.parent(300, [
        for (final a in f.atoms) a.placeholderDimensions,
      ]);
      try {
        final gap = parent.layout.projection.atoms[1];
        expect(gap.isSoftSpace, isTrue);
        expect(
          () => parent.layout.parentSelectionBoxes(
            gap.displayStartUtf16,
            gap.displayEndUtf16,
          ),
          throwsA(isA<ForumBodyParagraphLayoutException>()),
        );
      } finally {
        parent.release();
      }
    },
  );
  test('an equal native key cannot bind another original glyph input', () {
    final first = _input(prefix: 'ABC', suffix: 'Z'),
        other = _input(prefix: 'ABC', suffix: 'Z'),
        cache = _cache();
    final a = cache.acquireInline(
          content: first.glyphInput.glyphs,
          width: 100,
          dimensions: _dimensions,
        ),
        b = cache.acquireInline(
          content: other.glyphInput.glyphs,
          width: 100,
          dimensions: _dimensions,
        );
    addTearDown(a.release);
    addTearDown(b.release);
    expect(a.nativeInputIdentity, same(b.nativeInputIdentity));
    expect(
      () => ForumBodyInlineEmphasisGeometryPreparation(
        input: first,
        parent: b,
        ensureOwner: () {},
      ),
      throwsA(
        isA<ForumBodyEmphasisGeometryException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyEmphasisGeometryFailure.source,
        ),
      ),
    );
    expect(cache.activeLeases, 2);
    expect(_geometry(first, a).value.input, same(first));
  });
  test(
    'native geometry keys track actual parent width and physical child geometry',
    () {
      final input = _input(prefix: 'ABC DEF', suffix: 'Z'), cache = _cache();
      final keys = <Object>[];
      for (final (width, dimensions) in [
        (80.0, _dimensions),
        (140.0, _dimensions),
        (
          140.0,
          [
            const PlaceholderDimensions(
              size: Size(20, 30),
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              baselineOffset: 25,
            ),
          ],
        ),
      ]) {
        final parent = cache.acquireInline(
          content: input.glyphInput.glyphs,
          width: width,
          dimensions: dimensions,
        );
        try {
          keys.add(_geometry(input, parent).value.nativeInputIdentity);
        } finally {
          parent.release();
        }
      }
      expect(keys.toSet(), hasLength(3));
    },
  );
  test(
    'box limits and close never release a borrowed parent or publish partial results',
    () {
      final input = _input(prefix: 'A', suffix: 'Z'), cache = _cache();
      final parent = cache.acquireInline(
        content: input.glyphInput.glyphs,
        width: 100,
        dimensions: _dimensions,
      );
      addTearDown(parent.release);
      final work = ForumBodyInlineEmphasisGeometryPreparation(
        input: input,
        parent: parent,
        ensureOwner: () {},
        maxBoxes: 0,
      );
      expect(
        () {
          while (!work.isReady) {
            work.advance(maxParts: 1);
          }
        },
        throwsA(
          isA<ForumBodyEmphasisGeometryException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyEmphasisGeometryFailure.limit,
          ),
        ),
      );
      expect(work.isReady, isFalse);
      expect(work.takeGeometry, throwsStateError);
      work.close();
      expect(parent.isActive, isTrue);
      expect(cache.activeLeases, 1);
      expect(
        () => ForumBodyInlineEmphasisGeometryPreparation(
          input: input,
          parent: parent,
          ensureOwner: () {},
          maxBoxes: -1,
        ),
        throwsArgumentError,
      );
      final valid = ForumBodyInlineEmphasisGeometryPreparation(
        input: input,
        parent: parent,
        ensureOwner: () {},
      );
      expect(() => valid.advance(maxParts: 0), throwsArgumentError);
      valid.close();
      expect(() => valid.advance(maxParts: 1), throwsStateError);
      expect(parent.isActive, isTrue);
    },
  );
  test('a zero-target all-atomic parent needs no box budget', () {
    final input = _input(prefix: '', suffix: ''), cache = _cache();
    final parent = cache.acquireInline(
      content: input.glyphInput.glyphs,
      width: 100,
      dimensions: _dimensions,
    );
    addTearDown(parent.release);
    final result = _geometry(
      input,
      parent,
      maxBoxes: 0,
      maxGlyphQueries: 0,
    ).value;
    expect(result.targets, isEmpty);
    expect(result.lineCount, parent.layout.lineCount);
    expect(result.parentFontBounds, [null]);
    expect(result.atomLineIndices, [0]);
    expect(cache.activeLeases, 1);
  });
  test('unmarked parent fonts participate even with no marker targets', () {
    final input = _input(
          prefix: '<span style="font-size:66px;text-emphasis:none">。 </span>',
          suffix: '<span style="text-emphasis:none">😀</span>',
        ),
        cache = _cache();
    final parent = cache.acquireInline(
      content: input.glyphInput.glyphs,
      width: 500,
      dimensions: _dimensions,
    );
    addTearDown(parent.release);
    final value = _geometry(input, parent).value;
    expect(value.targets, isEmpty);
    expect(value.parentFontBounds.single, isNotNull);
    final font = value.parentFontBounds.single!;
    expect(
      font.height,
      greaterThan(
        parent.layout.lines.single.bottom - parent.layout.lines.single.top,
      ),
    );
    final engine = parent.layout.projection.engineText;
    for (var i = 0; i < engine.length; i++) {
      final glyph = parent.layout.glyphAtEngineUtf16(i);
      if (glyph != null) {
        expect(font.expandToInclude(glyph.fontBounds), font);
      }
    }
  });
  test('scalar query budget skips surrogate tails and complete child text', () {
    final input = _input(
          prefix: '😀',
          suffix: '',
          base: '基' * 512,
          annotation: '注' * 512,
        ),
        cache = _cache();
    final parent = cache.acquireInline(
      content: input.glyphInput.glyphs,
      width: 100,
      dimensions: _dimensions,
    );
    addTearDown(parent.release);
    final before = (
      cache.layoutBuildCount,
      cache.pictureBuildCount,
      cache.hitCount,
      cache.activeLeases,
    );
    final value = _geometry(input, parent, maxGlyphQueries: 1).value;
    expect(value.targets, hasLength(1));
    expect(value.parentFontBounds.single, isNotNull);
    expect(value.atomLineIndices, [0]);
    expect(
      () => _geometry(input, parent, maxGlyphQueries: 0),
      throwsA(
        isA<ForumBodyEmphasisGeometryException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyEmphasisGeometryFailure.limit,
        ),
      ),
    );
    expect(
      () => ForumBodyInlineEmphasisGeometryPreparation(
        input: input,
        parent: parent,
        ensureOwner: () {},
        maxGlyphQueries: -1,
      ),
      throwsArgumentError,
    );
    expect((
      cache.layoutBuildCount,
      cache.pictureBuildCount,
      cache.hitCount,
      cache.activeLeases,
    ), before);
  });
  for (final direction in TextDirection.values) {
    for (final width in [35.0, 300.0]) {
      test(
        'actual child and soft-slot rows exclude parent fonts $direction/$width',
        () {
          final f = RubySoftSpaceRowFixture(direction: direction, gapSize: 10);
          addTearDown(f.close);
          final prep = ForumBodyInlineEmphasisTextPreparation(
            content: f.content,
            ensureOwner: () {},
          );
          late ForumBodyInlineEmphasisTextInput input;
          try {
            while (!prep.isReady) {
              prep.advance(maxParts: 1);
            }
            input = prep.takeInput();
          } finally {
            prep.close();
          }
          final parent = f.parent(width, [
            for (final a in f.atoms) a.placeholderDimensions,
          ]);
          try {
            final value = _geometry(
              input,
              parent,
              maxGlyphQueries: 0,
              maxBoxes: 0,
            ).value;
            expect(value.parentFontBounds, everyElement(isNull));
            expect(value.atomLineIndices, [
              for (final atom in parent.layout.projection.atoms)
                parent.layout.lines.indexWhere(
                  (l) =>
                      atom.engineUtf16 >= l.engineCoverageStartUtf16 &&
                      atom.engineUtf16 < l.engineCoverageEndUtf16,
                ),
            ]);
            expect(value.atomLineIndices.every((i) => i >= 0), isTrue);
            expect(
              parent.layout.trimmedAtomIndices,
              width == 35 ? [1] : isEmpty,
            );
            expect(f.cache.activeLeases, 1);
          } finally {
            parent.release();
          }
          expect(f.cache.activeLeases, 0);
        },
      );
    }
  }
  test('every row, query, box and ready publication checks its owner', () {
    final input = _input(
          prefix: 'A e<span style="font-size:31px">́</span>',
          suffix: 'Z',
        ),
        cache = _cache();
    final parent = cache.acquireInline(
      content: input.glyphInput.glyphs,
      width: 40,
      dimensions: _dimensions,
    );
    addTearDown(parent.release);
    final parts = _geometry(input, parent).parts;
    for (var boundary = 0; boundary <= parts; boundary++) {
      var active = true;
      final work = ForumBodyInlineEmphasisGeometryPreparation(
        input: input,
        parent: parent,
        ensureOwner: () {
          if (!active) throw StateError('Retired');
        },
      );
      for (var n = 0; n < boundary; n++) {
        work.advance(maxParts: 1);
      }
      active = false;
      if (work.isReady) {
        expect(work.takeGeometry, throwsStateError);
      } else {
        expect(() => work.advance(maxParts: 1), throwsStateError);
      }
      expect(work.isReady, isFalse);
      expect(work.takeGeometry, throwsStateError);
      work.close();
      expect(cache.activeLeases, 1);
    }
  });
  test('released parent cannot publish active or ready geometry', () {
    final input = _input(prefix: 'A', suffix: 'Z'), cache = _cache();
    for (final ready in [false, true]) {
      final parent = cache.acquireInline(
        content: input.glyphInput.glyphs,
        width: 100,
        dimensions: _dimensions,
      );
      final work = ForumBodyInlineEmphasisGeometryPreparation(
        input: input,
        parent: parent,
        ensureOwner: () {},
      );
      if (ready) {
        while (!work.isReady) {
          work.advance(maxParts: 1);
        }
      }
      parent.release();
      if (ready) {
        expect(work.takeGeometry, throwsStateError);
      } else {
        expect(() => work.advance(maxParts: 1), throwsStateError);
      }
      expect(work.isReady, isFalse);
      work.close();
      expect(cache.activeLeases, 0);
    }
  });
  test('owner callback cannot reenter, close or retire ready publication', () {
    final input = _input(prefix: 'A', suffix: 'Z'), cache = _cache();
    final parent = cache.acquireInline(
      content: input.glyphInput.glyphs,
      width: 100,
      dimensions: _dimensions,
    );
    addTearDown(parent.release);
    for (final mode in [0, 1, 2]) {
      var armed = false;
      late ForumBodyInlineEmphasisGeometryPreparation work;
      work = ForumBodyInlineEmphasisGeometryPreparation(
        input: input,
        parent: parent,
        ensureOwner: () {
          if (!armed) return;
          if (mode == 0) {
            work.advance(maxParts: 1);
          } else if (mode == 1 || work.isReady) {
            work.close();
          }
        },
      );
      armed = true;
      expect(() {
        while (!work.isReady) {
          work.advance(maxParts: 1);
        }
      }, throwsStateError);
      expect(work.isReady, isFalse);
      work.close();
      expect(cache.activeLeases, 1);
    }
  });
}
