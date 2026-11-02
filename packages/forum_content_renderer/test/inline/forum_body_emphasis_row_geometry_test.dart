import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _body =
    '<p style="white-space:pre-wrap;line-height:.4;text-emphasis:dot red">'
    'ffi <b>e</b><span style="font-size:31px">́</span> '
    '<span style="font-size:31px">؀</span>A '
    '👩‍👩‍👧‍👦 <span>👩</span><b>‍👩‍👧‍👦</b> 中<a href="/synthetic">文</a>\n\n</p>';

final class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double size) => size < 25 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

ForumBodyParagraphContent _content({
  String html = _body,
  TextDirection direction = TextDirection.ltr,
  bool indent = false,
  TextAlign align = TextAlign.start,
  ForumBodyParagraphLayoutMode mode = ForumBodyParagraphLayoutMode.wrap,
}) {
  final doc = const ForumBodyParser().parse(
    html: html,
    sourceId: 'emphasis-row-geometry',
    conversionIdentity: 'none',
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: doc,
    styles: const ForumBodyStyleResolver().resolve(
      doc,
      ForumBodyReaderStyle(
        textStyle: const TextStyle(
          fontFamily: 'Ahem',
          fontSize: 20,
          color: Color(0xff123456),
        ),
        linkColor: const Color(0xff0000ff),
        fontRevision: 'emphasis-row-ahem',
        textDirection: direction,
        textAlign: align,
        firstLineIndent: ForumBodyLength(
          indent ? 2 : 0,
          ForumBodyLengthUnit.em,
        ),
      ),
    ),
    path: '0',
    layoutMode: mode,
  );
}

ForumBodyEmphasisGlyphInput _glyphs(ForumBodyParagraphContent source) {
  final job = ForumBodyEmphasisGlyphPreparation(content: source);
  addTearDown(job.close);
  while (!job.isReady) {
    expect(job.advance(maxParts: 1), 1);
  }
  return job.takeInput();
}

