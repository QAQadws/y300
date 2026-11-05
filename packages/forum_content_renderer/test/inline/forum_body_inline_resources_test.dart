import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_inline_fixture.dart';

ForumBodyInlineSpanContent _input({
  String before = 'A',
  String after = 'B',
  int resources = 1,
  String css = '',
}) {
  final document = const ForumBodyParser().parse(
    html:
        '<p style="$css"><span>$before</span>'
        '${List.filled(resources, '<img src="https://x/a">').join()}'
        '<span>$after</span></p>',
    sourceId: 'inline-resources',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  ForumBodyParagraphContent text(String path) =>
      const ForumBodyParagraphContentBuilder().build(
        document: document,
        styles: styles,
        path: path,
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
  final prefix = text('0/0'), suffix = text('0/${resources + 1}');
  final fence = prefix.projection.text.length;
  return ForumBodyInlineSpanContent.compose(
    identity: document.identity,
    path: '0',
    fontRevision: styles.fontRevision,
    styleRevision: styles.resolverRevision,
    style: styles.byPath['0']!,
    contexts: [prefix, suffix],
    atomicRanges: List.filled(resources, (startUtf16: fence, endUtf16: fence)),
    resourceAtoms: {for (var i = 0; i < resources; i++) i},
  );
}

PlaceholderDimensions _slot(double width, double height, double baseline) =>
    PlaceholderDimensions(
      size: Size(width, height),
      alignment: ui.PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      baselineOffset: baseline,
    );

ForumBodyInlineParagraphLayout _layout(
  ForumBodyInlineSpanContent input,
  List<PlaceholderDimensions> dimensions, {
  double width = 100,
  TextScaler scaler = TextScaler.noScaling,
}) {
  final result = ForumBodyInlineParagraphLayout.create(
    content: input,
    width: width,
    dimensions: dimensions,
    textScaler: scaler,
  );
  addTearDown(result.dispose);
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });

  test(
    'native inline resources have real baseline slots and no text glyphs',
    () {
      final input = _input(resources: 2);
      final dimensions = [_slot(22, 14, 10), _slot(16, 26, 24)];
      final layout = _layout(input, dimensions);
      expect(input.projection.display.text, 'AB');
      expect(input.textSpan.toPlainText(), 'A\uFFFC\uFFFCB');
      expect(input.runs, hasLength(2));
      expect(layout.lines, hasLength(1));
      final baseline = layout.lines.single.baseline;
      for (var i = 0; i < 2; i++) {
        final box = layout.atomBoxes[i].toRect();
        expect(box.size, dimensions[i].size);
        expect(
          box.top + dimensions[i].baselineOffset!,
          closeTo(baseline, .001),
        );
        final hit = layout.hitAt(box.center) as ForumBodyInlineAtomHit;
        expect(hit.index, i);
        expect(hit.offset, Offset(box.width / 2, box.height / 2));
        expect(
          layout.glyphAtEngineUtf16(layout.projection.atoms[i].engineUtf16),
          isNull,
        );
      }
      final selection = layout.selection(0, 2);
      expect(selection.atoms, isEmpty);
      expect(selection.textBoxes, hasLength(2));
      for (final text in selection.textBoxes) {
        for (final resource in layout.atomBoxes) {
          expect(text.toRect().overlaps(resource.toRect()), isFalse);
        }
      }
      expect(layout.parentSelectionBoxes(0, 1), hasLength(1));
      expect(layout.parentSelectionBoxes(1, 2), hasLength(1));
      expect(
        () => layout.parentSelectionBoxes(0, 2),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
      expect(input.projection.display.sourceAtUtf16(1).sourceRune, 1);
      expect(input.projection.sourceAtEngineUtf16(2).isExact, isFalse);
    },
  );

  test(
    'resource-only native rows wrap and retain distinct fragment ownership',
    () {
      final input = _input(before: '', after: '', resources: 3);
      final layout = _layout(input, List.filled(3, _slot(50, 20, 20)));
      expect(input.projection.display.text, isEmpty);
      expect(input.textSpan.toPlainText(), '\uFFFC\uFFFC\uFFFC');
      expect(input.runs, isEmpty);
      expect(layout.lines, hasLength(2));
      expect(layout.fragment(0, 1).atomIndices, [0, 1]);
      final tail = layout.fragment(1, 2);
      expect(tail.atomIndices, [2]);
      expect((tail.coverageStartUtf16, tail.coverageEndUtf16), (0, 0));
      expect(tail.engineCoverageStartUtf16, 2);
      expect(tail.engineCoverageEndUtf16, 3);
      for (final line in layout.lines) {
        expect((line.coverageStartUtf16, line.coverageEndUtf16), (0, 0));
      }
      for (var edge = 0; edge <= 3; edge++) {
        expect(layout.projection.sourceAtEngineUtf16(edge).isExact, isFalse);
      }
      expect(layout.selection(0, 0).textBoxes, isEmpty);
      expect(layout.selection(0, 0).atoms, isEmpty);
      final box = layout.atomBoxes[2].toRect();
      expect(
        (tail.hitAt(box.center - Offset(0, tail.top)) as ForumBodyInlineAtomHit)
            .index,
        2,
      );
    },
  );

  test('a trailing resource is emitted even after all real text ends', () {
    final input = _input(after: '');
    expect(input.textSpan.toPlainText(), 'A\uFFFC');
    final layout = _layout(input, [_slot(15, 12, 12)]);
    expect(layout.atomBoxes, hasLength(1));
    expect(layout.selection(0, 1).textBoxes, hasLength(1));
    expect(layout.selection(0, 1).atoms, isEmpty);
  });

  for (final before in ['', ' ']) {
    test(
      'leading resource retains a real first-line indent: after=$before',
      () {
        final input = _input(
          before: '',
          after: before,
          css: 'text-indent:10px;white-space:pre-wrap',
        );
        final layout = _layout(input, [_slot(30, 20, 20)]);
        expect(layout.projection.enginePrefix, isNotEmpty);
        expect(layout.atomBoxes.single.left, closeTo(10, .001));
        expect(layout.projection.atoms.single.isResource, isTrue);
        expect(input.projection.display.text, before);
      },
    );
  }

  test(
    'already resolved image dimensions are not multiplied by text scaling',
    () {
      final input = _input();
      final dimensions = [_slot(22, 14, 10)];
      final natural = _layout(input, dimensions);
      final scaled = _layout(
        input,
        dimensions,
        width: 200,
        scaler: TextScaler.linear(2),
      );
      expect(scaled.atomBoxes.single.toRect().size, const Size(22, 14));
      expect(
        scaled.atomBoxes.single.left,
        closeTo(2 * natural.atomBoxes.single.left, .001),
      );
      expect(scaled.height, greaterThan(natural.height));
    },
  );

  test(
    'single-level ruby contexts stay separate from neighboring resources',
    () {
      final fixture = mixedInlineInput();
      final original = fixture.content;
      final input = ForumBodyInlineSpanContent.compose(
        identity: original.identity,
        path: original.path,
        fontRevision: original.fontRevision,
        styleRevision: original.styleRevision,
        style: original.style,
        contexts: fixture.contexts,
        atomicRanges: [
          (startUtf16: 1, endUtf16: 1),
          (startUtf16: 1, endUtf16: 5),
          (startUtf16: 5, endUtf16: 5),
        ],
        resourceAtoms: {0, 2},
      );
      expect(input.textSpan.toPlainText(), 'X\uFFFC\uFFFC\uFFFCY');
      expect(
        input.resolveAtomicContexts(1, [fixture.base, fixture.annotation]),
        hasLength(2),
      );
      expect(() => input.resolveAtomicContexts(0, []), throwsArgumentError);
      expect(
        () => input.resolveAtomicContexts(2, [fixture.base]),
        throwsArgumentError,
      );
      expect(
        () => input.repartitionAtoms(
          atomicRanges: [(startUtf16: 1, endUtf16: 5)],
          softSpaceAtoms: {},
        ),
        throwsArgumentError,
      );
      final repartitioned = input.repartitionAtoms(
        atomicRanges: [
          (startUtf16: 1, endUtf16: 1),
          (startUtf16: 1, endUtf16: 3),
          (startUtf16: 3, endUtf16: 5),
          (startUtf16: 5, endUtf16: 5),
        ],
        softSpaceAtoms: {},
        resourceAtoms: {0, 3},
      );
      expect(
        repartitioned.projection.atoms
            .where((a) => a.isResource)
            .map((a) => a.displayStartUtf16),
        [1, 5],
      );
      expect(repartitioned.projection.display, same(input.projection.display));
    },
  );

  test('numeric slots cannot publish a readable ruby view or source proof', () {
    final input = _input(before: '', after: '');
    final cache = ForumBodyParagraphCache(
      maxEntries: 4,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final parent = cache.acquireInline(
      content: input,
      width: 100,
      dimensions: [_slot(20, 20, 20)],
    );
    expect(
      () => ForumBodyInlineParagraphView.adopt(
        cache: cache,
        parent: parent,
        startLine: 0,
        endLine: 1,
      ),
      throwsA(isA<ForumBodyInlineViewException>()),
    );
    expect(parent.isActive, isFalse);
    expect(cache.activeLeases, 0);
  });

  test(
    'resource geometry shares the existing cache and retires with its lease',
    () {
      final input = _input(before: '', after: '', resources: 2);
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      ForumBodyInlineParagraphLease acquire(double width) =>
          cache.acquireInline(
            content: input,
            width: 100,
            dimensions: [_slot(width, 20, 20), _slot(width, 20, 20)],
          );
      final first = acquire(50), reused = acquire(50), changed = acquire(60);
      expect(first.layout, same(reused.layout));
      expect(first.layout, isNot(same(changed.layout)));
      expect(first.layout.lines, hasLength(1));
      expect(changed.layout.lines, hasLength(2));
      expect(cache.activeLeases, 3);
      first.release();
      reused.release();
      changed.release();
      cache.close();
      expect(cache.activeLeases, 0);
      expect(first.isActive, isFalse);
      expect(() => first.layout.hitAt(Offset.zero), throwsStateError);
    },
  );
}
