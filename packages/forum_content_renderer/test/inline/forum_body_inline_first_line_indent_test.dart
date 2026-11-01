import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_inline_fixture.dart';

const dimension = PlaceholderDimensions(
  size: Size(40, 30),
  alignment: PlaceholderAlignment.baseline,
  baseline: TextBaseline.alphabetic,
  baselineOffset: 26,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });

  for (final direction in ['ltr', 'rtl']) {
    for (final alignment in ['start', 'center', 'end', 'justify']) {
      test(
        'opaque first unit keeps indent and source $direction/$alignment',
        () {
          final input = mixedInlineInput(
            prefix: '',
            suffix: 'abcdefgh',
            direction: direction,
            paragraphStyle: 'text-indent:20px;text-align:$alignment',
          ).content;
          final layout = ForumBodyInlineParagraphLayout.create(
            content: input,
            width: 60,
            dimensions: [dimension],
          );
          addTearDown(layout.dispose);
          expect(input.projection.enginePrefix, isEmpty);
          expect(layout.projection.enginePrefix.length, 2);
          expect(layout.projection.atoms.single.index, 0);
          expect(layout.projection.atoms.single.engineUtf16, 2);
          expect(layout.lines.first.coverageEndUtf16, 4);
          expect(layout.lines.first.engineCoverageEndUtf16, 3);
          final atom = layout.atomBoxes.single;
          expect(atom.left, closeTo(direction == 'ltr' ? 20 : 0, .001));
          expect(atom.right, closeTo(direction == 'ltr' ? 60 : 40, .001));
          final selected = layout.selection(0, 4);
          expect(selected.atoms.single.index, 0);
          expect(selected.textBoxes, isEmpty);
          expect(layout.fragment(0, 1).atomIndices, [0]);
          expect(layout.fragment(1, 2).atomIndices, isEmpty);
          final hit = layout.hitAt(Offset(direction == 'ltr' ? 1 : 59, 1));
          expect(hit, isA<ForumBodyInlineTextHit>());
          expect((hit as ForumBodyInlineTextHit).position.isExact, isFalse);
          expect(layout.projection.display.text, input.projection.display.text);
        },
      );
    }
  }

  test('ordinary prefix and opaque child share one native indentation', () {
    final input = mixedInlineInput(paragraphStyle: 'text-indent:20px').content;
    final layout = ForumBodyInlineParagraphLayout.create(
      content: input,
      width: 80,
      dimensions: [dimension],
    );
    addTearDown(layout.dispose);
    expect(layout.selection(0, 1).textBoxes.single.left, closeTo(20, .001));
    expect(layout.atomBoxes.single.left, closeTo(40, .001));
    expect(layout.lines.first.coverageEndUtf16, 5);
  });

  test(
    'intrinsic children keep unprefixed coordinates and cross-width reuse',
    () {
      final input = mixedInlineInput(
        paragraphStyle: 'text-indent:20px',
      ).content;
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      final first = cache.acquireInline(
        content: input,
        width: 80,
        dimensions: [dimension],
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
      final warm = cache.acquireInline(
        content: input,
        width: 120,
        dimensions: [dimension],
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      );
      expect(first.layout.projection.enginePrefix, isEmpty);
      expect(warm.layout, same(first.layout));
      expect(first.layout.width, 80);
      expect(first.layout.atomBoxes.single.left, 20);
      final wrap = cache.acquireInline(
        content: input,
        width: 100,
        dimensions: [dimension],
      );
      expect(wrap.layout.projection.enginePrefix.length, 2);
      expect(wrap.layout, isNot(same(first.layout)));
      expect(cache.layoutBuildCount, 2);
      first.release();
      warm.release();
      wrap.release();
    },
  );

  test(
    'percent and Reader em use actual current width/scale without rescaling atoms',
    () {
      final percent = mixedInlineInput(
        prefix: '',
        paragraphStyle: 'text-indent:25%',
      ).content;
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      for (final width in [80.0, 120.0, 80.0]) {
        final lease = cache.acquireInline(
          content: percent,
          width: width,
          dimensions: [dimension],
        );
        expect(lease.layout.atomBoxes.single.left, closeTo(width / 4, .001));
        expect(
          lease.layout.atomBoxes.single.right -
              lease.layout.atomBoxes.single.left,
          40,
        );
        lease.release();
      }
      expect(cache.layoutBuildCount, 2);
      final scaled = mixedInlineInput(
        prefix: '',
        reader: ForumBodyReaderStyle(
          textStyle: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            height: 1,
          ),
          fontRevision: 'scaled',
          linkColor: const Color(0xff0000ff),
          firstLineIndent: const ForumBodyLength(2, ForumBodyLengthUnit.em),
        ),
      ).content;
      final layout = ForumBodyInlineParagraphLayout.create(
        content: scaled,
        width: 200,
        dimensions: [dimension],
        textScaler: const _Scaler(),
      );
      addTearDown(layout.dispose);
      expect(layout.atomBoxes.single.left, closeTo(60, .001));
      expect(layout.atomBoxes.single.right - layout.atomBoxes.single.left, 40);
    },
  );

  test(
    'preserved manual whitespace suppresses Reader indent without source edits',
    () {
      ForumBodyReaderStyle reader() => ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
        fontRevision: 'manual',
        linkColor: const Color(0xff0000ff),
        firstLineIndent: const ForumBodyLength(2, ForumBodyLengthUnit.em),
      );
      for (final author in [false, true]) {
        final input = mixedInlineInput(
          prefix: '\u3000',
          suffix: '',
          reader: reader(),
          paragraphStyle: author ? 'text-indent:20px' : '',
        ).content;
        final layout = ForumBodyInlineParagraphLayout.create(
          content: input,
          width: 200,
          dimensions: [dimension],
        );
        addTearDown(layout.dispose);
        expect(layout.projection.enginePrefix.length, author ? 2 : 0);
        expect(layout.atomBoxes.single.left, closeTo(author ? 40 : 20, .001));
        expect(layout.projection.display.text, startsWith('\u3000'));
      }
    },
  );

  test('first-line ownership changes actual cache and preflight footprint', () {
    final first = mixedInlineInput(
      prefix: '',
      suffix: '',
      paragraphStyle: 'text-indent:20px',
    ).content;
    final continued = ForumBodyInlineSpanContent.compose(
      identity: first.identity,
      path: first.path,
      fontRevision: first.fontRevision,
      styleRevision: first.styleRevision,
      style: first.style,
      contexts: first.contexts.map((c) => c.content).toList(),
      atomicRanges: [(startUtf16: 0, endUtf16: 4)],
      appliesFirstLineIndent: false,
    );
    int quotedBytes(ForumBodyInlineSpanContent content) {
      final tiny = ForumBodyParagraphCache(maxEntries: 4, maxEstimatedBytes: 1);
      final probe = tiny.createBudgetProbe();
      try {
        probe.includeInline(
          content: content,
          width: 200,
          dimensions: [dimension],
          minimumLineCount: 1,
          textScaler: TextScaler.noScaling,
        );
        fail('One byte cannot admit the paragraph');
      } on ForumBodyParagraphBudgetException catch (error) {
        return error.requiredEstimatedBytes!;
      } finally {
        probe.close();
        tiny.close();
      }
    }

    expect(quotedBytes(first) - quotedBytes(continued), 192);
    final cache = ForumBodyParagraphCache(
      maxEntries: 4,
      maxEstimatedBytes: 1 << 20,
    );
    addTearDown(cache.close);
    final plain = cache.acquireInline(
      content: continued,
      width: 200,
      dimensions: [dimension],
    );
    final bytes = cache.estimatedRetainedBytes;
    plain.release();
    cache.clearUnpinned();
    final indented = cache.acquireInline(
      content: first,
      width: 200,
      dimensions: [dimension],
    );
    expect(cache.estimatedRetainedBytes - bytes, 192);
    final another = cache.acquireInline(
      content: continued,
      width: 200,
      dimensions: [dimension],
    );
    expect(indented.layout.atomBoxes.single.left, 20);
    expect(another.layout.atomBoxes.single.left, 0);
    expect(indented.layout, isNot(same(another.layout)));
    indented.release();
    another.release();
  });

  test(
    'warm requests still read current root scale before selecting an indent',
    () {
      final input = mixedInlineInput(
        prefix: '',
        reader: ForumBodyReaderStyle(
          textStyle: const TextStyle(
            fontFamily: 'Ahem',
            fontSize: 20,
            height: 1,
          ),
          fontRevision: 'mutable',
          linkColor: const Color(0xff0000ff),
          firstLineIndent: const ForumBodyLength(2, ForumBodyLengthUnit.em),
        ),
      ).content;
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 20,
      );
      addTearDown(cache.close);
      var factor = 1.0;
      final scaler = _CallbackScaler(() => factor);
      final cold = cache.acquireInline(
        content: input,
        width: 200,
        dimensions: [dimension],
        textScaler: scaler,
      );
      expect(cold.layout.atomBoxes.single.left, 40);
      cold.release();
      factor = 1.5;
      expect(
        cache.tryAcquireInlineCached(
          content: input,
          width: 200,
          dimensions: [dimension],
          textScaler: scaler,
        ),
        isNull,
      );
      final current = cache.acquireInline(
        content: input,
        width: 200,
        dimensions: [dimension],
        textScaler: scaler,
      );
      expect(current.layout.atomBoxes.single.left, 60);
      current.release();
      factor = double.nan;
      expect(
        () => cache.tryAcquireInlineCached(
          content: input,
          width: 200,
          dimensions: [dimension],
          textScaler: scaler,
        ),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
      expect(cache.layoutBuildCount, 2);
    },
  );

  test('nonzero length underflow cannot leave an engine-only prefix', () {
    final input = mixedInlineInput(
      prefix: '',
      reader: ForumBodyReaderStyle(
        textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
        fontRevision: 'underflow',
        linkColor: const Color(0xff0000ff),
        firstLineIndent: const ForumBodyLength(
          double.minPositive,
          ForumBodyLengthUnit.percent,
        ),
      ),
    ).content;
    expect(
      input
          .projectionForLayout(ForumBodyParagraphLayoutMode.wrap)
          .enginePrefix
          .length,
      2,
    );
    expect(
      () => ForumBodyInlineParagraphLayout.validateInputs(
        content: input,
        width: 1,
        dimensions: [
          const PlaceholderDimensions(
            size: Size(0, 30),
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            baselineOffset: 26,
          ),
        ],
        textScaler: TextScaler.noScaling,
      ),
      throwsA(
        isA<ForumBodyParagraphLayoutException>().having(
          (error) => error.failure,
          'failure',
          ForumBodyParagraphLayoutFailure.indent,
        ),
      ),
    );
  });

  test('an oversized first opaque unit never publishes a prefix-only row', () {
    final input = mixedInlineInput(
      prefix: '',
      paragraphStyle: 'text-indent:20px',
    ).content;
    expect(
      () => ForumBodyInlineParagraphLayout.create(
        content: input,
        width: 40,
        dimensions: [dimension],
      ),
      throwsA(
        isA<ForumBodyParagraphLayoutException>().having(
          (error) => error.failure,
          'failure',
          ForumBodyParagraphLayoutFailure.indent,
        ),
      ),
    );
  });
}

final class _Scaler extends TextScaler {
  const _Scaler();
  @override
  double scale(double size) => size <= 20 ? size * 1.5 : size * 1.2;
  @override
  double get textScaleFactor => 1.5;
}

final class _CallbackScaler extends TextScaler {
  const _CallbackScaler(this.factor);
  final double Function() factor;
  @override
  double scale(double size) => size * factor();
  @override
  double get textScaleFactor => factor();
}
