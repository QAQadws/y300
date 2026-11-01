import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

ForumBodyInlineSpanContent _content() {
  final document = const ForumBodyParser().parse(
    html: '<p><span>A</span><span>xx</span><span>B</span><span>yy</span></p>',
    sourceId: 'fractional-fragment-frame',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
      fontRevision: 'fractional-frame',
      linkColor: const Color(0xff0000ff),
    ),
  );
  return ForumBodyInlineSpanContent.compose(
    identity: document.identity,
    path: '0',
    fontRevision: styles.fontRevision,
    styleRevision: styles.resolverRevision,
    style: styles.byPath['0']!,
    contexts: [
      for (var i = 0; i < 4; i++)
        const ForumBodyParagraphContentBuilder().build(
          document: document,
          styles: styles,
          path: '0/$i',
          layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
        ),
    ],
    atomicRanges: [(startUtf16: 0, endUtf16: 3), (startUtf16: 3, endUtf16: 6)],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final height in [46.875, 35.15625, 30.125, 38.5]) {
    test(
      'a wrapped fragment contains actual fractional slot height $height',
      () {
        final dimensions = [
          PlaceholderDimensions(
            size: Size(30, height),
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            baselineOffset: height * .8,
          ),
          const PlaceholderDimensions(
            size: Size(20, 35.15625),
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            baselineOffset: 28.125,
          ),
        ];
        final layout = ForumBodyInlineParagraphLayout.create(
          content: _content(),
          width: 30,
          dimensions: dimensions,
        );
        try {
          expect(layout.lines, hasLength(2));
          for (var row = 0; row < 2; row++) {
            final fragment = layout.fragment(row, row + 1);
            final slot = layout.atomBoxes[row].toRect();
            expect(fragment.top, lessThanOrEqualTo(slot.top));
            expect(
              fragment.bottom,
              greaterThanOrEqualTo(slot.top + dimensions[row].size.height),
            );
            final hit = fragment.hitAt(
              Offset(slot.left + .1, slot.top - fragment.top + .01),
            );
            expect(hit, isA<ForumBodyInlineAtomHit>());
            expect((hit as ForumBodyInlineAtomHit).index, row);
          }
          final complete = layout.fragment(0, 2);
          expect(complete.top, 0);
          expect(complete.height, layout.height);
        } finally {
          layout.dispose();
        }
      },
    );
  }
}
