import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class _Nonlinear extends TextScaler {
  const _Nonlinear();
  @override
  double scale(double size) => size < 25 ? size * 1.4 : size * 1.1;
  @override
  double get textScaleFactor => throw StateError('Use actual font sizes');
}

ForumBodyParagraphContent _content({
  TextDirection direction = TextDirection.ltr,
  String height = '.4',
  bool indent = false,
  String? html,
  TextStyle? readerTextStyle,
}) {
  final doc = const ForumBodyParser().parse(
    html:
        html ??
        '<p style="white-space:pre-wrap;line-height:$height">'
            '<span style="background-color:rgba(0,255,0,.4);text-decoration:underline">'
            'ffi é 中 العربية 👩‍👩‍👧‍👦 X  </span>'
            '<span style="font-size:31px;background-color:rgba(0,0,255,.4);color:red">'
            'A e<span style="font-size:20px">́</span> ؀<b>A</b></span>'
            '<span style="visibility:hidden;background-color:red">HIDDEN</span>\nEND\n</p>',
    sourceId: 'paint-input',
    conversionIdentity: 'none',
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: doc,
    styles: const ForumBodyStyleResolver().resolve(
      doc,
      ForumBodyReaderStyle(
        textStyle:
            readerTextStyle ??
            const TextStyle(
              fontFamily: 'Ahem',
              fontSize: 20,
              color: Color(0xff123456),
              shadows: [
                Shadow(
                  color: Color(0xffaa0000),
                  offset: Offset(2, -3),
                  blurRadius: 2,
                ),
              ],
            ),
        fontRevision: 'paint-input-ahem',
        linkColor: const Color(0xff0000ff),
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

ForumBodyParagraphCache _cache({int entries = 12}) {
  final cache = ForumBodyParagraphCache(
    maxEntries: entries,
    maxEstimatedBytes: 1 << 25,
  );
  addTearDown(cache.close);
  return cache;
}

Future<List<int>> _pixels(
  void Function(Canvas) draw,
  int height,
  int dpr,
) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder)..scale(dpr.toDouble()));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(240 * dpr, height * dpr);
    try {
      return Uint8List.fromList(
        (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List(),
      );
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

  for (final layer in ForumBodyParagraphPaintLayer.values) {
    test('equivalent independent $layer inputs share native fonts', () {
      final first = _content(), second = _content(), cache = _cache();
      ForumBodyParagraphContent select(ForumBodyParagraphContent original) {
        final phases = ForumBodyParagraphPaintInput(original);
        return switch (layer) {
          ForumBodyParagraphPaintLayer.all => original,
          ForumBodyParagraphPaintLayer.background => phases.background,
          ForumBodyParagraphPaintLayer.foreground => phases.foreground,
          ForumBodyParagraphPaintLayer.decoration => phases.decoration,
        };
      }

      final a = select(first), b = select(second);
      expect(a.textSpan, b.textSpan);
      expect(a.textSpan.hashCode, b.textSpan.hashCode);
      expect(a.textSpan.compareTo(b.textSpan), RenderComparison.identical);
      final lease = cache.acquire(
        content: a,
        width: 140,
        rowIsolationPitch: 256,
      );
      final hit = cache.tryAcquireCached(
        content: b,
        width: 140,
        rowIsolationPitch: 256,
      );
      expect(hit, isNotNull);
      expect(hit!.content, same(b));
      expect(hit.nativeInputIdentity, lease.nativeInputIdentity);
      expect(cache.layoutBuildCount, 1);
      expect(cache.pictureBuildCount, 0);
      lease.release();
      hit.release();
      expect(cache.activeLeases, 0);
    });
  }

  test('caller Paint identity remains part of every native phase', () {
    TextStyle style() => TextStyle(
      fontFamily: 'Ahem',
      fontSize: 20,
      foreground: Paint()..color = const Color(0xff123456),
    );
    final a = _content(readerTextStyle: style()),
        b = _content(readerTextStyle: style());
    final first = ForumBodyParagraphPaintInput(a),
        second = ForumBodyParagraphPaintInput(b);
    final cache = _cache();
    final pairs = [
      (a, b),
      (first.background, second.background),
      (first.foreground, second.foreground),
      (first.decoration, second.decoration),
    ];
    for (final pair in pairs) {
      expect(pair.$1.textSpan, isNot(pair.$2.textSpan));
      final lease = cache.acquire(content: pair.$1, width: 140);
      expect(cache.tryAcquireCached(content: pair.$2, width: 140), isNull);
      lease.release();
    }
  });

  for (final direction in TextDirection.values) {
    for (final scaler in [TextScaler.noScaling, const _Nonlinear()]) {
      for (final width in [1.0, 140.0]) {
        for (final height in ['.4', '1.6']) {
          test(
            'full-context native layer conservation $direction/$scaler/$width/$height',
            () async {
              final original = _content(direction: direction, height: height);
              final input = ForumBodyParagraphPaintInput(original),
                  cache = _cache();
              expect(input.original, same(original));
              expect(original.paintLayer, ForumBodyParagraphPaintLayer.all);
              expect(cache.layoutBuildCount, 0);
              for (final phase in [
                input.background,
                input.foreground,
                input.decoration,
              ]) {
                expect(phase.projection, same(original.projection));
                expect(phase.runs, same(original.runs));
                expect(phase.issues, same(original.issues));
                expect(phase.style, same(original.style));
                expect(
                  phase.textSpan.toPlainText(),
                  original.textSpan.toPlainText(),
                );
                expect(
                  phase.textSpan.children!.length,
                  original.textSpan.children!.length,
                );
              }
              final leases = [
                for (final content in [
                  original,
                  input.background,
                  input.foreground,
                  input.decoration,
                ])
                  cache.acquire(
                    content: content,
                    width: width,
                    textScaler: scaler,
                    rowIsolationPitch: 256,
                  ),
              ];
              final source = leases[0].layout;
              expect(
                leases.map((l) => l.nativeInputIdentity).toSet().length,
                4,
              );
              expect(cache.layoutBuildCount, 4);
              expect(cache.pictureBuildCount, 0);
              for (final lease in leases.skip(1)) {
                final layout = lease.layout;
                expect(layout.lines.length, source.lines.length);
                expect(layout.height, source.height);
                expect(layout.width, source.width);
                expect(layout.alphabeticBaseline, source.alphabeticBaseline);
                for (var i = 0; i < source.lines.length; i++) {
                  final a = source.lines[i], b = layout.lines[i];
                  expect(
                    (
                      b.top,
                      b.bottom,
                      b.baseline,
                      b.left,
                      b.width,
                      b.startUtf16,
                      b.endUtf16,
                      b.engineStartUtf16,
                      b.engineEndUtf16,
                      b.coverageStartUtf16,
                      b.coverageEndUtf16,
                      b.canBreakBefore,
                      b.canBreakAfter,
                    ),
                    (
                      a.top,
                      a.bottom,
                      a.baseline,
                      a.left,
                      a.width,
                      a.startUtf16,
                      a.endUtf16,
                      a.engineStartUtf16,
                      a.engineEndUtf16,
                      a.coverageStartUtf16,
                      a.coverageEndUtf16,
                      a.canBreakBefore,
                      a.canBreakAfter,
                    ),
                  );
                }
                expect(
                  layout.selectionBoxes(0, original.projection.text.length),
                  source.selectionBoxes(0, original.projection.text.length),
                );
                for (var i = 0; i < original.projection.text.length; i++) {
                  final a = source.glyphAtDisplayUtf16(i),
                      b = layout.glyphAtDisplayUtf16(i);
                  expect(b?.fontBounds, a?.fontBounds);
                  expect(b?.lineIndex, a?.lineIndex);
                  expect(b?.engineClusterRange, a?.engineClusterRange);
                }
              }
              for (final lease in leases) {
                cache.prepareTextPaint(lease);
              }
              final before = (
                cache.layoutBuildCount,
                cache.pictureBuildCount,
                cache.activeLeases,
              );
              // Isolated rows have disjoint support. Whole-phase replay is valid
              // here only; natural overlapping rows require background/foreground
              // order per physical row and distinct paint/geometry translations.
              for (final dpr in [1, 3]) {
                final h = source.height.ceil() + 160;
                final expected = await _pixels(
                  (c) => source.paint(c, const Offset(50, 80)),
                  h,
                  dpr,
                );
                final actual = await _pixels(
                  (c) {
                    leases[1].layout.paint(c, const Offset(50, 80));
                    leases[2].layout.paint(c, const Offset(50, 80));
                    leases[3].layout.paint(c, const Offset(50, 80));
                  },
                  h,
                  dpr,
                );
                expect(
                  actual,
                  expected,
                  reason: 'Native paint layers must conserve full context',
                );
              }
              expect((
                cache.layoutBuildCount,
                cache.pictureBuildCount,
                cache.activeLeases,
              ), before);
              for (final lease in leases) {
                lease.release();
              }
              cache.clearUnpinned();
              expect(cache.activeLeases, 0);
              expect(cache.entryCount, 0);
            },
          );
        }
      }
    }
  }

  test(
    'layers retain actual indent, source transformations and hidden paint',
    () {
      final original = _content(
        indent: true,
        html: '<p style="letter-spacing:-2px">AB\nCD EF GH</p>',
      );
      final input = ForumBodyParagraphPaintInput(original), cache = _cache();
      final expected = cache.acquire(content: original, width: 45);
      for (final content in [
        input.background,
        input.foreground,
        input.decoration,
      ]) {
        final lease = cache.acquire(content: content, width: 45);
        expect(
          lease.layout.firstLineIndent.requestedAdvance,
          expected.layout.firstLineIndent.requestedAdvance,
        );
        expect(
          lease.layout.firstLineIndent.appliedAdvance,
          expected.layout.firstLineIndent.appliedAdvance,
        );
        expect(lease.layout.horizontalInset, expected.layout.horizontalInset);
        expect(
          content.withFirstLineIndent(false).paintLayer,
          content.paintLayer,
        );
        final window = content.displayWindow(startUtf16: 0, endUtf16: 1);
        expect(window.paintLayer, content.paintLayer);
        final gap = content.displayWindow(startUtf16: 2, endUtf16: 3);
        expect(gap.projection.hasCollapsibleSegmentBreaks, isTrue);
        final whitespace = gap.resolveWhitespaceSegmentBreaks(
          shouldRemove: (_, _) => true,
          precedingGrapheme: 'B',
          followingGrapheme: 'C',
        );
        expect(whitespace.paintLayer, content.paintLayer);
        expect(whitespace.projection.text, isEmpty);
        lease.release();
      }
      expected.release();
      final hidden = ForumBodyParagraphPaintInput(
        _content(
          html: '<p style="visibility:hidden;background-color:red">ABC</p>',
        ),
      );
      for (final content in [
        hidden.background,
        hidden.foreground,
        hidden.decoration,
      ]) {
        for (final span in content.textSpan.children!.cast<TextSpan>()) {
          expect(span.style!.foreground!.color.a, 0);
          expect(span.style!.background!.color.a, 0);
          expect(span.style!.shadows, isEmpty);
        }
      }
    },
  );

  test('overlapping natural rows require native per-row layer order', () async {
    final input = ForumBodyParagraphPaintInput(
      _content(
        html:
            '<p style="line-height:.4;white-space:pre-wrap"><span style="background-color:rgba(0,255,0,.5)">'
            'MMM\nA B\nCCC\nD E</span></p>',
      ),
    );
    final cache = _cache();
    final leases = [
      for (final content in [
        input.original,
        input.background,
        input.foreground,
        input.decoration,
      ])
        cache.acquire(content: content, width: 140),
    ];
    expect(leases[0].layout.lines.length, greaterThan(2));
    final h = leases[0].layout.height.ceil() + 160;
    final native = await _pixels(
      (c) => leases[0].layout.paint(c, const Offset(50, 80)),
      h,
      3,
    );
    final reordered = await _pixels(
      (c) {
        leases[1].layout.paint(c, const Offset(50, 80));
        leases[2].layout.paint(c, const Offset(50, 80));
        leases[3].layout.paint(c, const Offset(50, 80));
      },
      h,
      3,
    );
    expect(
      reordered,
      isNot(native),
      reason: 'All backgrounds first changes real native overlap',
    );
    for (final lease in leases) {
      lease.release();
    }
  });

  for (final fixture in <(String, TextStyle)>[
    ('native-default', const TextStyle()),
    ('implicit-color', const TextStyle(color: Color(0xffad1246))),
    (
      'paint-color',
      TextStyle(foreground: Paint()..color = const Color(0xffad1246)),
    ),
    (
      'paint-shader',
      TextStyle(
        foreground: Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, 0),
            const Offset(120, 0),
            const [Color(0xffff0000), Color(0xff0000ff)],
          ),
      ),
    ),
    (
      'explicit-color',
      const TextStyle(
        color: Color(0xffad1246),
        decorationColor: Color(0xff00bc32),
      ),
    ),
    (
      'transparent-sentinel',
      const TextStyle(
        color: Color(0xffad1246),
        decorationColor: Color(0x00000000),
      ),
    ),
    (
      'transparent-rgb',
      const TextStyle(
        color: Color(0xffad1246),
        decorationColor: Color(0x00ff0000),
      ),
    ),
    ('transparent-text', const TextStyle(color: Color(0x00000000))),
    (
      'decoration-on-transparent-text',
      const TextStyle(
        color: Color(0x00000000),
        decorationColor: Color(0xff00bc32),
      ),
    ),
  ]) {
    test('native decoration fallback ${fixture.$1}', () async {
      final original = _content(
        html: '<p>AB <span style="font-size:31px">lp g</span> CD EF</p>',
        readerTextStyle: fixture.$2.copyWith(
          fontFamily: 'Ahem',
          fontSize: 20,
          decoration: TextDecoration.combine([
            TextDecoration.underline,
            TextDecoration.overline,
            TextDecoration.lineThrough,
          ]),
          decorationStyle: TextDecorationStyle.double,
          decorationThickness: 1.5,
        ),
      );
      final input = ForumBodyParagraphPaintInput(original), cache = _cache();
      final leases = [
        for (final content in [
          original,
          input.background,
          input.foreground,
          input.decoration,
        ])
          cache.acquire(content: content, width: 140, rowIsolationPitch: 256),
      ];
      for (final lease in leases) {
        cache.prepareTextPaint(lease);
      }
      final h = leases[0].layout.height.ceil() + 160;
      for (final dpr in [1, 3]) {
        final expected = await _pixels(
          (c) => leases[0].layout.paint(c, const Offset(50, 80)),
          h,
          dpr,
        );
        final actual = await _pixels(
          (c) {
            for (final lease in leases.skip(1)) {
              lease.layout.paint(c, const Offset(50, 80));
            }
          },
          h,
          dpr,
        );
        expect(
          actual,
          expected,
          reason: 'Decoration fallback must match native text paint',
        );
      }
      for (final lease in leases) {
        lease.release();
      }
    });
  }

  test('phases use shared request, cache-only, probe and owner contracts', () {
    final input = ForumBodyParagraphPaintInput(_content());
    final cache = _cache(), probe = cache.createBudgetProbe();
    final requests = [
      for (final content in [
        input.original,
        input.background,
        input.foreground,
        input.decoration,
      ])
        ForumBodyTextRequest.paragraph(content, rowIsolationPitch: 256),
    ];
    for (final request in requests) {
      request.includeBudget(
        probe,
        width: 140,
        textScaler: TextScaler.noScaling,
      );
      expect(
        request.acquire(
          cache,
          width: 140,
          textScaler: TextScaler.noScaling,
          cachedOnly: true,
        ),
        isNull,
      );
    }
    expect(probe.snapshotNativeIdentities().length, 4);
    expect(cache.layoutBuildCount, 0);
    expect(cache.pictureBuildCount, 0);
    final leases = [
      for (final request in requests)
        request.acquire(
          cache,
          width: 140,
          textScaler: TextScaler.noScaling,
          cachedOnly: false,
        )!,
    ];
    expect(cache.entryCount, 4);
    for (var i = 0; i < requests.length; i++) {
      final alias = requests[i].acquire(
        cache,
        width: 140,
        textScaler: TextScaler.noScaling,
        cachedOnly: true,
      )!;
      expect(alias.nativeInputIdentity, leases[i].nativeInputIdentity);
      alias.release();
    }
    final pinned = _cache(entries: 1);
    final first = requests[1].acquire(
      pinned,
      width: 140,
      textScaler: TextScaler.noScaling,
      cachedOnly: false,
    )!;
    expect(
      () => requests[2].acquire(
        pinned,
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
    first.release();
    final next = requests[2].acquire(
      pinned,
      width: 140,
      textScaler: TextScaler.noScaling,
      cachedOnly: false,
    )!;
    next.release();
    cache.close();
    expect(leases.every((l) => !l.isActive), isTrue);
    expect(cache.activeLeases, 0);
    expect(
      () => requests[1].acquire(
        cache,
        width: 140,
        textScaler: TextScaler.noScaling,
        cachedOnly: true,
      ),
      throwsStateError,
    );
    probe.close();
  });

  for (final decorationStyle in TextDecorationStyle.values) {
    test('native decoration run boundaries $decorationStyle', () async {
      final original = _content(
        html:
            '<p>AB<span style="color:red">CD</span>EF<span style="color:blue">GH</span>'
            'IJ<span>KL</span>MN<span>OP</span>QR</p>',
        readerTextStyle: TextStyle(
          fontFamily: 'Ahem',
          fontSize: 20,
          color: const Color(0xff123456),
          decoration: TextDecoration.underline,
          decorationColor: const Color(0xff00bc32),
          decorationStyle: decorationStyle,
          decorationThickness: 2,
        ),
      );
      final input = ForumBodyParagraphPaintInput(original), cache = _cache();
      final leases = [
        for (final content in [
          original,
          input.background,
          input.foreground,
          input.decoration,
        ])
          cache.acquire(content: content, width: 240, rowIsolationPitch: 256),
      ];
      for (final lease in leases) {
        cache.prepareTextPaint(lease);
      }
      final h = leases[0].layout.height.ceil() + 160;
      for (final dpr in [1, 3]) {
        final expected = await _pixels(
          (c) => leases[0].layout.paint(c, const Offset(20, 80)),
          h,
          dpr,
        );
        final actual = await _pixels(
          (c) {
            for (final lease in leases.skip(1)) {
              lease.layout.paint(c, const Offset(20, 80));
            }
          },
          h,
          dpr,
        );
        expect(
          actual,
          expected,
          reason: 'Native paint runs must not coalesce after clearing glyphs',
        );
      }
      for (final lease in leases) {
        lease.release();
      }
    });
  }

  test(
    'paint-only and source-free derivations cannot impersonate an original',
    () {
      final original = _content(),
          input = ForumBodyParagraphPaintInput(_content());
      for (final content in [
        input.background,
        input.foreground,
        input.decoration,
        ForumBodyParagraphContent.anonymousInline(
          identity: original.identity,
          fontRevision: original.fontRevision,
          styleRevision: original.styleRevision,
          style: original.style,
        ),
      ]) {
        expect(
          () => ForumBodyParagraphPaintInput(content),
          throwsArgumentError,
        );
      }
      final cache = _cache();
      final natural = cache.acquire(content: input.original, width: 140);
      final isolated = cache.acquire(
        content: input.foreground,
        width: 140,
        rowIsolationPitch: 256,
      );
      expect(
        natural.hasSameSourceAndInputsExceptRowIsolation(isolated),
        isFalse,
      );
      natural.release();
      isolated.release();
    },
  );
}
