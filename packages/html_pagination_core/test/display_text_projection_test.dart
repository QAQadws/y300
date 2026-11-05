import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'source intervals project whole glyphs in a restricted display window',
    () {
      final projection = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: 'A\t  🦊e', sourceRuneStart: 3),
        HtmlDisplayTextRun(text: '\u0301', sourceRuneStart: 9),
        HtmlDisplayTextRun(text: 'B', sourceRuneStart: 14),
      ]);
      expect(projection.text, 'A 🦊e\u0301B');
      final windows = projection
          .graphemeRanges(startUtf16: 0, endUtf16: projection.text.length)
          .toList();
      final boundaries = [0, ...windows.map((glyph) => glyph.endUtf16)];
      for (final start in boundaries) {
        for (final end in boundaries.where((offset) => offset >= start)) {
          for (var from = 0; from <= 15; from++) {
            for (var to = from; to <= 15; to++) {
              final actual = projection.displayRangesInSource(
                sourceStart: from,
                sourceEnd: to,
                startUtf16: start,
                endUtf16: end,
              );
              final expected = windows.where((glyph) {
                final source = projection.sourceEnvelope(
                  startUtf16: glyph.startUtf16,
                  endUtf16: glyph.endUtf16,
                )!;
                return glyph.startUtf16 >= start &&
                    glyph.endUtf16 <= end &&
                    source.runeStart >= from &&
                    source.runeEnd <= to;
              });
              expect(
                actual.expand(
                  (span) => projection.graphemeRanges(
                    startUtf16: span.startUtf16,
                    endUtf16: span.endUtf16,
                  ),
                ),
                expected,
              );
            }
          }
        }
      }
    },
  );

  test('source lookup preserves the display order of rearranged contexts', () {
    HtmlDisplayTextSegment segment(String text, int start) =>
        HtmlDisplayTextSegment(
          HtmlDisplayTextProjection.build([
            HtmlDisplayTextRun(text: text, sourceRuneStart: start),
          ]),
        );
    final projection = HtmlDisplayTextProjection.concatenate(
      [segment('後', 3), segment('外', 0), segment('前', 2)],
      sourceOrder: const [1, 2, 0],
    );
    expect(
      projection.displayRangesInSource(
        sourceStart: 2,
        sourceEnd: 4,
        startUtf16: 0,
        endUtf16: 3,
      ),
      [(startUtf16: 0, endUtf16: 1), (startUtf16: 2, endUtf16: 3)],
    );
  });

  for (final mode in HtmlDisplayWhiteSpace.values) {
    test('forced-break suppression preserves source and styles ($mode)', () {
      final runs = [
        HtmlDisplayTextRun(text: 'A', sourceRuneStart: 0, whiteSpace: mode),
        HtmlDisplayTextRun(
          text: '\n',
          sourceRuneStart: 1,
          whiteSpace: mode,
          hardBreak: true,
        ),
        HtmlDisplayTextRun(
          text: '\n',
          sourceRuneStart: 2,
          whiteSpace: mode,
          hardBreak: true,
        ),
        HtmlDisplayTextRun(text: 'B', sourceRuneStart: 3, whiteSpace: mode),
      ];
      final projection = HtmlDisplayTextProjection.build(
        runs,
        suppressLineBreaks: true,
      );
      expect(projection.text, 'A B');
      expect(projection.parts.map((part) => part.runIndex), [0, 1, 3]);
      expect(projection.sourceAtUtf16(1).sourceRune, 1);
      expect(projection.sourceAtUtf16(2).sourceRune, 3);
      expect(projection.sourceAtUtf16(3).sourceRune, 4);
      if (mode != HtmlDisplayWhiteSpace.singleLine) {
        expect(HtmlDisplayTextProjection.build(runs).text, 'A\n\nB');
      }
      expect(
        () => HtmlDisplayTextProjection.build(
          runs,
          suppressLineBreaks: true,
          maxOutputCodeUnits: 2,
        ),
        throwsA(isA<HtmlDisplayTextLimitException>()),
      );
    });
  }

  for (final mode in [
    HtmlDisplayWhiteSpace.pre,
    HtmlDisplayWhiteSpace.preWrap,
  ]) {
    test('break suppression keeps literal preformatted whitespace ($mode)', () {
      final projection = HtmlDisplayTextProjection.build([
        HtmlDisplayTextRun(
          text: ' x  \n  y\t\u00a0\u3000 ',
          sourceRuneStart: 10,
          whiteSpace: mode,
        ),
      ], suppressLineBreaks: true);
      expect(projection.text, ' x     y\t\u00a0\u3000 ');
      expect(projection.sourceAtUtf16(0).sourceRune, 10);
      expect(projection.sourceAtUtf16(projection.text.length).sourceRune, 22);
    });
  }

  test('suppressed CRLF and Unicode breaks retain actual source gaps', () {
    final projection = HtmlDisplayTextProjection.build(const [
      HtmlDisplayTextRun(text: 'a\r', sourceRuneStart: 2),
      HtmlDisplayTextRun(text: '\n\u2028\u2029\u0085', sourceRuneStart: 4),
      HtmlDisplayTextRun(text: 'b', sourceRuneStart: 20),
    ], suppressLineBreaks: true);
    expect(projection.text, 'a b');
    expect(projection.sourceAtUtf16(1).sourceRune, 3);
    final before = projection.sourceAtUtf16(
      2,
      affinity: HtmlProjectionAffinity.upstream,
    );
    final after = projection.sourceAtUtf16(2);
    expect(before.sourceRune, 8);
    expect(after.sourceRune, 20);
    expect(before.isExact, isFalse);
    expect(after.isExact, isFalse);
  });

  test(
    'inline fragments retain collapsed edge spaces with their source spans',
    () {
      const runs = [
        HtmlDisplayTextRun(text: ' \t前 ', sourceRuneStart: 10),
        HtmlDisplayTextRun(text: ' \r', sourceRuneStart: 14),
        HtmlDisplayTextRun(text: '\n', sourceRuneStart: 16),
      ];
      final fragment = HtmlDisplayTextProjection.build(
        runs,
        preserveCollapsibleEdges: true,
      );
      expect(fragment.text, ' 前 ');
      expect(HtmlDisplayTextProjection.build(runs).text, '前');
      expect(fragment.sourceAtUtf16(0).sourceRune, 10);
      expect(fragment.sourceAtUtf16(1).sourceRune, 12);
      expect(fragment.sourceAtUtf16(2).sourceRune, 13);
      expect(fragment.sourceAtUtf16(3).sourceRune, 17);
      expect(fragment.parts.map((part) => part.runIndex), [0]);
    },
  );

  test(
    'whitespace-only fragments preserve one space and the complete collapsed range',
    () {
      final fragment = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: ' \t\r', sourceRuneStart: 20),
        HtmlDisplayTextRun(text: '\n ', sourceRuneStart: 23),
      ], preserveCollapsibleEdges: true);
      expect(fragment.text, ' ');
      expect(fragment.sourceAtUtf16(0).sourceRune, 20);
      expect(fragment.sourceAtUtf16(1).sourceRune, 25);
      expect(fragment.graphemeRanges(startUtf16: 0, endUtf16: 1), hasLength(1));
    },
  );

  test(
    'fragment edges do not preserve collapsible spaces around real line breaks',
    () {
      final fragment = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: '  a  ', sourceRuneStart: 0),
        HtmlDisplayTextRun(text: '\n', sourceRuneStart: 5, hardBreak: true),
        HtmlDisplayTextRun(text: '  b ', sourceRuneStart: 6),
        HtmlDisplayTextRun(
          text: '\n  ',
          sourceRuneStart: 10,
          whiteSpace: HtmlDisplayWhiteSpace.preLine,
        ),
      ], preserveCollapsibleEdges: true);
      expect(fragment.text, ' a\nb\n');
      expect(fragment.sourceAtUtf16(fragment.text.length).sourceRune, 11);
    },
  );

  test(
    'edge preservation keeps preformatted and Unicode noncollapsible spaces literal',
    () {
      for (final mode in [
        HtmlDisplayWhiteSpace.pre,
        HtmlDisplayWhiteSpace.preWrap,
      ]) {
        final fragment = HtmlDisplayTextProjection.build([
          HtmlDisplayTextRun(
            text: ' \t\u00a0\u3000 ',
            sourceRuneStart: 30,
            whiteSpace: mode,
          ),
        ], preserveCollapsibleEdges: true);
        expect(fragment.text, ' \t\u00a0\u3000 ');
      }
      final normal = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: '\u00a0\u3000', sourceRuneStart: 0),
      ], preserveCollapsibleEdges: true);
      expect(normal.text, '\u00a0\u3000');
    },
  );

  test(
    'preserved edges count toward output budgets and keep source gaps explicit',
    () {
      expect(
        () => HtmlDisplayTextProjection.build(
          const [HtmlDisplayTextRun(text: ' a ', sourceRuneStart: 0)],
          maxOutputCodeUnits: 2,
          preserveCollapsibleEdges: true,
        ),
        throwsA(isA<HtmlDisplayTextLimitException>()),
      );
      final fragment = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: ' a', sourceRuneStart: 5),
        HtmlDisplayTextRun(text: ' b ', sourceRuneStart: 50),
      ], preserveCollapsibleEdges: true);
      final before = fragment.sourceAtUtf16(
        2,
        affinity: HtmlProjectionAffinity.upstream,
      );
      final after = fragment.sourceAtUtf16(2);
      expect(before.sourceRune, 7);
      expect(after.sourceRune, 50);
      expect(before.isExact, isFalse);
      expect(after.isExact, isFalse);
    },
  );

  test(
    'single-line projection retains the source span across styled whitespace and BR',
    () {
      final projection = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(
          text: ' \u00a0甲\r',
          sourceRuneStart: 100,
          whiteSpace: HtmlDisplayWhiteSpace.singleLine,
        ),
        HtmlDisplayTextRun(
          text: '\n\t',
          sourceRuneStart: 104,
          whiteSpace: HtmlDisplayWhiteSpace.singleLine,
        ),
        HtmlDisplayTextRun(
          text: '\n',
          sourceRuneStart: 106,
          hardBreak: true,
          whiteSpace: HtmlDisplayWhiteSpace.singleLine,
        ),
        HtmlDisplayTextRun(
          text: '\u0085乙\u00a0',
          sourceRuneStart: 107,
          whiteSpace: HtmlDisplayWhiteSpace.singleLine,
        ),
      ]);
      expect(projection.text, '甲 乙');
      expect(projection.parts.map((part) => (part.runIndex, part.text)), [
        (0, '甲 '),
        (3, '乙'),
      ]);
      expect(projection.sourceAtUtf16(0).sourceRune, 102);
      expect(projection.sourceAtUtf16(1).sourceRune, 103);
      expect(projection.sourceAtUtf16(2).sourceRune, 108);
      expect(projection.sourceAtUtf16(3).sourceRune, 109);
    },
  );

  test(
    'single-line Unicode folding is opt-in and preserves non-whitespace format controls',
    () {
      const spaces = [
        0x09,
        0x0a,
        0x0b,
        0x0c,
        0x0d,
        0x20,
        0x85,
        0xa0,
        0x1680,
        0x2000,
        0x2001,
        0x2002,
        0x2003,
        0x2004,
        0x2005,
        0x2006,
        0x2007,
        0x2008,
        0x2009,
        0x200a,
        0x2028,
        0x2029,
        0x202f,
        0x205f,
        0x3000,
        0xfeff,
      ];
      for (final rune in spaces) {
        final projection = HtmlDisplayTextProjection.build([
          HtmlDisplayTextRun(
            text: 'a${String.fromCharCode(rune)}b',
            sourceRuneStart: 7,
            whiteSpace: HtmlDisplayWhiteSpace.singleLine,
          ),
        ]);
        expect(projection.text, 'a b', reason: 'U+${rune.toRadixString(16)}');
        expect(projection.sourceAtUtf16(2).sourceRune, 9);
      }
      for (final rune in [0x200b, 0x200c, 0x200d, 0x2060]) {
        final text = 'a${String.fromCharCode(rune)}b';
        final projection = HtmlDisplayTextProjection.build([
          HtmlDisplayTextRun(
            text: text,
            sourceRuneStart: 0,
            whiteSpace: HtmlDisplayWhiteSpace.singleLine,
          ),
        ]);
        expect(projection.text, text);
        expect(HtmlDisplayTextProjection.isSingleLineWhitespace(rune), isFalse);
      }
      final ordinary = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: '\u00a0\u3000甲\u00a0', sourceRuneStart: 0),
      ]);
      expect(ordinary.text, '\u00a0\u3000甲\u00a0');
    },
  );

  test(
    'single-line collapse preserves source gaps and whole Unicode graphemes',
    () {
      final projection = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(
          text: '甲\u00a0',
          sourceRuneStart: 10,
          whiteSpace: HtmlDisplayWhiteSpace.singleLine,
        ),
        HtmlDisplayTextRun(
          text: '\n',
          sourceRuneStart: 20,
          hardBreak: true,
          whiteSpace: HtmlDisplayWhiteSpace.singleLine,
        ),
        HtmlDisplayTextRun(
          text: 'e\u0301👩🏽‍💻乙',
          sourceRuneStart: 30,
          whiteSpace: HtmlDisplayWhiteSpace.singleLine,
        ),
      ]);
      expect(projection.text, '甲 e\u0301👩🏽‍💻乙');
      expect(
        projection
            .sourceAtUtf16(2, affinity: HtmlProjectionAffinity.upstream)
            .sourceRune,
        21,
      );
      expect(projection.sourceAtUtf16(2).sourceRune, 30);
      expect(projection.sourceAtUtf16(2).isExact, isFalse);
      expect(projection.sourceAtUtf16(3).displayUtf16, 4);
      expect(projection.sourceAtUtf16(3).isExact, isFalse);
      expect(projection.sourceAtUtf16(5).displayUtf16, 11);
      expect(projection.sourceAtUtf16(11).sourceRune, 36);
    },
  );

  test(
    'single-line empty and limited output cannot fabricate a source position',
    () {
      final empty = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(
          text: '\u00a0\n\t',
          sourceRuneStart: 42,
          whiteSpace: HtmlDisplayWhiteSpace.singleLine,
        ),
      ], maxOutputCodeUnits: 0);
      expect(empty.text, isEmpty);
      expect(empty.sourceAtUtf16(0).sourceRune, 42);
      expect(
        () => HtmlDisplayTextProjection.build(const [
          HtmlDisplayTextRun(
            text: ' 甲\u00a0乙 ',
            sourceRuneStart: 0,
            whiteSpace: HtmlDisplayWhiteSpace.singleLine,
          ),
        ], maxOutputCodeUnits: 2),
        throwsA(isA<HtmlDisplayTextLimitException>()),
      );
    },
  );

  test(
    'line windows enumerate only their actual complete display graphemes',
    () {
      final projection = HtmlDisplayTextProjection.build([
        const HtmlDisplayTextRun(
          text: '甲e\u0301🙂乙\n丙',
          sourceRuneStart: 20,
          whiteSpace: HtmlDisplayWhiteSpace.preWrap,
        ),
      ]);
      expect(projection.graphemeRanges(startUtf16: 1, endUtf16: 6).toList(), [
        (startUtf16: 1, endUtf16: 3),
        (startUtf16: 3, endUtf16: 5),
        (startUtf16: 5, endUtf16: 6),
      ]);
      expect(projection.graphemeRanges(startUtf16: 6, endUtf16: 7).single, (
        startUtf16: 6,
        endUtf16: 7,
      ));
      expect(projection.graphemeRanges(startUtf16: 8, endUtf16: 8), isEmpty);
      for (final range in [(2, 6), (1, 4), (4, 4)]) {
        expect(
          () => projection
              .graphemeRanges(startUtf16: range.$1, endUtf16: range.$2)
              .toList(),
          throwsArgumentError,
        );
      }
      expect(
        () => projection.graphemeRanges(startUtf16: -1, endUtf16: 0).toList(),
        throwsRangeError,
      );
      expect(
        () => projection.graphemeRanges(startUtf16: 0, endUtf16: 9).toList(),
        throwsRangeError,
      );
    },
  );

  test('display grapheme windows do not fill missing source or empty text', () {
    final projection = HtmlDisplayTextProjection.build([
      const HtmlDisplayTextRun(text: 'a', sourceRuneStart: 0),
      const HtmlDisplayTextRun(text: 'b', sourceRuneStart: 7),
    ]);
    expect(projection.graphemeRanges(startUtf16: 0, endUtf16: 2).length, 2);
    expect(projection.sourceAtUtf16(1).isExact, isFalse);
    expect(projection.sourceAtUtf16(1).sourceRune, 7);
    final empty = HtmlDisplayTextProjection.build(const []);
    expect(empty.graphemeRanges(startUtf16: 0, endUtf16: 0), isEmpty);
  });

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
