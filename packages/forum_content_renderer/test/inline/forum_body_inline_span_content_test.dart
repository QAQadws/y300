import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import 'test_support/mixed_inline_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('font strut admission cannot publish a standalone source-free page', () {
    final input = mixedInlineInput().content;
    final strut = ForumBodyParagraphContent.anonymousInline(
      identity: input.identity,
      fontRevision: input.fontRevision,
      styleRevision: input.styleRevision,
      style: input.style,
    );
    expect(
      () => ForumBodyTextPageContent.paragraph(strut),
      throwsArgumentError,
    );
    final cache = ForumBodyParagraphCache(
      maxEntries: 4,
      maxEstimatedBytes: 1 << 20,
    );
    final lease = cache.acquire(content: strut, width: 100);
    final composer = ForumBodyTextPageComposer(
      identity: input.identity,
      layoutId: 'strut-admission',
      width: 100,
      height: 100,
      maxPages: 10,
      maxFragments: 10,
    );
    try {
      expect(
        () => composer.append(
          lease: lease,
          paragraphIndex: 0,
          left: 0,
          spaceBefore: 0,
          spaceAtPageStart: 0,
        ),
        throwsArgumentError,
      );
      expect(lease.isActive, isTrue);
      expect(composer.needsInput, isTrue);
      composer.finish();
      expect(composer.snapshot, isEmpty);
      expect(lease.layout.sourceAt(const Offset(1, 1)).isExact, isFalse);
    } finally {
      composer.close();
      lease.release();
      cache.close();
    }
    expect(cache.activeLeases, 0);
  });

  test(
    'source-free struts cannot replace text or enter display projections',
    () {
      final fixture = mixedInlineInput();
      final original = fixture.content;
      ForumBodyParagraphContent strut({String? fontRevision}) =>
          ForumBodyParagraphContent.anonymousInline(
            identity: original.identity,
            fontRevision: fontRevision ?? original.fontRevision,
            styleRevision: original.styleRevision,
            style: original.style,
          );
      final base = strut();
      expect(base.isSourceFree, isTrue);
      expect(base.path, isNull);
      expect(base.projection.text, isEmpty);
      expect(base.runs, isEmpty);
      expect(
        base.displayWindow(startUtf16: 0, endUtf16: 0).isSourceFree,
        isTrue,
      );
      expect(
        () => ForumBodyInlineSpanContent.compose(
          identity: original.identity,
          path: original.path,
          fontRevision: original.fontRevision,
          styleRevision: original.styleRevision,
          style: original.style,
          contexts: [base, ...fixture.contexts],
          atomicRanges: [(startUtf16: 1, endUtf16: 5)],
        ),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
      expect(
        () => original.resolveAtomicContexts(0, [base, fixture.annotation]),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );

      final orphan = ForumBodyInlineSpanContent.compose(
        identity: original.identity,
        path: original.path,
        fontRevision: original.fontRevision,
        styleRevision: original.styleRevision,
        style: original.style,
        contexts: [fixture.annotation],
        atomicRanges: [(startUtf16: 0, endUtf16: 2)],
      );
      final windows = orphan.resolveAtomicContexts(0, [
        base,
        fixture.annotation,
      ]);
      expect(windows.map((window) => (window.startUtf16, window.endUtf16)), [
        (0, 0),
        (0, 2),
      ]);
      expect(
        () => orphan.resolveAtomicContexts(0, [base]),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
      expect(
        () => orphan.resolveAtomicContexts(0, [
          strut(fontRevision: 'foreign'),
          fixture.annotation,
        ]),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
    },
  );

  test(
    'real ruby IR composes actual source/styles and native engine placeholders',
    () {
      final fixture = mixedInlineInput();
      final content = fixture.content;
      expect(content.projection.display.text, 'XABxyY');
      expect(content.projection.engineText, 'X\uFFFCY');
      expect(content.textSpan.toPlainText(), content.projection.engineText);
      expect(content.runs, hasLength(4));
      expect(content.runs.map((run) => run.style.textStyle.fontSize), [
        20,
        20,
        10,
        20,
      ]);
      final children = content.textSpan.children!;
      expect(children, hasLength(3));
      expect(
        (children.first as TextSpan).style!.color,
        const Color(0xffff0000),
      );
      expect(children[1], isA<PlaceholderSpan>());
      expect((children.last as TextSpan).style!.color, const Color(0xff0000ff));
      expect(content.projection.sourceAtEngineUtf16(1).sourceRune, 1);
      expect(content.projection.sourceAtEngineUtf16(2).sourceRune, 7);
      expect(
        content.projection
            .sourceAtEngineUtf16(2, affinity: HtmlProjectionAffinity.upstream)
            .sourceRune,
        6,
      );
      expect(content.projection.sourceAtEngineUtf16(2).isExact, isFalse);
      for (
        var offset = 0;
        offset < content.projection.engineText.length;
        offset++
      ) {
        expect(
          content.textSpan.codeUnitAt(offset),
          content.projection.engineText.codeUnitAt(offset),
        );
      }
      expect(
        content.textSpan.codeUnitAt(content.projection.engineText.length),
        isNull,
      );
      expect(
        content.textSpan.getSpanForPosition(const TextPosition(offset: 1)),
        same(children[1]),
      );
      expect(() => content.runs.clear(), throwsUnsupportedError);
      expect(() => children.clear(), throwsUnsupportedError);
      fixture.contexts.clear();
      expect(content.textSpan.toPlainText(), 'X\uFFFCY');
    },
  );

  test(
    'actual child layout drives mixed wrapping and baseline without scaling twice',
    () {
      final fixture = mixedInlineInput();
      final content = fixture.content;
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final group = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: fixture.base,
        annotation: fixture.annotation,
        textScaler: const _Scaler(),
      );
      addTearDown(group.close);
      final painter =
          TextPainter(
              text: content.textSpan,
              textDirection: content.style.textDirection,
              textScaler: const _Scaler(),
            )
            ..setPlaceholderDimensions([group.placeholderDimensions])
            ..layout(maxWidth: 90);
      addTearDown(painter.dispose);
      final box = painter.inlinePlaceholderBoxes!.single;
      final lines = painter.computeLineMetrics();
      expect(lines, hasLength(2));
      expect(group.size, const Size(60, 55));
      expect(box.toRect().size, group.size);
      expect(box.top + group.baseline, closeTo(lines.first.baseline, 1e-6));
      expect(lines.last.baseline, greaterThan(lines.first.baseline));
      final boundary = painter.getLineBoundary(const TextPosition(offset: 0));
      expect(
        content.projection.displayRangeForEngineRange(
          startUtf16: boundary.start,
          endUtf16: boundary.end,
        ),
        (startUtf16: 0, endUtf16: 5),
      );
      expect(cache.activeLeases, 2);
      group.close();
      expect(cache.activeLeases, 0);
      // The mixed value is pure and survives the geometry owner's retirement.
      cache.close();
      expect(content.textSpan.toPlainText(), 'X\uFFFCY');
      expect(cache.estimatedRetainedBytes, 0);
    },
  );

  test(
    'tight line-height retains the full opaque box in the parent engine',
    () {
      final fixture = mixedInlineInput(paragraphStyle: 'line-height:0.25');
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final group = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: fixture.base,
        annotation: fixture.annotation,
        gap: 2,
      );
      addTearDown(group.close);
      final painter =
          TextPainter(
              text: fixture.content.textSpan,
              textDirection: TextDirection.ltr,
            )
            ..setPlaceholderDimensions([group.placeholderDimensions])
            ..layout(maxWidth: 60);
      addTearDown(painter.dispose);
      final box = painter.inlinePlaceholderBoxes!.single;
      final line = painter.computeLineMetrics().first;
      expect(box.top, greaterThanOrEqualTo(line.baseline - line.ascent - 1e-6));
      expect(
        box.bottom,
        lessThanOrEqualTo(line.baseline + line.descent + 1e-6),
      );
      expect(box.bottom, lessThanOrEqualTo(painter.height));
    },
  );

  test(
    'parent can paint actual base and annotation at the native placeholder',
    () async {
      final fixture = mixedInlineInput();
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final group = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: fixture.base,
        annotation: fixture.annotation,
      );
      addTearDown(group.close);
      final painter =
          TextPainter(
              text: fixture.content.textSpan,
              textDirection: TextDirection.ltr,
            )
            ..setPlaceholderDimensions([group.placeholderDimensions])
            ..layout(maxWidth: 100);
      addTearDown(painter.dispose);
      final box = painter.inlinePlaceholderBoxes!.single;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      painter.paint(canvas, Offset.zero);
      group.paint(canvas, box.toRect().topLeft);
      final picture = recorder.endRecording();
      try {
        final image = await picture.toImage(100, painter.height.ceil());
        try {
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          var above = 0;
          var below = 0;
          for (var y = box.top.ceil(); y < box.bottom.floor(); y++) {
            for (var x = box.left.ceil(); x < box.right.floor(); x++) {
              if (bytes[(y * 100 + x) * 4 + 3] > 0) {
                if (y < box.top + group.baseOffset.dy) {
                  above++;
                } else {
                  below++;
                }
              }
            }
          }
          expect(above, greaterThan(0));
          expect(below, greaterThan(0));
        } finally {
          image.dispose();
        }
      } finally {
        picture.dispose();
      }
      final annotationBox = group
          .selectionBoxes(
            part: ForumBodyRubyPart.annotation,
            startUtf16: 0,
            endUtf16: 1,
          )
          .single;
      final hit = group.sourceAt(
        Offset(
          annotationBox.left + .1,
          (annotationBox.top + annotationBox.bottom) / 2,
        ),
      );
      expect(hit.part, ForumBodyRubyPart.annotation);
      expect(hit.position.sourceRune, 4);
    },
  );

  test(
    'ordinary hidden spans keep geometry but receive the shared transparent style',
    () {
      final fixture = mixedInlineInput(
        prefix: '<b style="visibility:hidden">e\u0301</b>Q',
      );
      final spans = fixture.content.textSpan.children!
          .whereType<TextSpan>()
          .toList();
      expect(spans.first.text, 'e\u0301');
      expect(spans.first.style!.foreground!.color, const Color(0x00000000));
      expect(spans.first.style!.decoration, TextDecoration.none);
      expect(spans[1].text, 'Q');
      expect(spans[1].style!.color, const Color(0xffff0000));
      expect(fixture.content.projection.engineText, 'e\u0301Q\uFFFCY');
    },
  );

  test(
    'RTL parent uses actual engine positions while child text stays independent',
    () {
      final fixture = mixedInlineInput(
        prefix: 'א',
        base: 'אב',
        annotation: 'xy',
        suffix: 'ב',
        direction: 'rtl',
      );
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final group = ForumBodyRubyGroupLayout.create(
        cache: cache,
        base: fixture.base,
        annotation: fixture.annotation,
      );
      addTearDown(group.close);
      final painter =
          TextPainter(
              text: fixture.content.textSpan,
              textDirection: fixture.content.style.textDirection,
            )
            ..setPlaceholderDimensions([group.placeholderDimensions])
            ..layout(maxWidth: 100);
      addTearDown(painter.dispose);
      expect(fixture.content.style.textDirection, TextDirection.rtl);
      final box = painter.inlinePlaceholderBoxes!.single;
      final selected = painter.getBoxesForSelection(
        const TextSelection(baseOffset: 1, extentOffset: 2),
      );
      expect(selected.single.toRect(), box.toRect());
      expect(
        fixture.content.projection.displayRangeForEngineRange(
          startUtf16: 1,
          endUtf16: 2,
        ),
        (startUtf16: 1, endUtf16: 5),
      );
    },
  );

  test('adjacent atoms across styled contexts use one native slot each', () {
    final fixture = mixedInlineInput();
    final original = fixture.content;
    final content = ForumBodyInlineSpanContent.compose(
      identity: original.identity,
      path: original.path,
      fontRevision: original.fontRevision,
      styleRevision: original.styleRevision,
      style: original.style,
      contexts: fixture.contexts,
      atomicRanges: [
        (startUtf16: 0, endUtf16: 1),
        (startUtf16: 1, endUtf16: 5),
        (startUtf16: 5, endUtf16: 6),
      ],
    );
    expect(content.textSpan.toPlainText(), '\uFFFC\uFFFC\uFFFC');
    expect(content.textSpan.children!.whereType<TextSpan>(), isEmpty);
    const dimension = PlaceholderDimensions(
      size: Size(20, 30),
      alignment: ui.PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      baselineOffset: 20,
    );
    final painter =
        TextPainter(text: content.textSpan, textDirection: TextDirection.ltr)
          ..setPlaceholderDimensions([dimension, dimension, dimension])
          ..layout(maxWidth: 40);
    addTearDown(painter.dispose);
    expect(painter.inlinePlaceholderBoxes, hasLength(3));
    expect(painter.computeLineMetrics(), hasLength(2));
    expect(
      content.projection.displayRangeForEngineRange(startUtf16: 0, endUtf16: 2),
      (startUtf16: 0, endUtf16: 5),
    );
  });

  test('literal U+FFFC stays ordinary text beside the actual placeholder', () {
    final fixture = mixedInlineInput(prefix: '\uFFFC');
    final content = fixture.content;
    expect(content.projection.engineText, '\uFFFC\uFFFCY');
    expect(
      content.textSpan.children!.whereType<PlaceholderSpan>(),
      hasLength(1),
    );
    final painter =
        TextPainter(text: content.textSpan, textDirection: TextDirection.ltr)
          ..setPlaceholderDimensions([
            const PlaceholderDimensions(
              size: Size(40, 30),
              alignment: ui.PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              baselineOffset: 20,
            ),
          ])
          ..layout(maxWidth: 100);
    addTearDown(painter.dispose);
    expect(painter.inlinePlaceholderBoxes, hasLength(1));
    expect(content.projection.sourceAtEngineUtf16(1).sourceRune, 1);
  });

  test('composition rejects mixed document, font and style scopes', () {
    final fixture = mixedInlineInput();
    final content = fixture.content;
    ForumBodyInlineSpanContent compose({
      ForumBodyIdentity? identity,
      String? font,
      int? style,
    }) => ForumBodyInlineSpanContent.compose(
      identity: identity ?? content.identity,
      path: content.path,
      fontRevision: font ?? content.fontRevision,
      styleRevision: style ?? content.styleRevision,
      style: content.style,
      contexts: fixture.contexts,
      atomicRanges: [],
    );
    final foreign = const ForumBodyParser().parse(
      html: '<p>other</p>',
      sourceId: 'other',
      conversionIdentity: 'none',
    );
    for (final action in <void Function()>[
      () => compose(identity: foreign.identity),
      () => compose(font: 'other'),
      () => compose(style: -1),
    ]) {
      expect(
        action,
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (error) => error.failure,
            'scope failure',
            ForumBodyParagraphInputFailure.identity,
          ),
        ),
      );
    }
  });

  test(
    'source windows retain unique run ownership within the original budget',
    () {
      final fixture = mixedInlineInput(
        prefix: 'X<span style="color:green">Y</span>',
      );
      final original = fixture.content;
      final prefix = fixture.contexts.first;
      final windows = [
        prefix.displayWindow(startUtf16: 0, endUtf16: 1),
        prefix.displayWindow(startUtf16: 1, endUtf16: 2),
        ...fixture.contexts.skip(1),
      ];
      ForumBodyInlineSpanContent compose(int maxRuns) =>
          ForumBodyInlineSpanContent.compose(
            identity: original.identity,
            path: original.path,
            fontRevision: original.fontRevision,
            styleRevision: original.styleRevision,
            style: original.style,
            contexts: windows,
            atomicRanges: [(startUtf16: 2, endUtf16: 6)],
            maxRuns: maxRuns,
          );
      final split = compose(5);
      expect(split.runs, hasLength(5));
      expect(split.runs.toSet(), original.runs.toSet());
      expect(
        split.projection.display.hasSameSourceMapping(
          original.projection.display,
        ),
        isTrue,
      );
      final spans = split.textSpan.children!.whereType<TextSpan>().toList();
      expect(spans.map((span) => span.text), ['X', 'Y', 'Y']);
      expect(spans.map((span) => span.style!.color), [
        const Color(0xffff0000),
        const Color(0xff008000),
        const Color(0xff0000ff),
      ]);
      expect(
        () => compose(4),
        throwsA(isA<ForumBodyParagraphInputException>()),
      );
    },
  );

  test(
    'composition refuses source reordering and enforces all structural budgets',
    () {
      final fixture = mixedInlineInput();
      final content = fixture.content;
      ForumBodyInlineSpanContent compose({
        List<ForumBodyParagraphContent>? contexts,
        int maxInputCodeUnits = 16384,
        int maxRuns = 512,
        int maxContexts = 512,
        int maxAtoms = 512,
      }) => ForumBodyInlineSpanContent.compose(
        identity: content.identity,
        path: content.path,
        fontRevision: content.fontRevision,
        styleRevision: content.styleRevision,
        style: content.style,
        contexts: contexts ?? fixture.contexts,
        atomicRanges: [(startUtf16: 1, endUtf16: 5)],
        maxInputCodeUnits: maxInputCodeUnits,
        maxRuns: maxRuns,
        maxContexts: maxContexts,
        maxAtoms: maxAtoms,
      );
      expect(
        () => compose(contexts: fixture.contexts.reversed.toList()),
        throwsArgumentError,
      );
      for (final action in <void Function()>[
        () => compose(maxInputCodeUnits: 5),
        () => compose(maxRuns: 3),
        () => compose(maxContexts: 3),
      ]) {
        expect(action, throwsA(isA<ForumBodyParagraphInputException>()));
      }
      expect(
        () => compose(maxAtoms: 0),
        throwsA(isA<HtmlInlineTextLimitException>()),
      );
      for (final action in <void Function()>[
        () => compose(maxInputCodeUnits: -1),
        () => compose(maxRuns: -1),
        () => compose(maxContexts: -1),
        () => compose(maxAtoms: -1),
      ]) {
        expect(action, throwsArgumentError);
      }
    },
  );

  test(
    'native span demands valid pre-scaled alphabetic placeholder geometry',
    () {
      final placeholder = mixedInlineInput().content.textSpan.children!
          .whereType<PlaceholderSpan>()
          .single;
      final builder = ui.ParagraphBuilder(
        ui.ParagraphStyle(textDirection: TextDirection.ltr),
      );
      expect(() => placeholder.build(builder), throwsStateError);
      for (final dimensions in const [
        PlaceholderDimensions(
          size: Size(40, 30),
          alignment: ui.PlaceholderAlignment.bottom,
        ),
        PlaceholderDimensions(
          size: Size(40, 30),
          alignment: ui.PlaceholderAlignment.baseline,
          baseline: TextBaseline.ideographic,
          baselineOffset: 20,
        ),
        PlaceholderDimensions(
          size: Size(double.infinity, 30),
          alignment: ui.PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          baselineOffset: 20,
        ),
        PlaceholderDimensions(
          size: Size(40, 30),
          alignment: ui.PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          baselineOffset: 40,
        ),
      ]) {
        expect(
          () => placeholder.build(builder, dimensions: [dimensions]),
          throwsArgumentError,
        );
      }
      final paragraph = builder.build();
      paragraph.dispose();
    },
  );
}

final class _Scaler extends TextScaler {
  const _Scaler();
  @override
  double scale(double size) => size <= 10 ? size * 2.5 : size * 1.5;
  @override
  double get textScaleFactor => 1.5;
}
