import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

const _html =
    '<p style="text-emphasis:\'X\' red;white-space:pre-wrap;line-height:.4">'
    '<span style="text-emphasis:none;font-size:31px">大</span>AB '
    '<span style="font-size:31px">؀</span><span style="text-emphasis-position:under">A</span> '
    'e<b style="font-size:31px">́</b> '
    '<span style="text-emphasis-position:under">👩</span>'
    '<b style="text-emphasis-position:under">‍👩‍👧‍👦</b> '
    '中<a href="/synthetic">文</a>\n\n</p>';

final class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double size) => size < 20 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual sizes');
}

ForumBodyParagraphContent _content({
  String html = _html,
  TextDirection direction = TextDirection.ltr,
  bool indent = false,
  double? tracking,
}) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'emphasis-row-layout',
    conversionIdentity: 'none',
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: document,
    styles: const ForumBodyStyleResolver().resolve(
      document,
      ForumBodyReaderStyle(
        textStyle: TextStyle(
          fontFamily: 'Ahem',
          fontSize: 20,
          color: Color(0xff123456),
          letterSpacing: tracking,
        ),
        linkColor: const Color(0xff0000ff),
        fontRevision: 'row-layout-ahem',
        textDirection: direction,
        firstLineIndent: ForumBodyLength(
          indent ? 2 : 0,
          ForumBodyLengthUnit.em,
        ),
      ),
    ),
    path: '0',
  );
}

ForumBodyEmphasisGlyphInput _glyphs(ForumBodyParagraphContent source) {
  final job = ForumBodyEmphasisGlyphPreparation(content: source);
  while (!job.isReady) {
    job.advance(maxParts: 1);
  }
  return job.takeInput();
}

ForumBodyParagraphCache _cache({int entries = 16, int bytes = 1 << 24}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: bytes,
  );
  addTearDown(cache.close);
  return cache;
}

ForumBodyEmphasisRowInput _input(
  ForumBodyEmphasisGlyphInput glyphs,
  ForumBodyParagraphLease parent,
  int startLine,
) {
  final rows = ForumBodyParagraphRowPreparation(
    parent: parent,
    startLine: startLine,
    ensureOwner: () {},
  );
  while (!rows.isReady) {
    rows.advance(maxParts: 1);
  }
  final metrics = rows.takeMetrics();
  final source = ForumBodyEmphasisRowInputPreparation(
    parentGlyphInput: glyphs,
    row: metrics,
  );
  while (!source.isReady) {
    source.advance(maxParts: 1);
  }
  return source.takeInput();
}

ForumBodyEmphasisLineLayout _visible(
  ForumBodyEmphasisLinePreparation job, {
  bool cachedOnly = false,
}) {
  addTearDown(job.close);
  for (var i = 0; !job.isReady && i < 20000; i++) {
    final step = job.advance(maxParts: 1, cachedOnly: cachedOnly);
    expect(step.partsPrepared, lessThanOrEqualTo(1));
    expect(
      step.nativeLayoutsBuilt + step.picturesRecorded,
      lessThanOrEqualTo(1),
    );
    expect(step.waitingForLayoutBudget, isFalse);
    expect(job.cacheMiss, isFalse);
  }
  expect(job.isReady, isTrue);
  return job.takeLayout();
}

ForumBodyEmphasisLineMetrics _measure(
  ForumBodyEmphasisLineMetricsPreparation job,
) {
  addTearDown(job.close);
  for (var i = 0; !job.isReady && i < 20000; i++) {
    final step = job.advance(maxParts: 1);
    expect(step.partsPrepared, lessThanOrEqualTo(1));
    expect(step.nativeLayoutsBuilt, lessThanOrEqualTo(1));
    expect(step.picturesRecorded, 0);
    expect(step.waitingForLayoutBudget, isFalse);
  }
  expect(job.isReady, isTrue);
  expect(job.nativeLeases, isEmpty);
  return job.takeMetrics();
}

