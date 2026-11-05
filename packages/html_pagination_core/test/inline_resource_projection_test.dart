import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:test/test.dart';

HtmlDisplayTextProjection _text(String value) =>
    HtmlDisplayTextProjection.build([
      HtmlDisplayTextRun(
        text: value,
        sourceRuneStart: 50,
        whiteSpace: HtmlDisplayWhiteSpace.preWrap,
      ),
    ]);

void main() {
  test(
    'all insertion multiplicities preserve every text caret and engine edge',
    () {
      for (var pattern = 0; pattern < 243; pattern++) {
        var digits = pattern;
        final counts = <int>[];
        final ranges = <({int startUtf16, int endUtf16})>[];
        for (var fence = 0; fence <= 4; fence++) {
          final count = digits % 3;
          digits ~/= 3;
          counts.add(count);
          ranges.addAll(
            List.filled(count, (startUtf16: fence, endUtf16: fence)),
          );
        }
        final map = HtmlInlineTextProjection.build(
          display: _text('ABCD'),
          atomicRanges: ranges,
          resourceAtoms: {for (var i = 0; i < ranges.length; i++) i},
        );
        var before = 0;
        for (var fence = 0; fence <= 4; fence++) {
          expect(
            map
                .engineAtDisplayUtf16(
                  fence,
                  affinity: HtmlProjectionAffinity.upstream,
                )
                .engineUtf16,
            before,
            reason: 'pattern=$pattern/fence=$fence/upstream',
          );
          expect(
            map.engineAtDisplayUtf16(fence).engineUtf16,
            before + counts[fence],
            reason: 'pattern=$pattern/fence=$fence',
          );
          before += counts[fence] + 1;
        }
        for (var edge = 0; edge <= map.engineText.length; edge++) {
          expect(map.isLegalEngineBoundary(edge), isTrue);
          expect(map.displayAtEngineUtf16(edge).engineUtf16, edge);
        }
        expect(map.display.text, 'ABCD');
      }
    },
  );

  test('resources add engine slots without adding display or source text', () {
    final display = _text('A👩‍💻e\u0301B');
    final map = HtmlInlineTextProjection.build(
      display: display,
      atomicRanges: [
        (startUtf16: 0, endUtf16: 0),
        (startUtf16: 1, endUtf16: 1),
        (startUtf16: 1, endUtf16: 1),
        (startUtf16: 8, endUtf16: 8),
        (startUtf16: 9, endUtf16: 9),
      ],
      resourceAtoms: {0, 1, 2, 3, 4},
    );
    expect(map.display, same(display));
    expect(map.display.text, 'A👩‍💻e\u0301B');
    expect(map.engineText, '\uFFFCA\uFFFC\uFFFC👩‍💻e\u0301\uFFFCB\uFFFC');
    expect(map.hasResources, isTrue);
    expect(map.hasSoftSpaces, isFalse);
    expect(map.atoms.map((a) => a.engineUtf16), [0, 2, 3, 11, 13]);
    expect(map.atoms.every((a) => a.isResource && !a.isSoftSpace), isTrue);
    expect(
      map.atoms.every((a) => a.displayStartUtf16 == a.displayEndUtf16),
      isTrue,
    );
    expect(map.engineAtDisplayUtf16(1).engineUtf16, 4);
    expect(
      map
          .engineAtDisplayUtf16(1, affinity: HtmlProjectionAffinity.upstream)
          .engineUtf16,
      2,
    );
    for (final edge in [2, 3, 4]) {
      final point = map.displayAtEngineUtf16(edge);
      expect(
        (point.engineUtf16, point.displayUtf16, point.isExact),
        (edge, 1, true),
      );
      expect(map.isLegalEngineBoundary(edge), isTrue);
    }
    expect(map.sourceAtEngineUtf16(3).isExact, isFalse);
    expect(map.sourceAtEngineUtf16(4).sourceRune, 51);
    expect(map.sourceAtEngineUtf16(4).isExact, isTrue);
    expect(
      map
          .sourceAtEngineUtf16(2, affinity: HtmlProjectionAffinity.upstream)
          .isExact,
      isTrue,
    );
    expect(map.displayRangeForEngineRange(startUtf16: 2, endUtf16: 4), (
      startUtf16: 1,
      endUtf16: 1,
    ));
    // Engine wrapping inside the actual emoji is still illegal.
    expect(map.isLegalEngineBoundary(5), isFalse);
    expect(map.isLegalEngineBoundary(7), isFalse);
  });

  test(
    'resource-only rows have geometry boundaries, never exact source zero',
    () {
      final map = HtmlInlineTextProjection.build(
        display: HtmlDisplayTextProjection.build(const []),
        atomicRanges: List.filled(3, (startUtf16: 0, endUtf16: 0)),
        resourceAtoms: {0, 1, 2},
        enginePrefix: '\u00A0\u2060',
      );
      expect(map.engineText, '\u00A0\u2060\uFFFC\uFFFC\uFFFC');
      expect(map.isLegalEngineBoundary(1), isFalse);
      for (final edge in [0, 2, 3, 4, 5]) {
        expect(map.isLegalEngineBoundary(edge), isTrue);
        expect(map.sourceAtEngineUtf16(edge).isExact, isFalse);
      }
      expect(map.displayRangeForEngineRange(startUtf16: 2, endUtf16: 5), (
        startUtf16: 0,
        endUtf16: 0,
      ));
      expect(map.engineAtDisplayUtf16(0).engineUtf16, 5);
      expect(
        map
            .engineAtDisplayUtf16(0, affinity: HtmlProjectionAffinity.upstream)
            .engineUtf16,
        2,
      );
    },
  );

  test('resources and real opaque text retain independent ordered atoms', () {
    final map = HtmlInlineTextProjection.build(
      display: _text('ABCD'),
      atomicRanges: [
        (startUtf16: 0, endUtf16: 0),
        (startUtf16: 0, endUtf16: 2),
        (startUtf16: 2, endUtf16: 2),
        (startUtf16: 2, endUtf16: 4),
        (startUtf16: 4, endUtf16: 4),
      ],
      resourceAtoms: {0, 2, 4},
    );
    expect(map.engineText, '\uFFFC\uFFFC\uFFFC\uFFFC\uFFFC');
    expect(map.atoms.map((a) => a.isResource), [
      true,
      false,
      true,
      false,
      true,
    ]);
    expect(map.engineAtDisplayUtf16(0).engineUtf16, 1);
    expect(map.engineAtDisplayUtf16(2).engineUtf16, 3);
    expect(
      map
          .engineAtDisplayUtf16(2, affinity: HtmlProjectionAffinity.upstream)
          .engineUtf16,
      2,
    );
    expect(map.displayRangeForEngineRange(startUtf16: 1, endUtf16: 2), (
      startUtf16: 0,
      endUtf16: 2,
    ));
    expect(map.displayRangeForEngineRange(startUtf16: 2, endUtf16: 3), (
      startUtf16: 2,
      endUtf16: 2,
    ));
  });

  test(
    'actual source UFFFC and resource slots have different mapping identities',
    () {
      final text = HtmlInlineTextProjection.build(
        display: _text('\uFFFC'),
        atomicRanges: const [],
      );
      final resource = HtmlInlineTextProjection.build(
        display: HtmlDisplayTextProjection.build(const []),
        atomicRanges: [(startUtf16: 0, endUtf16: 0)],
        resourceAtoms: {0},
      );
      expect(text.engineText, resource.engineText);
      expect(text.hasSameMapping(resource), isFalse);
      expect(text.sourceAtEngineUtf16(0).isExact, isTrue);
      expect(resource.sourceAtEngineUtf16(0).isExact, isFalse);
      final equal = HtmlInlineTextProjection.build(
        display: HtmlDisplayTextProjection.build(const []),
        atomicRanges: [(startUtf16: 0, endUtf16: 0)],
        resourceAtoms: {0},
      );
      expect(equal.hasSameMapping(resource), isTrue);
      expect(equal.mappingHash, resource.mappingHash);
    },
  );

  test(
    'resource engine and atom budgets are independent from display length',
    () {
      HtmlInlineTextProjection build({int atoms = 2, int engine = 3}) =>
          HtmlInlineTextProjection.build(
            display: _text('A'),
            atomicRanges: List.filled(2, (startUtf16: 0, endUtf16: 0)),
            resourceAtoms: {0, 1},
            maxDisplayCodeUnits: 1,
            maxAtoms: atoms,
            maxEngineCodeUnits: engine,
          );
      expect(build().engineText.length, 3);
      expect(
        () => build(atoms: 1),
        throwsA(isA<HtmlInlineTextLimitException>()),
      );
      expect(
        () => build(engine: 2),
        throwsA(isA<HtmlInlineTextLimitException>()),
      );
    },
  );

  test(
    'invalid resources do not relax text graphemes, ordering or whitespace',
    () {
      HtmlInlineTextProjection build(
        List<({int startUtf16, int endUtf16})> ranges, {
        Set<int> resources = const {0},
        Set<int> spaces = const {},
      }) => HtmlInlineTextProjection.build(
        display: _text('A👩‍💻 B'),
        atomicRanges: ranges,
        resourceAtoms: resources,
        softSpaceAtoms: spaces,
      );
      expect(() => build([(startUtf16: 0, endUtf16: 1)]), throwsArgumentError);
      expect(() => build([(startUtf16: 2, endUtf16: 2)]), throwsArgumentError);
      expect(
        () => build([(startUtf16: 0, endUtf16: 0)], resources: {}),
        throwsArgumentError,
      );
      expect(
        () => build([(startUtf16: 0, endUtf16: 0)], resources: {1}),
        throwsRangeError,
      );
      expect(
        () => build([(startUtf16: 0, endUtf16: 0)], spaces: {0}),
        throwsArgumentError,
      );
      expect(
        () => build(
          [(startUtf16: 0, endUtf16: 6), (startUtf16: 1, endUtf16: 1)],
          resources: {1},
        ),
        throwsArgumentError,
      );
    },
  );

  test('resources preserve source gaps and separate grapheme contexts', () {
    final display = HtmlDisplayTextProjection.concatenate([
      HtmlDisplayTextSegment(_text('e')),
      HtmlDisplayTextSegment(
        HtmlDisplayTextProjection.build([
          const HtmlDisplayTextRun(
            text: '\u0301',
            sourceRuneStart: 90,
            whiteSpace: HtmlDisplayWhiteSpace.preWrap,
          ),
        ]),
        runIndexMap: {0: 1},
      ),
    ]);
    final map = HtmlInlineTextProjection.build(
      display: display,
      atomicRanges: [(startUtf16: 1, endUtf16: 1)],
      resourceAtoms: {0},
    );
    expect(map.engineText, 'e\uFFFC\u0301');
    expect(
      map
          .sourceAtEngineUtf16(1, affinity: HtmlProjectionAffinity.upstream)
          .sourceRune,
      51,
    );
    expect(map.sourceAtEngineUtf16(2).sourceRune, 90);
    expect(map.display, same(display));
  });
}
