import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

import 'test_support/mixed_inline_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'long fractional slot remains measurable with explicit row isolation',
    () {
      final content = mixedInlineInput(
        prefix: 'A\n' * 300,
        paragraphStyle: 'white-space:pre-wrap;line-height:.4',
      ).content;
      final cache = ForumBodyParagraphCache(
        maxEntries: 4,
        maxEstimatedBytes: 1 << 26,
      );
      addTearDown(cache.close);
      final dimensions = [
        const PlaceholderDimensions(
          size: Size(31.3, 40.7),
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          baselineOffset: 29.2,
        ),
      ];
      final natural = cache.acquireInline(
        content: content,
        width: 140,
        dimensions: dimensions,
      );
      addTearDown(natural.release);
      final raw =
          TextPainter(
              text: content.textSpan,
              textDirection: TextDirection.ltr,
              strutStyle: StrutStyle.fromTextStyle(
                content.style.textStyle,
                height: 256 / 20,
                leading: 0,
                forceStrutHeight: true,
              ),
            )
            ..setPlaceholderDimensions(dimensions)
            ..layout(minWidth: 140, maxWidth: 140);
      final box = raw.inlinePlaceholderBoxes!.single,
          row = raw.computeLineMetrics().last;
      raw.dispose();
      expect(
        (box.toRect().height - dimensions.single.size.height).abs(),
        greaterThan(1e-3),
      );
      final isolated = cache.acquireInline(
        content: content,
        width: 140,
        dimensions: dimensions,
        rowIsolationPitch: 256,
      );
      addTearDown(isolated.release);
      expect(isolated.layout.lineCount, natural.layout.lineCount);
      expect(isolated.layout.rowIsolationPitch, 256);
      expect(isolated.layout.atomBoxes.single, box);
      expect(isolated.layout.dimensions.single.size, dimensions.single.size);
      expect(isolated.layout.nativeFontClearance, greaterThanOrEqualTo(40.7));
      expect(isolated.layout.lines.last.baseline, row.baseline);
      final reference = ForumBodyInlineRowReferencePreparation(
        natural: natural,
        isolated: isolated,
        ensureOwner: () {},
      );
      try {
        while (!reference.isReady) {
          reference.advance(maxParts: 1);
        }
        final value = reference.takeReference();
        expect(value.atomLineIndices, [300]);
        expect(value.isolatedAtomBoxes.single, box);
      } finally {
        reference.close();
      }
    },
  );
}