Future<List<int>> _pixels(
  ForumBodyEmphasisLineLayout line,
  int dpr,
  void Function(Canvas) draw,
) async {
  final rec = ui.PictureRecorder();
  draw(Canvas(rec)..scale(dpr.toDouble()));
  final picture = rec.endRecording();
  try {
    final image = await picture.toImage(
      (line.width.ceil() + 100) * dpr,
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
    picture.dispose();
  }
}

void _verifyBaselines(
  ForumBodyEmphasisLineLayout line,
  ForumBodyParagraphRowView view,
  ForumBodyEmphasisRowInput input,
  List<TextPainter> controls,
) {
  final placement =
      <(int, ForumBodyEmphasisSide), ({double edge, double extent})>{};
  for (var i = 0; i < line.marks.length; i++) {
    final mark = line.marks[i],
        raw = controls[i],
        unit = input.text.units[line.marks[i].unitIndex];
    final side = input.content.runs[unit.runIndex].style.textEmphasis.side;
    final glyph = view.glyphAtDisplayUtf16(unit.governingUtf16)!;
    var bounds = Rect.fromLTWH(0, 0, raw.width, raw.height);
    for (final box in raw.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: mark.input.mark.length),
    )) {
      bounds = bounds.expandToInclude(box.toRect());
    }
    final baseline = raw.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final edge = side == ForumBodyEmphasisSide.over
        ? glyph.fontBounds.top
        : glyph.fontBounds.bottom;
    final extent = side == ForumBodyEmphasisSide.over
        ? bounds.bottom - baseline
        : baseline - bounds.top;
    final key = (mark.lineIndex, side), old = placement[key];
    placement[key] = (
      edge: old == null
          ? edge
          : side == ForumBodyEmphasisSide.over
          ? (edge < old.edge ? edge : old.edge)
          : (edge > old.edge ? edge : old.edge),
      extent: old == null || extent > old.extent ? extent : old.extent,
    );
  }
  for (var i = 0; i < line.marks.length; i++) {
    final mark = line.marks[i],
        unit = input.text.units[line.marks[i].unitIndex];
    final side = input.content.runs[unit.runIndex].style.textEmphasis.side;
    final reference = placement[(mark.lineIndex, side)]!;
    final expected =
        reference.edge +
        (side == ForumBodyEmphasisSide.over
            ? -reference.extent
            : reference.extent) +
        line.baseOffset.dy;
    expect(
      mark.offset.dy +
          controls[i].computeDistanceToActualBaseline(TextBaseline.alphabetic),
      closeTo(expected, 1e-8),
    );
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
    for (final width in [1.0, 140.0]) {
      for (final scaler in [TextScaler.noScaling, const _Nonlinear()]) {
        test(
          'prepared row emphasis draws original context $direction/$width/$scaler',
          () async {
            final glyphs = _glyphs(_content(direction: direction)),
                cache = _cache();
            final parent = cache.acquire(
              content: glyphs.glyphs,
              width: width,
              rowIsolationPitch: 256,
              textScaler: scaler,
            );
            addTearDown(parent.release);
            var index = 0, painted = 0, multi = 0;
            while (index < parent.layout.lineCount) {
              final input = _input(glyphs, parent, index);
              final view = ForumBodyParagraphRowView.bind(
                parent: parent,
                metrics: input.row,
                ensureOwner: () {},
              );
              final job = ForumBodyEmphasisLinePreparation.row(
                input: input,
                cache: cache,
                textScaler: scaler,
                ensureOwner: () {},
              );
              final line = _visible(job);
              try {
                expect(line.metrics.rowInput, same(input));
                expect(line.projection, same(input.content.projection));
                expect(line.marks.length, input.text.units.length);
                expect(line.nativeLeases.length, 2);
                expect(cache.activeLeases, 3);
                expect(line.metrics.baseRequest.content, same(glyphs.glyphs));
                expect(
                  line.metrics.nativeFootprint.first.minimumLineCount,
                  parent.layout.lineCount,
                );
                final controls = <TextPainter>[];
                try {
                  final bySide = <(int, ForumBodyEmphasisSide), double>{};
                  for (final mark in line.marks) {
                    final unit = input.text.units[mark.unitIndex],
                        style = input.content.runs[unit.runIndex].style;
                    final baseGlyph = view.glyphAtDisplayUtf16(
                      unit.governingUtf16,
                    )!;
                    expect(mark.lineIndex, baseGlyph.lineIndex);
                    expect(
                      mark.input.textStyle.fontSize,
                      style.textStyle.fontSize! * .5,
                    );
                    expect(
                      mark.fontBounds.center.dx,
                      closeTo(baseGlyph.fontBounds.center.dx, 1e-8),
                    );
                    final raw = TextPainter(
                      text: TextSpan(
                        text: mark.input.mark,
                        style: mark.input.textStyle,
                      ),
                      textScaler: scaler,
                      textDirection: mark.input.textDirection,
                      locale: mark.input.textStyle.locale,
                    )..layout();
                    controls.add(raw);
                    final baseline =
                        mark.offset.dy +
                        raw.computeDistanceToActualBaseline(
                          TextBaseline.alphabetic,
                        );
                    final side = style.textEmphasis.side;
                    final shared = bySide.putIfAbsent((
                      mark.lineIndex,
                      side,
                    ), () => baseline);
                    expect(baseline, closeTo(shared, 1e-8));
                    if (side == ForumBodyEmphasisSide.over) {
                      expect(
                        mark.fontBounds.bottom,
                        lessThanOrEqualTo(
                          baseGlyph.fontBounds.top + line.baseOffset.dy + 1e-8,
                        ),
                      );
                    } else {
                      expect(
                        mark.fontBounds.top,
                        greaterThanOrEqualTo(
                          baseGlyph.fontBounds.bottom +
                              line.baseOffset.dy -
                              1e-8,
                        ),
                      );
                    }
                    final hit = line.sourceAt(mark.fontBounds.center),
                        expected = line.projection.sourceAtUtf16(
                          unit.governingUtf16,
                        );
                    expect(hit.sourceRune, expected.sourceRune);
                    expect(hit.isExact, isFalse);
                  }
                  expect(
                    line
                        .selectionBoxes(0, line.projection.text.length)
                        .map((b) => b.toRect()),
                    view
                        .selectionBoxes(0, line.projection.text.length)
                        .map((b) => b.toRect().shift(line.baseOffset)),
                  );
                  _verifyBaselines(line, view, input, controls);
                  final builds = cache.layoutBuildCount,
                      recordings = cache.pictureBuildCount;
                  for (final dpr in [1, 3]) {
                    final reference = await _pixels(line, dpr, (canvas) {
                      view.paint(
                        canvas,
                        const Offset(25, 25) + line.baseOffset,
                      );
                      for (var i = 0; i < line.marks.length; i++) {
                        controls[i].paint(
                          canvas,
                          const Offset(25, 25) + line.marks[i].offset,
                        );
                      }
                    });
                    expect(
                      await _pixels(
                        line,
                        dpr,
                        (canvas) => line.paint(canvas, const Offset(25, 25)),
                      ),
                      reference,
                    );
                  }
                  expect(cache.layoutBuildCount, builds);
                  expect(cache.pictureBuildCount, recordings);
                } finally {
                  for (final raw in controls) {
                    raw.dispose();
                  }
                }
                painted += line.marks.length;
                if (input.row.lineCount > 1) multi++;
              } finally {
                line.close();
              }
              expect(cache.activeLeases, 1);
              index = input.row.selector.endLine;
            }
            expect(painted, greaterThan(0));
            if (width == 1) expect(multi, greaterThan(0));
          },
        );
      }
    }
  }

  test(
    'pure row metrics reacquire whole glyphs after eviction and preserve source hits',
    () {
      final glyphs = _glyphs(_content()), cache = _cache();
      final parent = cache.acquire(
        content: glyphs.glyphs,
        width: 140,
        rowIsolationPitch: 256,
      );
      final input = _input(glyphs, parent, 0);
      final metrics = _measure(
        ForumBodyEmphasisLineMetricsPreparation.row(
          input: input,
          cache: cache,
          ensureOwner: () {},
        ),
      );
      expect(cache.pictureBuildCount, 0);
      expect(cache.activeLeases, 1);
      expect(metrics.rowInput, same(input));
      expect(
        metrics.pictureInput.commands.first.paragraphRow,
        input.row.selector,
      );
      parent.release();
      cache.clearUnpinned();
      expect(cache.entryCount, 0);
      final line = _visible(
        ForumBodyEmphasisLinePreparation.fromMetrics(
          input: input.text,
          metrics: metrics,
          cache: cache,
          ensureOwner: () {},
          width: 140,
          expectedTextScaler: TextScaler.noScaling,
        ),
      );
      try {
        expect(line.metrics, same(metrics));
        expect(cache.activeLeases, 2);
        expect(
          line.sourceAt(line.marks.first.fontBounds.center).isExact,
          isFalse,
        );
        expect(cache.preparedPictureCount, 1);
      } finally {
        line.close();
      }
      expect(cache.activeLeases, 0);
    },
  );

  test('row rebind preserves real first-line indent and negative tracking', () {
    final glyphs = _glyphs(
      _content(
        indent: true,
        tracking: -2,
        html: '<p style="text-emphasis:\'X\' red">AB CD EF GH IJ KL MN OP</p>',
      ),
    );
    final cache = _cache();
    final parent = cache.acquire(
      content: glyphs.glyphs,
      width: 140,
      rowIsolationPitch: 160,
    );
    addTearDown(parent.release);
    expect(parent.layout.firstLineIndent.appliedAdvance, greaterThan(0));
    expect(parent.layout.horizontalInset, 2);
    var index = 0, windows = 0;
    while (index < parent.layout.lineCount) {
      final input = _input(glyphs, parent, index);
      final row = ForumBodyParagraphRowView.bind(
        parent: parent,
        metrics: input.row,
        ensureOwner: () {},
      );
      final metrics = _measure(
        ForumBodyEmphasisLineMetricsPreparation.row(
          input: input,
          cache: cache,
          ensureOwner: () {},
        ),
      );
      final line = _visible(
        ForumBodyEmphasisLinePreparation.fromMetrics(
          input: input.text,
          metrics: metrics,
          cache: cache,
          ensureOwner: () {},
          width: 140,
          expectedTextScaler: TextScaler.noScaling,
        ),
      );
      try {
        expect(input.content.appliesFirstLineIndent, index == 0);
        for (final mark in line.marks) {
          final unit = input.text.units[mark.unitIndex],
              actual = row.glyphAtDisplayUtf16(unit.governingUtf16)!;
          expect(
            mark.fontBounds.center.dx,
            closeTo(actual.fontBounds.center.dx, 1e-8),
          );
          expect(
            line.sourceAt(mark.fontBounds.center).sourceRune,
            line.projection.sourceAtUtf16(unit.governingUtf16).sourceRune,
          );
        }
        expect(line.projection.text, row.projection.text);
      } finally {
        line.close();
      }
      index = input.row.selector.endLine;
      windows++;
    }
    expect(windows, greaterThan(1));
  });

  test('cached-only measured row misses do not stage native drawings', () {
    final glyphs = _glyphs(_content()), cache = _cache();
    final parent = cache.acquire(
      content: glyphs.glyphs,
      width: 140,
      rowIsolationPitch: 256,
    );
    addTearDown(parent.release);
    final input = _input(glyphs, parent, 0);
    final metrics = _measure(
      ForumBodyEmphasisLineMetricsPreparation.row(
        input: input,
        cache: cache,
        ensureOwner: () {},
      ),
    );
    final job = ForumBodyEmphasisLinePreparation.fromMetrics(
      input: input.text,
      metrics: metrics,
      cache: cache,
      ensureOwner: () {},
      width: 140,
      expectedTextScaler: TextScaler.noScaling,
    );
    for (var i = 0; !job.cacheMiss && i < 20000; i++) {
      job.advance(maxParts: 1, cachedOnly: true);
    }
    expect(job.cacheMiss, isTrue);
    expect(cache.pictureBuildCount, 0);
    job.close();
    expect(cache.activeLeases, 1);
    final ready = _visible(
      ForumBodyEmphasisLinePreparation.fromMetrics(
        input: input.text,
        metrics: metrics,
        cache: cache,
        ensureOwner: () {},
        width: 140,
        expectedTextScaler: TextScaler.noScaling,
      ),
    );
    ready.close();
    final builds = cache.layoutBuildCount, pics = cache.pictureBuildCount;
    final warm = _visible(
      ForumBodyEmphasisLinePreparation.fromMetrics(
        input: input.text,
        metrics: metrics,
        cache: cache,
        ensureOwner: () {},
        width: 140,
        expectedTextScaler: TextScaler.noScaling,
      ),
      cachedOnly: true,
    );
    warm.close();
    expect(cache.layoutBuildCount, builds);
    expect(cache.pictureBuildCount, pics);
  });

  test(
    'old row metrics reject changed actual scales and new source windows',
    () {
      final glyphs = _glyphs(_content()), cache = _cache();
      final parent = cache.acquire(
        content: glyphs.glyphs,
        width: 140,
        rowIsolationPitch: 256,
      );
      addTearDown(parent.release);
      final input = _input(glyphs, parent, 0);
      expect(
        () => _visible(
          ForumBodyEmphasisLinePreparation.row(
            input: input,
            cache: cache,
            textScaler: const _Nonlinear(),
            ensureOwner: () {},
          ),
        ),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      final metrics = _measure(
        ForumBodyEmphasisLineMetricsPreparation.row(
          input: input,
          cache: cache,
          ensureOwner: () {},
        ),
      );
      final other = _input(glyphs, parent, 0);
      expect(
        () => ForumBodyEmphasisLinePreparation.fromMetrics(
          input: other.text,
          metrics: metrics,
          cache: cache,
          ensureOwner: () {},
          width: 140,
          expectedTextScaler: TextScaler.noScaling,
        ),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      expect(
        () => _visible(
          ForumBodyEmphasisLinePreparation.fromMetrics(
            input: input.text,
            metrics: metrics,
            cache: cache,
            ensureOwner: () {},
            width: 140,
            expectedTextScaler: const _Nonlinear(),
          ),
        ),
        throwsA(isA<ForumBodyEmphasisLineException>()),
      );
      expect(cache.activeLeases, 1);
    },
  );

  test(
    'row own footprint is content failure while unrelated pin waits on same job',
    () {
      const html = '<p style="text-emphasis:\'X\' red">AB CD</p>';
      final glyphs = _glyphs(_content(html: html));
      final small = _cache(entries: 2);
      final parent = small.acquire(
        content: glyphs.glyphs,
        width: 100,
        rowIsolationPitch: 160,
      );
      addTearDown(parent.release);
      final input = _input(glyphs, parent, 0);
      expect(
        () => _visible(
          ForumBodyEmphasisLinePreparation.row(
            input: input,
            cache: small,
            ensureOwner: () {},
          ),
        ),
        throwsA(
          isA<ForumBodyParagraphBudgetException>().having(
            (e) => e.failure,
            'failure',
            ForumBodyParagraphBudgetFailure.content,
          ),
        ),
      );
      final cache = _cache(entries: 3);
      final extra = cache.acquire(
        content: ForumBodyParagraphContent.anonymousInline(
          identity: glyphs.glyphs.identity,
          fontRevision: glyphs.glyphs.fontRevision,
          styleRevision: glyphs.glyphs.styleRevision,
          style: glyphs.glyphs.style,
        ),
        width: 100,
      );
      final job = ForumBodyEmphasisLinePreparation.row(
        input: input,
        cache: cache,
        ensureOwner: () {},
      );
      var waiting = false;
      for (var i = 0; !waiting && i < 20000; i++) {
        waiting = job.advance(maxParts: 1).waitingForLayoutBudget;
      }
      expect(waiting, isTrue);
      extra.release();
      final line = _visible(job);
      line.close();
      expect(cache.activeLeases, 0);
    },
  );

  for (final retireCache in [false, true]) {
    test(
      'native row recording retirement cannot publish cache=$retireCache',
      () {
        final glyphs = _glyphs(_content()), cache = _cache();
        final parent = cache.acquire(
          content: glyphs.glyphs,
          width: 140,
          rowIsolationPitch: 256,
        );
        final input = _input(glyphs, parent, 0);
        parent.release();
        final job = ForumBodyEmphasisLinePreparation.row(
          input: input,
          cache: cache,
          ensureOwner: () {},
        );
        final oldCreate = ui.Picture.onCreate,
            oldDispose = ui.Picture.onDispose;
        var created = 0, disposed = 0;
        ui.Picture.onCreate = (_) {
          created++;
          if (retireCache) {
            cache.close();
          } else {
            job.close();
          }
        };
        ui.Picture.onDispose = (_) {
          disposed++;
        };
        try {
          expect(() => _visible(job), throwsStateError);
        } finally {
          ui.Picture.onCreate = oldCreate;
          ui.Picture.onDispose = oldDispose;
          job.close();
        }
        expect(created, 1);
        expect(disposed, 1);
        expect(cache.activeLeases, 0);
        expect(cache.preparedPictureCount, 0);
      },
    );
  }
}
