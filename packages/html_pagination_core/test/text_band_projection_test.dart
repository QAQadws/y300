import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:test/test.dart';

HtmlDisplayTextProjection project(String text, int start) =>
    HtmlDisplayTextProjection.build([
      HtmlDisplayTextRun(
        text: text,
        sourceRuneStart: start,
        whiteSpace: HtmlDisplayWhiteSpace.preWrap,
      ),
    ]);

void main() {
  test(
    'engine spacer has no display/source ownership and children stay independent',
    () {
      final first = project('e', 5);
      final second = project('\u0301👩‍💻אב', 20);
      final band = HtmlTextBandProjection.build([first, second]);
      expect(band.engineText, 'e\n\u200b\n\u0301👩‍💻אב');
      expect(
        band.children.map(
          (child) => (child.engineStartUtf16, child.engineEndUtf16),
        ),
        [(0, 1), (4, 12)],
      );
      expect(band.children[1].display, same(second));
      for (var engine = 1; engine <= 4; engine++) {
        final hit = band.sourceAtChildEngineUtf16(0, engine);
        expect(hit.sourceRune, 6);
        expect(hit.isExact, engine == 1);
      }
      final next = band.sourceAtChildEngineUtf16(1, 1);
      expect(next.sourceRune, 20);
      expect(next.isExact, isFalse);
      expect(band.sourceAtChildEngineUtf16(1, 4).isExact, isTrue);
      expect(() => band.children.clear(), throwsUnsupportedError);
    },
  );

  test('every child hit agrees with original Unicode/source affinity', () {
    final inputs = [
      project('👨‍👩‍👧‍👦e\u0301', 5),
      project('אב\u00a0 X ', 40),
    ];
    final band = HtmlTextBandProjection.build(inputs);
    for (final child in band.children) {
      for (var local = 0; local <= child.display.text.length; local++) {
        for (final affinity in HtmlProjectionAffinity.values) {
          final expected = child.display.sourceAtUtf16(
            local,
            affinity: affinity,
          );
          final actual = band.sourceAtChildEngineUtf16(
            child.index,
            child.engineStartUtf16 + local,
            affinity: affinity,
          );
          expect(
            (actual.sourceRune, actual.displayUtf16, actual.isExact),
            (expected.sourceRune, expected.displayUtf16, expected.isExact),
          );
        }
      }
    }
  });

  test('selection expands complete graphemes without selecting separators', () {
    final band = HtmlTextBandProjection.build([
      project('A', 0),
      project('👩‍💻e\u0301Z', 5),
    ]);
    expect(band.engineRangeForChildSelection(1, startUtf16: 1, endUtf16: 6), (
      startUtf16: 4,
      endUtf16: 11,
    ));
    expect(band.engineRangeForChildSelection(1, startUtf16: 1, endUtf16: 1), (
      startUtf16: 9,
      endUtf16: 9,
    ));
    expect(
      () => band.engineRangeForChildSelection(1, startUtf16: 0, endUtf16: 100),
      throwsRangeError,
    );
    expect(() => band.sourceAtChildEngineUtf16(-1, 0), throwsRangeError);
    expect(() => band.sourceAtChildEngineUtf16(0, -1), throwsRangeError);
    expect(
      () => band.sourceAtChildEngineUtf16(0, band.engineText.length + 1),
      throwsRangeError,
    );
  });

  test(
    'empty windows retain external gap affinity and do not hide reverse order',
    () {
      final original = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: 'A', sourceRuneStart: 5),
        HtmlDisplayTextRun(text: 'B', sourceRuneStart: 50),
      ]);
      final empty = original.slice(startUtf16: 1, endUtf16: 1);
      final band = HtmlTextBandProjection.build([empty]);
      expect(band.sourceAtChildEngineUtf16(0, 0).sourceRune, 50);
      expect(
        band
            .sourceAtChildEngineUtf16(
              0,
              0,
              affinity: HtmlProjectionAffinity.upstream,
            )
            .sourceRune,
        6,
      );
      expect(band.sourceAtChildEngineUtf16(0, 0).isExact, isFalse);
      expect(
        () => HtmlTextBandProjection.build([empty, project('X', 20)]),
        throwsArgumentError,
      );
      expect(HtmlTextBandProjection.build([]).engineText, isEmpty);
    },
  );

  test('child, real text and virtual engine payload have separate budgets', () {
    final children = [project('AB', 0), project('C', 4)];
    expect(
      () => HtmlTextBandProjection.build(children, maxChildren: 1),
      throwsA(isA<HtmlTextBandLimitException>()),
    );
    expect(
      () => HtmlTextBandProjection.build(children, maxDisplayCodeUnits: 2),
      throwsA(isA<HtmlTextBandLimitException>()),
    );
    expect(
      () => HtmlTextBandProjection.build(children, maxEngineCodeUnits: 5),
      throwsA(isA<HtmlTextBandLimitException>()),
    );
    expect(
      HtmlTextBandProjection.build(
        children,
        maxEngineCodeUnits: 6,
      ).engineText.length,
      6,
    );
    expect(
      () => HtmlTextBandProjection.build(children.reversed.toList()),
      throwsArgumentError,
    );
    expect(
      () => HtmlTextBandProjection.build([], maxChildren: -1),
      throwsArgumentError,
    );
    expect(
      () => HtmlTextBandProjection.build([], maxDisplayCodeUnits: -1),
      throwsArgumentError,
    );
    expect(
      () => HtmlTextBandProjection.build([], maxEngineCodeUnits: -1),
      throwsArgumentError,
    );
  });
}
