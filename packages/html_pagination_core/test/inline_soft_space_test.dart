import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:test/test.dart';

HtmlDisplayTextProjection _display(String text) =>
    HtmlDisplayTextProjection.build([
      HtmlDisplayTextRun(text: text, sourceRuneStart: 10),
    ], preserveCollapsibleEdges: true);

void main() {
  test(
    'soft glue keeps real source windows and distinct engine/map identity',
    () {
      final display = _display('á  🦊');
      final ranges = [
        (startUtf16: 0, endUtf16: 2),
        (startUtf16: 2, endUtf16: 3),
        (startUtf16: 3, endUtf16: 5),
      ];
      final soft = HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: ranges,
        softSpaceAtoms: {1},
      );
      final opaque = HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: ranges,
      );
      expect(soft.engineText, '\ufffc \ufffc');
      expect(opaque.engineText, '\ufffc\ufffc\ufffc');
      expect(soft.atoms.map((a) => a.isSoftSpace), [false, true, false]);
      expect(soft.hasSameMapping(opaque), isFalse);
      expect(soft.sourceAtEngineUtf16(1).sourceRune, 12);
      expect(soft.sourceAtEngineUtf16(2).sourceRune, 14);
      expect(soft.displayRangeForEngineRange(startUtf16: 0, endUtf16: 2), (
        startUtf16: 0,
        endUtf16: 3,
      ));
      expect(soft.engineAtDisplayUtf16(4).isExact, isFalse);
    },
  );
  for (final index in [-1, 0, 2, 3]) {
    test('soft glue rejects an edge or missing atom $index', () {
      expect(
        () => HtmlInlineTextProjection.build(
          display: _display('A B'),
          atomicRanges: [
            (startUtf16: 0, endUtf16: 1),
            (startUtf16: 1, endUtf16: 2),
            (startUtf16: 2, endUtf16: 3),
          ],
          softSpaceAtoms: {index},
        ),
        throwsArgumentError,
      );
    });
  }
  for (final gap in ['x', '\u00a0', '\u3000', '\n']) {
    test('soft glue never reclassifies noncollapsible text ($gap)', () {
      final display = HtmlDisplayTextProjection.build([
        HtmlDisplayTextRun(
          text: 'A${gap}B',
          sourceRuneStart: 0,
          whiteSpace: HtmlDisplayWhiteSpace.pre,
        ),
      ]);
      expect(
        () => HtmlInlineTextProjection.build(
          display: display,
          atomicRanges: [
            (startUtf16: 0, endUtf16: 1),
            (startUtf16: 1, endUtf16: 2),
            (startUtf16: 2, endUtf16: 3),
          ],
          softSpaceAtoms: {1},
        ),
        throwsArgumentError,
      );
    });
  }
  test(
    'soft glue cannot hide ordinary text or attach to another glue atom',
    () {
      expect(
        () => HtmlInlineTextProjection.build(
          display: _display('A B C'),
          atomicRanges: [
            (startUtf16: 0, endUtf16: 1),
            (startUtf16: 1, endUtf16: 2),
            (startUtf16: 4, endUtf16: 5),
          ],
          softSpaceAtoms: {1},
        ),
        throwsArgumentError,
      );
      expect(
        () => HtmlInlineTextProjection.build(
          display: _display('A \tB'),
          atomicRanges: [
            (startUtf16: 0, endUtf16: 1),
            (startUtf16: 1, endUtf16: 2),
            (startUtf16: 2, endUtf16: 3),
            (startUtf16: 3, endUtf16: 4),
          ],
          softSpaceAtoms: {1, 2},
        ),
        throwsArgumentError,
      );
    },
  );
}
