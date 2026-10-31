import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'source mapping equality ignores run partition but preserves coordinates',
    () {
      final whole = HtmlDisplayTextProjection.build([
        const HtmlDisplayTextRun(text: 'é👩🏽‍💻a', sourceRuneStart: 8),
      ]);
      final split = HtmlDisplayTextProjection.build([
        const HtmlDisplayTextRun(text: 'e', sourceRuneStart: 8),
        const HtmlDisplayTextRun(text: '́👩🏽‍💻a', sourceRuneStart: 9),
      ]);
      expect(whole.sourceMappingHash, split.sourceMappingHash);
      expect(whole.hasSameSourceMapping(split), isTrue);
      expect(whole.hasSameSourceMapping(whole), isTrue);
      final shifted = HtmlDisplayTextProjection.build([
        const HtmlDisplayTextRun(text: 'é👩🏽‍💻a', sourceRuneStart: 9),
      ]);
      expect(whole.text, shifted.text);
      expect(whole.hasSameSourceMapping(shifted), isFalse);
      for (var offset = 0; offset <= whole.text.length; offset++) {
        for (final affinity in HtmlProjectionAffinity.values) {
          final a = whole.sourceAtUtf16(offset, affinity: affinity);
          final b = split.sourceAtUtf16(offset, affinity: affinity);
          expect(
            (a.sourceRune, a.displayUtf16, a.isExact),
            (b.sourceRune, b.displayUtf16, b.isExact),
          );
        }
      }
    },
  );

  test(
    'source mapping equality retains collapsed ranges, gaps and empty bases',
    () {
      HtmlDisplayTextProjection projection(List<HtmlDisplayTextRun> runs) =>
          HtmlDisplayTextProjection.build(runs);
      final contiguous = projection([
        const HtmlDisplayTextRun(text: 'ab', sourceRuneStart: 0),
      ]);
      final gap = projection([
        const HtmlDisplayTextRun(text: 'a', sourceRuneStart: 0),
        const HtmlDisplayTextRun(text: 'b', sourceRuneStart: 5),
      ]);
      expect(contiguous.text, gap.text);
      expect(contiguous.hasSameSourceMapping(gap), isFalse);
      final oneSpace = projection([
        const HtmlDisplayTextRun(text: 'a b', sourceRuneStart: 0),
      ]);
      final twoSpaces = projection([
        const HtmlDisplayTextRun(text: 'a  b', sourceRuneStart: 0),
      ]);
      expect(oneSpace.text, twoSpaces.text);
      expect(oneSpace.hasSameSourceMapping(twoSpaces), isFalse);
      final empty = projection([]);
      final basedEmpty = projection([
        const HtmlDisplayTextRun(text: '', sourceRuneStart: 5),
      ]);
      expect(empty.text, basedEmpty.text);
      expect(empty.hasSameSourceMapping(basedEmpty), isFalse);
      expect(
        basedEmpty.hasSameSourceMapping(
          projection([const HtmlDisplayTextRun(text: '', sourceRuneStart: 5)]),
        ),
        isTrue,
      );
    },
  );

  test(
    'normal collapses across runs while retaining the first style owner',
    () {
      final projection = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: '  甲 ', sourceRuneStart: 0),
        HtmlDisplayTextRun(text: ' \t乙 \n', sourceRuneStart: 4),
      ]);
      expect(projection.text, '甲 乙');
      expect(projection.parts.map((part) => part.text), ['甲 ', '乙']);
      expect(projection.parts.map((part) => part.runIndex), [0, 1]);
      expect(projection.sourceAtUtf16(0).sourceRune, 2);
      expect(projection.sourceAtUtf16(1).sourceRune, 3);
      expect(projection.sourceAtUtf16(2).sourceRune, 6);
      expect(projection.sourceAtUtf16(3).sourceRune, 7);
    },
  );

  test(
    'preformatted spaces survive and pre-line/BR retain explicit breaks',
    () {
      for (final mode in [
        HtmlDisplayWhiteSpace.pre,
        HtmlDisplayWhiteSpace.preWrap,
      ]) {
        final projection = HtmlDisplayTextProjection.build([
          HtmlDisplayTextRun(
            text: ' \t甲\n  ',
            sourceRuneStart: 0,
            whiteSpace: mode,
          ),
        ]);
        expect(projection.text, ' \t甲\n  ');
      }
      final projection = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(
          text: ' 甲  \n 乙 ',
          sourceRuneStart: 0,
          whiteSpace: HtmlDisplayWhiteSpace.preLine,
        ),
        HtmlDisplayTextRun(text: '\n', sourceRuneStart: 8, hardBreak: true),
        HtmlDisplayTextRun(text: ' 丙 ', sourceRuneStart: 9),
      ]);
      expect(projection.text, '甲\n乙\n丙');
      expect(projection.sourceAtUtf16(3).sourceRune, 8);
    },
  );

  test('NBSP and full-width spaces are not generic trim targets', () {
    final projection = HtmlDisplayTextProjection.build(const [
      HtmlDisplayTextRun(text: ' \u00a0\u3000甲\u3000 ', sourceRuneStart: 0),
    ]);
    expect(projection.text, '\u00a0\u3000甲\u3000');
  });

  test('normal spaces bordering a preserved newline are still collapsible', () {
    final projection = HtmlDisplayTextProjection.build(const [
      HtmlDisplayTextRun(text: '甲 ', sourceRuneStart: 0),
      HtmlDisplayTextRun(
        text: '\n ',
        sourceRuneStart: 2,
        whiteSpace: HtmlDisplayWhiteSpace.preWrap,
      ),
      HtmlDisplayTextRun(text: '乙 ', sourceRuneStart: 4),
    ]);
    expect(projection.text, '甲\n 乙');
  });

  test(
    'CRLF may straddle styled runs without duplicating source or line breaks',
    () {
      final projection = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(
          text: '甲\r',
          sourceRuneStart: 0,
          whiteSpace: HtmlDisplayWhiteSpace.preWrap,
        ),
        HtmlDisplayTextRun(
          text: '\n乙',
          sourceRuneStart: 2,
          whiteSpace: HtmlDisplayWhiteSpace.preWrap,
        ),
      ]);
      expect(projection.text, '甲\n乙');
      expect(projection.sourceAtUtf16(2).sourceRune, 3);
    },
  );

  test(
    'hit coordinates snap whole emoji and cross-style combining clusters',
    () {
      final projection = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: '👨‍👩‍👧‍👦e', sourceRuneStart: 10),
        HtmlDisplayTextRun(text: '\u0301א', sourceRuneStart: 18),
      ]);
      final up = projection.sourceAtUtf16(
        1,
        affinity: HtmlProjectionAffinity.upstream,
      );
      final down = projection.sourceAtUtf16(1);
      expect(up.displayUtf16, 0);
      expect(up.sourceRune, 10);
      expect(down.displayUtf16, 11);
      expect(down.sourceRune, 17);
      expect(down.isExact, isFalse);
      expect(projection.sourceAtUtf16(12).displayUtf16, 13);
      expect(projection.sourceAtUtf16(12).sourceRune, 19);
      expect(projection.sourceAtUtf16(13).isExact, isTrue);
    },
  );

  test(
    'hidden source gaps preserve affinity and never claim an exact boundary',
    () {
      final projection = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: '甲', sourceRuneStart: 0),
        HtmlDisplayTextRun(text: '乙', sourceRuneStart: 10),
      ]);
      expect(projection.sourceAtUtf16(1).sourceRune, 10);
      expect(
        projection
            .sourceAtUtf16(1, affinity: HtmlProjectionAffinity.upstream)
            .sourceRune,
        1,
      );
      expect(projection.sourceAtUtf16(1).isExact, isFalse);
      expect(() => projection.parts.clear(), throwsUnsupportedError);
      expect(() => projection.sourceAtUtf16(3), throwsRangeError);
    },
  );

  test('admission is explicit and source order cannot silently overlap', () {
    expect(
      () => HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: '12345', sourceRuneStart: 0),
      ], maxOutputCodeUnits: 4),
      throwsA(isA<HtmlDisplayTextLimitException>()),
    );
    expect(
      () => HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: 'ab', sourceRuneStart: 1),
        HtmlDisplayTextRun(text: 'c', sourceRuneStart: 2),
      ]),
      throwsArgumentError,
    );
    expect(
      () => HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: 'x', sourceRuneStart: 0, hardBreak: true),
      ]),
      throwsArgumentError,
    );
    expect(
      HtmlDisplayTextProjection.build(const []).sourceAtUtf16(0).sourceRune,
      0,
    );
  });
}
