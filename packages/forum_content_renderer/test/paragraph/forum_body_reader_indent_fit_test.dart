import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import '../inline/test_support/mixed_inline_fixture.dart';

ForumBodyReaderStyle reader({
  TextDirection direction = TextDirection.ltr,
  ForumBodyLength indent = const ForumBodyLength(4, ForumBodyLengthUnit.em),
}) => ForumBodyReaderStyle(
  textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
  fontRevision: 'reader-indent-fit',
  linkColor: const Color(0xff0000ff),
  firstLineIndent: indent,
  textDirection: direction,
  paragraphAfter: 0,
);

ForumBodyParagraphContent content(String html, ForumBodyReaderStyle options) {
  final doc = const ForumBodyParser().parse(
    html: html,
    sourceId: 'reader-indent-fit',
    conversionIdentity: 'none',
  );
  return const ForumBodyParagraphContentBuilder().build(
    document: doc,
    styles: const ForumBodyStyleResolver().resolve(doc, options),
    path: '0',
  );
}

const dimensions = [
  PlaceholderDimensions(
    size: Size(40, 30),
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    baselineOffset: 26,
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'packages/forum_content_renderer/ForumBodyInlineSpace',
    )..addFont(rootBundle.load('assets/fonts/inline_space.ttf'))).load();
  });
  for (final direction in TextDirection.values) {
    for (final width in [20.0, 25.0, 40.0]) {
      test('ordinary reader fits first real grapheme $direction/$width', () {
        final input = content('<p>abcdef</p>', reader(direction: direction));
        final cache = ForumBodyParagraphCache(
          maxEntries: 4,
          maxEstimatedBytes: 1 << 20,
        );
        addTearDown(cache.close);
        final lease = cache.acquire(content: input, width: width);
        final layout = lease.layout;
        final geometry = layout.firstLineIndent;
        expect(geometry.requestedAdvance, 80);
        expect(geometry.appliedAdvance, closeTo(width - 20, .001));
        expect(geometry.isReduced, isTrue);
        expect(geometry.layoutPasses, inInclusiveRange(2, 3));
        expect(layout.lines.first.coverageEndUtf16, 1);
        expect(layout.lines.first.engineCoverageEndUtf16, 3);
        final box = layout.selectionBoxes(0, 1).single;
        expect(
          direction == TextDirection.ltr ? box.left : width - box.right,
          closeTo(geometry.appliedAdvance, .001),
        );
        expect(layout.projection.text, 'abcdef');
        expect(
          input.style.indent,
          const ForumBodyLength(4, ForumBodyLengthUnit.em),
        );
        lease.release();
        final warm = cache.tryAcquireCached(content: input, width: width)!;
        expect(warm.layout, same(layout));
        expect(
          warm.layout.firstLineIndent.appliedAdvance,
          geometry.appliedAdvance,
        );
        expect(cache.layoutBuildCount, 1);
        warm.release();
      });
    }
    for (final width in [40.0, 50.0, 60.0]) {
      test(
        'opaque reader fits without shifting atom identity $direction/$width',
        () {
          final input = mixedInlineInput(
            prefix: '',
            suffix: 'abcdef',
            direction: direction.name,
            reader: reader(direction: direction),
          ).content;
          final cache = ForumBodyParagraphCache(
            maxEntries: 4,
            maxEstimatedBytes: 1 << 20,
          );
          addTearDown(cache.close);
          final lease = cache.acquireInline(
            content: input,
            width: width,
            dimensions: dimensions,
          );
          final layout = lease.layout;
          final geometry = layout.firstLineIndent;
          expect(geometry.requestedAdvance, 80);
          expect(geometry.appliedAdvance, closeTo(width - 40, .001));
          expect(geometry.layoutPasses, inInclusiveRange(2, 3));
          expect(layout.projection.enginePrefix.length, 2);
          expect(layout.projection.atoms.single.engineUtf16, 2);
          expect(layout.lines.first.coverageEndUtf16, 4);
          expect(layout.fragment(0, 1).atomIndices, [0]);
          final box = layout.atomBoxes.single;
          expect(
            direction == TextDirection.ltr ? box.left : width - box.right,
            closeTo(geometry.appliedAdvance, .001),
          );
          expect(layout.selection(0, 4).atoms.single.index, 0);
          lease.release();
          final warm = cache.tryAcquireInlineCached(
            content: input,
            width: width,
            dimensions: dimensions,
          )!;
          expect(warm.layout, same(layout));
          expect(cache.layoutBuildCount, 1);
          warm.release();
        },
      );
    }
  }

  test(
    'normal reader needs one layout and explicit author indent remains strict',
    () {
      final ordinary = ForumBodyParagraphLayout.create(
        content: content('<p>abc</p>', reader()),
        width: 200,
      );
      addTearDown(ordinary.dispose);
      expect(ordinary.firstLineIndent.appliedAdvance, 80);
      expect(ordinary.firstLineIndent.isReduced, isFalse);
      expect(ordinary.firstLineIndent.layoutPasses, 1);
      expect(
        () => ForumBodyParagraphLayout.create(
          content: content('<p style="text-indent:80px">abc</p>', reader()),
          width: 40,
        ),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
      final mixed = mixedInlineInput(
        prefix: '',
        paragraphStyle: 'text-indent:20px',
      ).content;
      expect(
        () => ForumBodyInlineParagraphLayout.create(
          content: mixed,
          width: 40,
          dimensions: dimensions,
        ),
        throwsA(isA<ForumBodyParagraphLayoutException>()),
      );
    },
  );

  test(
    'a preserved first LF is real source coverage rather than a prefix-only row',
    () {
      final layout = ForumBodyParagraphLayout.create(
        content: content('<p style="white-space:pre-wrap">\nabc</p>', reader()),
        width: 25,
      );
      addTearDown(layout.dispose);
      expect(layout.projection.text, '\nabc');
      expect(layout.lines.first.coverageEndUtf16, 1);
      expect(layout.firstLineIndent.layoutPasses, 1);
    },
  );
  test(
    'nonlinear scaling and Unicode clusters retain the original projection',
    () {
      final scaled = ForumBodyParagraphLayout.create(
        content: content('<p>abcdef</p>', reader()),
        width: 45,
        textScaler: const _Scaler(),
      );
      addTearDown(scaled.dispose);
      expect(scaled.firstLineIndent.requestedAdvance, 120);
      expect(scaled.firstLineIndent.appliedAdvance, closeTo(15, .001));
      final mixedSize = ForumBodyParagraphLayout.create(
        content: content(
          '<p><span style="font-size:40px">a</span>bc</p>',
          reader(),
        ),
        width: 60,
        textScaler: const _Scaler(),
      );
      addTearDown(mixedSize.dispose);
      expect(mixedSize.firstLineIndent.requestedAdvance, 120);
      expect(mixedSize.firstLineIndent.appliedAdvance, closeTo(12, .001));
      for (final text in ['\u0301A', 'a\u0301b', '👩‍👩‍👧‍👦b']) {
        final input = content('<p>$text</p>', reader());
        final layout = ForumBodyParagraphLayout.create(
          content: input,
          width: 80,
        );
        addTearDown(layout.dispose);
        expect(layout.projection.text, text);
        expect(
          layout.lines.first.coverageEndUtf16,
          greaterThanOrEqualTo(input.projection.firstGrapheme!.length),
        );
        expect(layout.lines.last.coverageEndUtf16, text.length);
        expect(layout.firstLineIndent.layoutPasses, lessThanOrEqualTo(3));
        expect(
          layout.selectionBoxes(0, input.projection.firstGrapheme!.length),
          isNotEmpty,
        );
      }
    },
  );
  test(
    'word and cluster fitting cannot leave a positive-indent overflowing row',
    () {
      for (final text in ['ab cd', 'AV AV', 'a\u0301b ab']) {
        final layout = ForumBodyParagraphLayout.create(
          content: content('<p>$text</p>', reader()),
          width: 60,
        );
        addTearDown(layout.dispose);
        expect(layout.lines.first.width, lessThanOrEqualTo(60.001));
        expect(layout.lines.first.coverageEndUtf16, greaterThan(0));
        expect(layout.firstLineIndent.layoutPasses, inInclusiveRange(2, 3));
        expect(layout.projection.text, text);
      }
    },
  );
}

final class _Scaler extends TextScaler {
  const _Scaler();
  @override
  double scale(double size) => size <= 20 ? size * 1.5 : size * 1.2;
  @override
  double get textScaleFactor => 1.5;
}