ForumBodyParagraphCache _cache() {
  final cache = ForumBodyParagraphCache(
    maxEntries: 8,
    maxEstimatedBytes: 1 << 24,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyParagraphRowMetrics _row(ForumBodyParagraphLease parent, int start) {
  final job = ForumBodyParagraphRowPreparation(
    parent: parent,
    startLine: start,
    ensureOwner: () {},
  );
  addTearDown(job.close);
  for (var i = 0; !job.isReady && i < 20000; i++) {
    expect(job.advance(maxParts: 1), 1);
  }
  expect(job.isReady, isTrue);
  return job.takeMetrics();
}

ForumBodyEmphasisRowInput _source(
  ForumBodyEmphasisGlyphInput parent,
  ForumBodyParagraphRowMetrics row, {
  int quantum = 1,
  int maxUnits = 512,
}) {
  final job = ForumBodyEmphasisRowInputPreparation(
    parentGlyphInput: parent,
    row: row,
    maxUnits: maxUnits,
  );
  addTearDown(job.close);
  for (var i = 0; !job.isReady && i < 20000; i++) {
    expect(job.advance(maxParts: quantum), inInclusiveRange(1, quantum));
  }
  expect(job.isReady, isTrue);
  return job.takeInput();
}

ForumBodyEmphasisTextGeometry _geometry(
  ForumBodyEmphasisRowInput input,
  ForumBodyParagraphRowView row, {
  int quantum = 1,
  int maxBoxes = 4096,
}) {
  final job = ForumBodyEmphasisGeometryPreparation.row(
    input: input,
    base: row,
    ensureOwner: () {},
    maxBoxes: maxBoxes,
  );
  addTearDown(job.close);
  for (var i = 0; !job.isReady && i < 20000; i++) {
    expect(job.advance(maxParts: quantum), inInclusiveRange(1, quantum));
  }
  expect(job.isReady, isTrue);
  return job.takeGeometry();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final width in [1.0, 80.0, 140.0]) {
      for (final scaler in [TextScaler.noScaling, const _Nonlinear()]) {
        test(
          'actual row targets preserve governing glyphs $direction/$width/$scaler',
          () {
            final source = _content(direction: direction),
                glyphs = _glyphs(source),
                cache = _cache();
            final parent = cache.acquire(
              content: glyphs.glyphs,
              width: width,
              textScaler: scaler,
              rowIsolationPitch: 256,
            );
            addTearDown(parent.release);
            final rawBuilder = ui.ParagraphBuilder(
              glyphs.glyphs.style.textStyle.getParagraphStyle(
                textAlign: glyphs.glyphs.style.textAlign,
                textDirection: direction,
                textScaler: scaler,
                strutStyle: StrutStyle.fromTextStyle(
                  glyphs.glyphs.style.textStyle,
                  height: 256 / scaler.scale(20),
                  leading: 0,
                  forceStrutHeight: true,
                ),
              ),
            );
            glyphs.glyphs.textSpan.build(rawBuilder, textScaler: scaler);
            final raw = rawBuilder.build()
              ..layout(ui.ParagraphConstraints(width: width));
            addTearDown(raw.dispose);
            final wholeJob = ForumBodyEmphasisTextPreparation.fromGlyphInput(
              glyphInput: glyphs,
            );
            while (!wholeJob.isReady) {
              wholeJob.advance(maxParts: 7);
            }
            final whole = wholeJob.takeInput();
            final globalTargets = <Object>[];
            var line = 0, spanning = 0, governingLater = 0;
            final bytes = cache.estimatedRetainedBytes;
            while (line < parent.layout.lineCount) {
              final metrics = _row(parent, line);
              final row = ForumBodyParagraphRowView.bind(
                parent: parent,
                metrics: metrics,
                ensureOwner: () {},
              );
              final input = _source(glyphs, metrics),
                  batched = _source(glyphs, metrics, quantum: 7);
              expect(input.parentGlyphInput, same(glyphs));
              expect(input.row, same(metrics));
              expect(input.content.runs, same(source.runs));
              expect(input.content.issues, same(source.issues));
              expect(
                input.text.glyphInput.glyphs.runs.length,
                glyphs.glyphs.runs.length,
              );
              for (var run = 0; run < glyphs.glyphs.runs.length; run++) {
                expect(
                  input.text.glyphInput.glyphs.runs[run],
                  same(glyphs.glyphs.runs[run]),
                );
              }
              expect(
                () => input.text.glyphInput.glyphs.runs.clear(),
                throwsUnsupportedError,
              );
              expect(
                input.text.glyphInput.glyphs.projection,
                same(input.content.projection),
              );
              expect(
                input.content.projection.hasSameSourceMapping(row.projection),
                isTrue,
              );
              expect(
                input.content.appliesFirstLineIndent,
                row.content.appliesFirstLineIndent,
              );
              expect(
                batched.text.units.map(
                  (u) =>
                      (u.startUtf16, u.endUtf16, u.governingUtf16, u.runIndex),
                ),
                input.text.units.map(
                  (u) =>
                      (u.startUtf16, u.endUtf16, u.governingUtf16, u.runIndex),
                ),
              );
              final result = _geometry(input, row),
                  batchedGeometry = _geometry(input, row, quantum: 11);
              expect(result.rowInput, same(input));
              expect(result.input, same(input.text));
              expect(result.lineCount, metrics.lineCount);
              expect(result.nativeInputIdentity, parent.nativeInputIdentity);
              for (var i = 0; i < result.targets.length; i++) {
                final target = result.targets[i], unit = input.text.units[i];
                final native = raw.getGlyphInfoAt(
                  unit.governingUtf16 + metrics.startUtf16,
                )!;
                final expectedLine = raw.getLineNumberAt(
                  unit.governingUtf16 + metrics.startUtf16,
                )!;
                expect(target.unit, same(unit));
                expect(
                  target.lineIndex,
                  expectedLine - metrics.selector.startLine,
                );
                expect(
                  target.baseline,
                  parent.layout.lines[expectedLine].baseline -
                      metrics.selector.originY,
                );
                expect(
                  target.sourceStartLine,
                  raw.getLineNumberAt(unit.startUtf16 + metrics.startUtf16)! -
                      metrics.selector.startLine,
                );
                expect(
                  target.sourceEndLine,
                  raw.getLineNumberAt(unit.endUtf16 + metrics.startUtf16 - 1)! -
                      metrics.selector.startLine +
                      1,
                );
                expect(
                  target.governingFontBounds,
                  native.graphemeClusterLayoutBounds.shift(
                    Offset(0, -metrics.selector.originY),
                  ),
                );
                expect(
                  target.boxes,
                  row.selectionBoxes(unit.startUtf16, unit.endUtf16),
                );
                expect(
                  target.fontBounds,
                  target.boxes
                      .map((b) => b.toRect())
                      .reduce((a, b) => a.expandToInclude(b)),
                );
                expect(
                  target.governingFontBounds,
                  batchedGeometry.targets[i].governingFontBounds,
                );
                if (target.sourceEndLine - target.sourceStartLine > 1) {
                  spanning++;
                }
                if (target.lineIndex > target.sourceStartLine) governingLater++;
                globalTargets.add((
                  unit.startUtf16 + metrics.startUtf16,
                  unit.endUtf16 + metrics.startUtf16,
                  unit.governingUtf16 + metrics.startUtf16,
                  unit.runIndex,
                ));
              }
              line = metrics.selector.endLine;
            }
            expect(
              globalTargets,
              whole.units.map(
                (u) => (u.startUtf16, u.endUtf16, u.governingUtf16, u.runIndex),
              ),
            );
            if (width == 1) {
              expect(spanning, greaterThan(0));
              expect(governingLater, greaterThan(0));
            }
            expect(cache.layoutBuildCount, 1);
            expect(cache.pictureBuildCount, 0);
            expect(cache.estimatedRetainedBytes, bytes);
            expect(cache.activeLeases, 1);
          },
        );
      }
    }
  }

  test(
    'long emphasis source prepares targets only for each requested actual row',
    () {
      final source = _content(
        html: '<p style="text-emphasis:dot red">${'ABCD ' * 200}</p>',
      );
      final glyphs = _glyphs(source), cache = _cache();
      final parent = cache.acquire(
        content: glyphs.glyphs,
        width: 100,
        rowIsolationPitch: 160,
      );
      addTearDown(parent.release);
      var count = 0, line = 0;
      while (line < parent.layout.lineCount) {
        final metrics = _row(parent, line),
            input = _source(glyphs, metrics, maxUnits: 5);
        count += input.text.units.length;
        expect(input.text.units.length, lessThanOrEqualTo(5));
        line = metrics.selector.endLine;
      }
      expect(count, 800);
      expect(cache.layoutBuildCount, 1);
      expect(cache.activeLeases, 1);
      expect(cache.pictureBuildCount, 0);
      expect(source.style.textEmphasis.isEnabled, isTrue);
      expect(glyphs.glyphs.style.textEmphasis.isEnabled, isFalse);
    },
  );

  test('row source proof rejects a separate equal whole glyph derivation', () {
    final original = _content(),
        first = _glyphs(original),
        second = _glyphs(original),
        cache = _cache();
    final parent = cache.acquire(
      content: first.glyphs,
      width: 100,
      rowIsolationPitch: 160,
    );
    addTearDown(parent.release);
    final metrics = _row(parent, 0);
    expect(
      () => ForumBodyEmphasisRowInputPreparation(
        parentGlyphInput: second,
        row: metrics,
      ),
      throwsA(isA<ForumBodyParagraphInputException>()),
    );
    final row = ForumBodyParagraphRowView.bind(
      parent: parent,
      metrics: metrics,
      ensureOwner: () {},
    );
    final input = _source(first, metrics), otherMetrics = _row(parent, 0);
    final other = ForumBodyParagraphRowView.bind(
      parent: parent,
      metrics: otherMetrics,
      ensureOwner: () {},
    );
    expect(
      () => ForumBodyEmphasisGeometryPreparation.row(
        input: input,
        base: other,
        ensureOwner: () {},
      ),
      throwsA(isA<ForumBodyEmphasisGeometryException>()),
    );
    expect(
      () => ForumBodyEmphasisGeometryPreparation(
        input: input.text,
        base: parent,
        ensureOwner: () {},
      ),
      throwsA(isA<ForumBodyEmphasisGeometryException>()),
    );
    expect(_geometry(input, row).targets, isNotEmpty);
  });

  test(
    'real indentation converts raw governing code units without legal-boundary snapping',
    () {
      final original = _content(indent: true),
          glyphs = _glyphs(original),
          cache = _cache();
      final parent = cache.acquire(
        content: glyphs.glyphs,
        width: 100,
        rowIsolationPitch: 256,
      );
      addTearDown(parent.release);
      var line = 0, count = 0;
      while (line < parent.layout.lineCount) {
        final metrics = _row(parent, line), input = _source(glyphs, metrics);
        final view = ForumBodyParagraphRowView.bind(
          parent: parent,
          metrics: metrics,
          ensureOwner: () {},
        );
        final geometry = _geometry(input, view);
        for (final target in geometry.targets) {
          final whole = parent.layout.glyphAtDisplayUtf16(
            metrics.startUtf16 + target.unit.governingUtf16,
          )!;
          expect(
            target.governingFontBounds,
            whole.fontBounds.shift(Offset(0, -metrics.selector.originY)),
          );
          count++;
        }
        expect(input.content.appliesFirstLineIndent, line == 0);
        line = metrics.selector.endLine;
      }
      expect(count, greaterThan(0));
      expect(() => parent.layout.glyphAtDisplayUtf16(-1), throwsRangeError);
      expect(
        () =>
            parent.layout.glyphAtDisplayUtf16(original.projection.text.length),
        throwsRangeError,
      );
    },
  );

  test(
    'pure source and borrowed geometry cancellation release no caller handles',
    () {
      final original = _content(), glyphs = _glyphs(original), cache = _cache();
      final parent = cache.acquire(
        content: glyphs.glyphs,
        width: 140,
        rowIsolationPitch: 256,
      );
      addTearDown(parent.release);
      final metrics = _row(parent, 0), input = _source(glyphs, metrics);
      final row = ForumBodyParagraphRowView.bind(
        parent: parent,
        metrics: metrics,
        ensureOwner: () {},
      );
      final sourceJob = ForumBodyEmphasisRowInputPreparation(
        parentGlyphInput: glyphs,
        row: metrics,
      );
      sourceJob.advance(maxParts: 1);
      sourceJob.close();
      sourceJob.close();
      expect(() => sourceJob.takeInput(), throwsStateError);
      expect(
        () => _source(glyphs, metrics, maxUnits: 0),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
      expect(
        () => _geometry(input, row, maxBoxes: 0),
        throwsA(isA<ForumBodyEmphasisGeometryException>()),
      );
      final job = ForumBodyEmphasisGeometryPreparation.row(
        input: input,
        base: row,
        ensureOwner: () {},
      );
      while (!job.isReady) {
        job.advance(maxParts: 1);
      }
      parent.release();
      expect(() => job.takeGeometry(), throwsStateError);
      job.close();
      expect(cache.activeLeases, 0);
    },
  );

  test(
    'public glyph queries preserve all layout modes and native alignment/scaling',
    () {
      for (final mode in ForumBodyParagraphLayoutMode.values) {
        for (final dir in TextDirection.values) {
          for (final align in TextAlign.values) {
            for (final scaler in [TextScaler.noScaling, const _Nonlinear()]) {
              final content = _glyphs(
                _content(
                  html:
                      '<p style="text-emphasis:dot;line-height:1.5">AB 中<span style="font-size:31px">CD 文</span>EF</p>',
                  mode: mode,
                  direction: dir,
                  align: align,
                ),
              ).glyphs;
              final layout = ForumBodyParagraphLayout.create(
                content: content,
                width: 140,
                textScaler: scaler,
              );
              final flutter =
                  TextPainter(
                    text: content.textSpan,
                    textAlign: align,
                    textDirection: dir,
                    textScaler: scaler,
                  )..layout(
                    minWidth:
                        mode == ForumBodyParagraphLayoutMode.intrinsicSingleLine
                        ? 0
                        : 140,
                    maxWidth: mode == ForumBodyParagraphLayoutMode.wrap
                        ? 140
                        : double.infinity,
                  );
              try {
                for (var i = 0; i < content.projection.text.length; i++) {
                  if (content.projection.text.codeUnitAt(i) == 32) continue;
                  final glyph = layout.glyphAtDisplayUtf16(i)!;
                  final native = flutter.getClosestGlyphForOffset(
                    glyph.fontBounds.center / layout.paintScale,
                  )!;
                  final bounds = native.graphemeClusterLayoutBounds;
                  expect(
                    glyph.fontBounds,
                    Rect.fromLTRB(
                      bounds.left * layout.paintScale,
                      bounds.top * layout.paintScale,
                      bounds.right * layout.paintScale,
                      bounds.bottom * layout.paintScale,
                    ),
                    reason: '$mode/$dir/$align/$scaler/$i',
                  );
                  expect(
                    glyph.engineClusterRange,
                    native.graphemeClusterCodeUnitRange,
                  );
                }
              } finally {
                flutter.dispose();
                layout.dispose();
              }
            }
          }
        }
      }
    },
  );

  test(
    'row callback retirement during a native query cannot retain late geometry',
    () {
      final original = _content(html: '<p style="text-emphasis:dot">A</p>'),
          glyphs = _glyphs(original),
          cache = _cache();
      final parent = cache.acquire(
        content: glyphs.glyphs,
        width: 140,
        rowIsolationPitch: 160,
      );
      addTearDown(parent.release);
      final metrics = _row(parent, 0), input = _source(glyphs, metrics);
      var armed = false, calls = 0;
      late ForumBodyEmphasisGeometryPreparation job;
      final row = ForumBodyParagraphRowView.bind(
        parent: parent,
        metrics: metrics,
        ensureOwner: () {
          if (armed && ++calls == 3) job.close();
        },
      );
      job = ForumBodyEmphasisGeometryPreparation.row(
        input: input,
        base: row,
        ensureOwner: () {},
      );
      job.advance(maxParts: 1);
      calls = 0;
      armed = true;
      expect(() => job.advance(maxParts: 1), throwsStateError);
      expect(() => job.takeGeometry(), throwsStateError);
      expect(job.isReady, isFalse);
      expect(parent.isActive, isTrue);
      expect(cache.activeLeases, 1);
      expect(cache.pictureBuildCount, 0);
    },
  );
}
