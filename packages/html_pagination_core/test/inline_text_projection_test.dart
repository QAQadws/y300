import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:test/test.dart';

HtmlDisplayTextProjection project(String text, [int source = 0]) =>
    HtmlDisplayTextProjection.build([
      HtmlDisplayTextRun(
        text: text,
        sourceRuneStart: source,
        whiteSpace: HtmlDisplayWhiteSpace.preWrap,
      ),
    ]);

void main() {
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
