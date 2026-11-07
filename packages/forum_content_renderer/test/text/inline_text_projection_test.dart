import 'package:forum_content_renderer/forum_text.dart';
import 'package:flutter_test/flutter_test.dart';

HtmlDisplayTextProjection project(String text, [int source = 0]) =>
    HtmlDisplayTextProjection.build([
      HtmlDisplayTextRun(
        text: text,
        sourceRuneStart: source,
        whiteSpace: HtmlDisplayWhiteSpace.preWrap,
      ),
    ]);

void main() {
  test(
    'atom range lookup preserves interior offsets and coincident fences',
    () {
      final map = HtmlInlineTextProjection.build(
        display: project('ABCDEFGH'),
        atomicRanges: [
          (startUtf16: 0, endUtf16: 2),
          (startUtf16: 2, endUtf16: 2),
          (startUtf16: 2, endUtf16: 2),
          (startUtf16: 2, endUtf16: 4),
          (startUtf16: 6, endUtf16: 6),
          (startUtf16: 6, endUtf16: 6),
          (startUtf16: 7, endUtf16: 8),
        ],
        resourceAtoms: {1, 2, 4, 5},
      );
      expect(List.generate(9, map.firstAtomEndingAfterDisplayUtf16), [
        0,
        0,
        3,
        3,
        4,
        4,
        6,
        6,
        7,
      ]);
    },
  );

  test(
    'multi-unit mechanical prefix stays indivisible and is included in mapping identity',
    () {
      final display = project('AB', 50);
      final map = HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: [(startUtf16: 0, endUtf16: 1)],
        enginePrefix: '\u00A0\u2060',
      );
      expect(map.engineText, '\u00A0\u2060\uFFFCB');
      expect(map.atoms.single.engineUtf16, 2);
      for (final offset in [0, 1]) {
        expect(map.displayAtEngineUtf16(offset).displayUtf16, 0);
        expect(map.sourceAtEngineUtf16(offset).isExact, isFalse);
      }
      expect(map.isLegalEngineBoundary(0), isTrue);
      expect(map.isLegalEngineBoundary(1), isFalse);
      expect(map.isLegalEngineBoundary(2), isTrue);
      expect(map.sourceAtEngineUtf16(2).sourceRune, 50);
      expect(map.sourceAtEngineUtf16(2).isExact, isTrue);
      expect(map.displayRangeForEngineRange(startUtf16: 0, endUtf16: 2), (
        startUtf16: 0,
        endUtf16: 0,
      ));
      expect(
        () => map.displayRangeForEngineRange(startUtf16: 1, endUtf16: 4),
        throwsArgumentError,
      );
      final other = HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: [(startUtf16: 0, endUtf16: 1)],
        enginePrefix: '\uFFFD\u2060',
      );
      expect(map.hasSameMapping(other), isFalse);
      expect(
        () => HtmlInlineTextProjection.build(
          display: display,
          atomicRanges: const [],
          enginePrefix: '\u00A0\u2060',
          maxEngineCodeUnits: 3,
        ),
        throwsA(isA<HtmlInlineTextLimitException>()),
      );
    },
  );

  test(
    'mechanical leading placeholder has engine bounds but no source caret',
    () {
      final display = project('A👩‍💻e\u0301Z', 10);
      final map = HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: const [],
        enginePrefix: '\uFFFC',
      );
      expect(map.display, same(display));
      expect(map.engineText, '\uFFFC${display.text}');
      expect(map.atoms, isEmpty);
      expect(map.enginePrefix, '\uFFFC');
      expect(map.engineAtDisplayUtf16(0).engineUtf16, 1);
      expect(map.displayAtEngineUtf16(0).displayUtf16, 0);
      expect(map.displayAtEngineUtf16(0).isExact, isFalse);
      expect(map.sourceAtEngineUtf16(0).sourceRune, 10);
      expect(map.sourceAtEngineUtf16(0).isExact, isFalse);
      expect(map.sourceAtEngineUtf16(1).sourceRune, 10);
      expect(map.sourceAtEngineUtf16(1).isExact, isTrue);
      final legal = {0, 1, 2, 7, 9, 10};
      for (var offset = 0; offset <= map.engineText.length; offset++) {
        expect(
          map.isLegalEngineBoundary(offset),
          legal.contains(offset),
          reason: 'engine $offset',
        );
      }
      expect(map.displayOffsetAtEngineUtf16(3), 2);
      expect(
        () => map.displayRangeForEngineRange(startUtf16: 0, endUtf16: 3),
        throwsArgumentError,
      );
      expect(map.displayRangeForEngineRange(startUtf16: 0, endUtf16: 1), (
        startUtf16: 0,
        endUtf16: 0,
      ));
      expect(map.displayRangeForEngineRange(startUtf16: 0, endUtf16: 10), (
        startUtf16: 0,
        endUtf16: 9,
      ));
      expect(() => map.isLegalEngineBoundary(-1), throwsRangeError);
      expect(() => map.isLegalEngineBoundary(11), throwsRangeError);
    },
  );

  test(
    'leading placeholder shifts real opaque and soft atoms without becoming a child',
    () {
      final map = HtmlInlineTextProjection.build(
        display: project('AB CD', 50),
        enginePrefix: '\uFFFC',
        atomicRanges: [
          (startUtf16: 0, endUtf16: 2),
          (startUtf16: 2, endUtf16: 3),
          (startUtf16: 3, endUtf16: 5),
        ],
        softSpaceAtoms: {1},
      );
      expect(map.engineText, '\uFFFC\uFFFC \uFFFC');
      expect(map.atoms.map((atom) => atom.index), [0, 1, 2]);
      expect(map.atoms.map((atom) => atom.engineUtf16), [1, 2, 3]);
      expect(map.hasSoftSpaces, isTrue);
      expect(map.sourceAtEngineUtf16(0).isExact, isFalse);
      expect(map.sourceAtEngineUtf16(1).sourceRune, 50);
      expect(map.sourceAtEngineUtf16(1).isExact, isTrue);
      expect(map.sourceAtEngineUtf16(3).sourceRune, 53);
      expect(map.displayRangeForEngineRange(startUtf16: 0, endUtf16: 4), (
        startUtf16: 0,
        endUtf16: 5,
      ));
    },
  );

  test('source UFFFC remains distinct from a mechanical prefix', () {
    final map = HtmlInlineTextProjection.build(
      display: project('\uFFFCX', 30),
      atomicRanges: const [],
      enginePrefix: '\uFFFC',
    );
    expect(map.engineText, '\uFFFC\uFFFCX');
    expect(map.sourceAtEngineUtf16(0).isExact, isFalse);
    expect(map.sourceAtEngineUtf16(1).sourceRune, 30);
    expect(map.sourceAtEngineUtf16(1).isExact, isTrue);
    expect(map.sourceAtEngineUtf16(2).sourceRune, 31);
    expect(map.sourceAtEngineUtf16(2).isExact, isTrue);
  });

  test('mapping identity includes the mechanical prefix', () {
    final display = project('AB');
    final plain = HtmlInlineTextProjection.build(
      display: display,
      atomicRanges: const [],
    );
    final prefixed = HtmlInlineTextProjection.build(
      display: display,
      atomicRanges: const [],
      enginePrefix: '\uFFFC',
    );
    final equal = HtmlInlineTextProjection.build(
      display: project('AB'),
      atomicRanges: const [],
      enginePrefix: '\uFFFC',
    );
    expect(plain.hasSameMapping(prefixed), isFalse);
    expect(prefixed.hasSameMapping(plain), isFalse);
    expect(prefixed.hasSameMapping(equal), isTrue);
    expect(prefixed.mappingHash, equal.mappingHash);
  });

  test('mechanical prefix consumes engine budget only', () {
    final display = project('AB');
    expect(
      () => HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: const [],
        enginePrefix: '\uFFFC',
        maxAtoms: 0,
        maxDisplayCodeUnits: 2,
        maxEngineCodeUnits: 2,
      ),
      throwsA(isA<HtmlInlineTextLimitException>()),
    );
    final map = HtmlInlineTextProjection.build(
      display: display,
      atomicRanges: const [],
      enginePrefix: '\uFFFC',
      maxAtoms: 0,
      maxDisplayCodeUnits: 2,
      maxEngineCodeUnits: 3,
    );
    expect(map.engineText.length, 3);
    expect(map.display.text.length, 2);
  });

  test('mechanical-only input cannot manufacture exact source zero', () {
    final map = HtmlInlineTextProjection.build(
      display: HtmlDisplayTextProjection.build(const []),
      atomicRanges: const [],
      enginePrefix: '\uFFFC',
    );
    expect(map.engineText, '\uFFFC');
    expect(map.isLegalEngineBoundary(0), isTrue);
    expect(map.isLegalEngineBoundary(1), isTrue);
    expect(map.sourceAtEngineUtf16(0).isExact, isFalse);
    expect(map.sourceAtEngineUtf16(1).isExact, isFalse);
    expect(map.displayRangeForEngineRange(startUtf16: 0, endUtf16: 1), (
      startUtf16: 0,
      endUtf16: 0,
    ));
  });

  test(
    'leading placeholder does not relax real atom or soft adjacency admission',
    () {
      expect(
        () => HtmlInlineTextProjection.build(
          display: project('AB'),
          atomicRanges: [(startUtf16: 0, endUtf16: 0)],
          enginePrefix: '\uFFFC',
        ),
        throwsArgumentError,
      );
      expect(
        () => HtmlInlineTextProjection.build(
          display: project(' CD'),
          atomicRanges: [
            (startUtf16: 0, endUtf16: 1),
            (startUtf16: 1, endUtf16: 3),
          ],
          softSpaceAtoms: {0},
          enginePrefix: '\uFFFC',
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'prefix preserves explicit reordered source and both boundary affinities',
    () {
      final display = HtmlDisplayTextProjection.concatenate(
        [
          HtmlDisplayTextSegment(project('B', 20)),
          HtmlDisplayTextSegment(project('A', 10)),
        ],
        sourceOrder: [1, 0],
      );
      final map = HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: [(startUtf16: 0, endUtf16: 1)],
        enginePrefix: '\uFFFC',
      );
      for (final affinity in HtmlProjectionAffinity.values) {
        for (var offset = 0; offset <= display.text.length; offset++) {
          final original = display.sourceAtUtf16(offset, affinity: affinity);
          final actual = map.sourceAtEngineUtf16(
            offset + 1,
            affinity: affinity,
          );
          expect(actual.sourceRune, original.sourceRune);
          expect(actual.isExact, original.isExact);
          expect(actual.displayUtf16, original.displayUtf16);
        }
      }
    },
  );

  test(
    'raw physical-row offsets keep code units without legalizing grapheme cuts',
    () {
      final map = HtmlInlineTextProjection.build(
        display: project('AB👩‍💻e\u0301Z'),
        atomicRanges: [(startUtf16: 0, endUtf16: 2)],
      );
      expect(map.engineText, '\uFFFC👩‍💻e\u0301Z');
      expect(map.displayOffsetAtEngineUtf16(1), 2);
      expect(map.displayOffsetAtEngineUtf16(2), 3);
      expect(map.displayAtEngineUtf16(2).displayUtf16, 7);
      expect(map.displayAtEngineUtf16(2).isExact, isFalse);
      expect(
        () => map.displayRangeForEngineRange(startUtf16: 0, endUtf16: 2),
        throwsArgumentError,
      );
      expect(
        map.displayOffsetAtEngineUtf16(map.engineText.length),
        map.display.text.length,
      );
      expect(() => map.displayOffsetAtEngineUtf16(-1), throwsRangeError);
      expect(
        () => map.displayOffsetAtEngineUtf16(map.engineText.length + 1),
        throwsRangeError,
      );
    },
  );

  test('ordinary Unicode text retains every affinity without placeholders', () {
    final display = project('e\u0301👩‍💻אב\nZ', 10);
    final map = HtmlInlineTextProjection.build(
      display: display,
      atomicRanges: [],
    );
    expect(map.engineText, display.text);
    expect(map.atoms, isEmpty);
    for (var offset = 0; offset <= display.text.length; offset++) {
      for (final affinity in HtmlProjectionAffinity.values) {
        final expected = display.sourceAtUtf16(offset, affinity: affinity);
        final position = map.displayAtEngineUtf16(offset, affinity: affinity);
        final source = map.sourceAtEngineUtf16(offset, affinity: affinity);
        expect(position.engineUtf16, expected.displayUtf16);
        expect(position.displayUtf16, expected.displayUtf16);
        expect(position.isExact, expected.displayUtf16 == offset);
        expect(
          (source.sourceRune, source.displayUtf16, source.isExact),
          (expected.sourceRune, expected.displayUtf16, expected.isExact),
        );
      }
    }
  });

  test(
    'atoms replace engine text only and retain actual child source gaps',
    () {
      final display = HtmlDisplayTextProjection.concatenate([
        HtmlDisplayTextSegment(project('前', 0)),
        HtmlDisplayTextSegment(project('漢字', 1), runIndexOffset: 1),
        HtmlDisplayTextSegment(project('かんじ', 20), runIndexOffset: 2),
        HtmlDisplayTextSegment(project('後👩‍💻e\u0301', 30), runIndexOffset: 3),
      ]);
      final map = HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: [(startUtf16: 1, endUtf16: 6)],
      );
      expect(map.engineText, '前\uFFFC後👩‍💻e\u0301');
      expect(identical(map.display, display), isTrue);
      expect(display.text, '前漢字かんじ後👩‍💻e\u0301');
      final atom = map.atoms.single;
      expect(
        (
          atom.index,
          atom.displayStartUtf16,
          atom.displayEndUtf16,
          atom.engineUtf16,
          atom.engineEndUtf16,
        ),
        (0, 1, 6, 1, 2),
      );
      final before = map.engineAtDisplayUtf16(
        3,
        affinity: HtmlProjectionAffinity.upstream,
      );
      final after = map.engineAtDisplayUtf16(3);
      expect(
        (before.engineUtf16, before.displayUtf16, before.isExact),
        (1, 1, false),
      );
      expect(
        (after.engineUtf16, after.displayUtf16, after.isExact),
        (2, 6, false),
      );
      final gapBefore = map.sourceAtEngineUtf16(
        2,
        affinity: HtmlProjectionAffinity.upstream,
      );
      final gapAfter = map.sourceAtEngineUtf16(2);
      expect((gapBefore.sourceRune, gapBefore.isExact), (23, false));
      expect((gapAfter.sourceRune, gapAfter.isExact), (30, false));
      expect(map.displayAtEngineUtf16(2).isExact, isTrue);
      expect(display.sourceAtUtf16(3).sourceRune, 20);
      expect(() => map.atoms.clear(), throwsUnsupportedError);
    },
  );

  test('adjacent and separated atoms retain distinct ordered engine slots', () {
    final ranges = [
      (startUtf16: 1, endUtf16: 3),
      (startUtf16: 3, endUtf16: 5),
      (startUtf16: 6, endUtf16: 8),
    ];
    final map = HtmlInlineTextProjection.build(
      display: project('A漢字かなBאבC'),
      atomicRanges: ranges,
    );
    expect(map.engineText, 'A\uFFFC\uFFFCB\uFFFCC');
    expect(map.atoms.map((atom) => atom.engineUtf16), [1, 2, 4]);
    expect(map.displayRangeForEngineRange(startUtf16: 1, endUtf16: 3), (
      startUtf16: 1,
      endUtf16: 5,
    ));
    ranges.clear();
    expect(map.atoms, hasLength(3));
    for (var engine = 0; engine <= map.engineText.length; engine++) {
      final position = map.displayAtEngineUtf16(engine);
      final roundTrip = map.engineAtDisplayUtf16(position.displayUtf16);
      expect(position.isExact, isTrue);
      expect((roundTrip.engineUtf16, roundTrip.isExact), (engine, true));
    }
  });

  test(
    'ordinary literal object-replacement characters remain real source text',
    () {
      final map = HtmlInlineTextProjection.build(
        display: project('\uFFFC漢字\uFFFC', 10),
        atomicRanges: [(startUtf16: 1, endUtf16: 3)],
      );
      expect(map.engineText, '\uFFFC\uFFFC\uFFFC');
      expect(map.atoms.single.engineUtf16, 1);
      expect(map.sourceAtEngineUtf16(1).sourceRune, 11);
      expect(map.sourceAtEngineUtf16(2).sourceRune, 13);
      expect(map.sourceAtEngineUtf16(3).sourceRune, 14);
    },
  );

  test('line windows cannot cut ordinary graphemes or atomic children', () {
    final map = HtmlInlineTextProjection.build(
      display: project('e\u0301漢字👩‍💻Z'),
      atomicRanges: [(startUtf16: 2, endUtf16: 4)],
    );
    expect(map.engineText, 'e\u0301\uFFFC👩‍💻Z');
    expect(
      () => map.displayRangeForEngineRange(startUtf16: 1, endUtf16: 3),
      throwsArgumentError,
    );
    expect(
      () => map.displayRangeForEngineRange(startUtf16: 2, endUtf16: 4),
      throwsArgumentError,
    );
    expect(map.displayRangeForEngineRange(startUtf16: 2, endUtf16: 3), (
      startUtf16: 2,
      endUtf16: 4,
    ));
    expect(map.displayRangeForEngineRange(startUtf16: 3, endUtf16: 3), (
      startUtf16: 4,
      endUtf16: 4,
    ));
    expect(map.engineAtDisplayUtf16(3).isExact, isFalse);
  });

  test(
    'independent child boundaries are not recomputed from concatenated text',
    () {
      final display = HtmlDisplayTextProjection.concatenate([
        HtmlDisplayTextSegment(project('e', 0)),
        HtmlDisplayTextSegment(project('\u0301', 1)),
      ]);
      final map = HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: [
          (startUtf16: 0, endUtf16: 1),
          (startUtf16: 1, endUtf16: 2),
        ],
      );
      expect(map.engineText, '\uFFFC\uFFFC');
      expect(map.sourceAtEngineUtf16(1).sourceRune, 1);
      expect(map.sourceAtEngineUtf16(1).isExact, isTrue);
      expect(
        () => HtmlInlineTextProjection.build(
          display: project('e\u0301'),
          atomicRanges: [(startUtf16: 0, endUtf16: 1)],
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'invalid, overlapping, reversed and split-grapheme atoms fail before publication',
    () {
      final display = project('A👩‍💻e\u0301Z');
      for (final ranges in <List<({int startUtf16, int endUtf16})>>[
        [(startUtf16: 0, endUtf16: 0)],
        [(startUtf16: 0, endUtf16: 6), (startUtf16: 1, endUtf16: 6)],
        [(startUtf16: 6, endUtf16: 8), (startUtf16: 0, endUtf16: 1)],
        [(startUtf16: 2, endUtf16: 6)],
        [(startUtf16: 6, endUtf16: 7)],
        [(startUtf16: -1, endUtf16: 1)],
        [(startUtf16: 0, endUtf16: 100)],
        [(startUtf16: 2, endUtf16: 1)],
      ]) {
        expect(
          () => HtmlInlineTextProjection.build(
            display: display,
            atomicRanges: ranges,
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test('budgets count both actual display payload and engine placeholders', () {
    final display = project('漢字かな');
    final ranges = [(startUtf16: 0, endUtf16: 2), (startUtf16: 2, endUtf16: 4)];
    expect(
      () => HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: ranges,
        maxAtoms: 1,
      ),
      throwsA(isA<HtmlInlineTextLimitException>()),
    );
    expect(
      () => HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: ranges,
        maxDisplayCodeUnits: 3,
      ),
      throwsA(isA<HtmlInlineTextLimitException>()),
    );
    expect(
      () => HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: ranges,
        maxEngineCodeUnits: 1,
      ),
      throwsA(isA<HtmlInlineTextLimitException>()),
    );
    final map = HtmlInlineTextProjection.build(
      display: display,
      atomicRanges: ranges,
      maxAtoms: 2,
      maxDisplayCodeUnits: 4,
      maxEngineCodeUnits: 2,
    );
    expect(map.engineText.length, 2);
    expect(
      () => HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: [],
        maxAtoms: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: [],
        maxDisplayCodeUnits: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => HtmlInlineTextProjection.build(
        display: display,
        atomicRanges: [],
        maxEngineCodeUnits: -1,
      ),
      throwsArgumentError,
    );
  });

  test(
    'empty maps preserve source edge affinity and validate coordinate ranges',
    () {
      final source = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: 'A', sourceRuneStart: 0),
        HtmlDisplayTextRun(text: 'B', sourceRuneStart: 50),
      ]).slice(startUtf16: 1, endUtf16: 1);
      final map = HtmlInlineTextProjection.build(
        display: source,
        atomicRanges: [],
        maxAtoms: 0,
        maxDisplayCodeUnits: 0,
        maxEngineCodeUnits: 0,
      );
      expect(map.engineText, isEmpty);
      expect(map.sourceAtEngineUtf16(0).sourceRune, 50);
      expect(
        map
            .sourceAtEngineUtf16(0, affinity: HtmlProjectionAffinity.upstream)
            .sourceRune,
        1,
      );
      expect(map.sourceAtEngineUtf16(0).isExact, isFalse);
      expect(map.displayAtEngineUtf16(0).isExact, isTrue);
      expect(() => map.displayAtEngineUtf16(-1), throwsRangeError);
      expect(() => map.displayAtEngineUtf16(1), throwsRangeError);
      expect(() => map.engineAtDisplayUtf16(1), throwsRangeError);
      expect(
        () => map.displayRangeForEngineRange(startUtf16: 1, endUtf16: 1),
        throwsRangeError,
      );
    },
  );

  test(
    'map identity includes source, segmentation and explicit atomic ranges',
    () {
      final original = HtmlInlineTextProjection.build(
        display: project('ABC', 10),
        atomicRanges: [(startUtf16: 1, endUtf16: 2)],
      );
      final same = HtmlInlineTextProjection.build(
        display: project('ABC', 10),
        atomicRanges: [(startUtf16: 1, endUtf16: 2)],
      );
      expect(original.mappingHash, same.mappingHash);
      expect(original.hasSameMapping(same), isTrue);
      expect(original.hasSameMapping(original), isTrue);
      for (final different in [
        HtmlInlineTextProjection.build(
          display: project('ABC', 20),
          atomicRanges: [(startUtf16: 1, endUtf16: 2)],
        ),
        HtmlInlineTextProjection.build(
          display: project('ABC', 10),
          atomicRanges: [],
        ),
        HtmlInlineTextProjection.build(
          display: project('ABC', 10),
          atomicRanges: [(startUtf16: 0, endUtf16: 1)],
        ),
      ]) {
        expect(original.hasSameMapping(different), isFalse);
      }
    },
  );
}
