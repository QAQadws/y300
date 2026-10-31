import 'package:html_pagination_core/html_pagination_core.dart';
import 'package:test/test.dart';

HtmlDisplayTextProjection project(String text, int source) =>
    HtmlDisplayTextProjection.build([
      HtmlDisplayTextRun(
        text: text,
        sourceRuneStart: source,
        whiteSpace: HtmlDisplayWhiteSpace.preWrap,
      ),
    ]);

void main() {
  test(
    'independent base and annotation preserve separate grapheme contexts',
    () {
      final combined = HtmlDisplayTextProjection.concatenate([
        HtmlDisplayTextSegment(project('e', 10)),
        HtmlDisplayTextSegment(project('\u0301', 11), runIndexOffset: 1),
      ]);
      final ordinary = project('e\u0301', 10);
      expect(combined.text, ordinary.text);
      expect(combined.graphemeRanges(startUtf16: 0, endUtf16: 2).toList(), [
        (startUtf16: 0, endUtf16: 1),
        (startUtf16: 1, endUtf16: 2),
      ]);
      expect(ordinary.sourceAtUtf16(1).displayUtf16, 2);
      expect(combined.sourceAtUtf16(1).displayUtf16, 1);
      expect(combined.hasSameDisplaySegmentation(ordinary), isFalse);
      expect(combined.hasSameSourceMapping(ordinary), isFalse);
      expect(combined.parts.map((part) => part.runIndex), [0, 1]);
    },
  );

  test(
    'concatenation preserves explicit style ownership without whitespace normalization',
    () {
      final combined = HtmlDisplayTextProjection.concatenate([
        HtmlDisplayTextSegment(project(' A ', 10), runIndexOffset: 3),
        HtmlDisplayTextSegment(project('\tB\u00a0', 30), runIndexOffset: 7),
      ]);
      expect(combined.text, ' A \tB\u00a0');
      expect(combined.parts.map((part) => (part.runIndex, part.utf16Start)), [
        (3, 0),
        (7, 3),
      ]);
      expect(combined.sourceAtUtf16(3).sourceRune, 30);
      expect(
        combined
            .sourceAtUtf16(3, affinity: HtmlProjectionAffinity.upstream)
            .sourceRune,
        13,
      );
      expect(combined.sourceAtUtf16(3).isExact, isFalse);
      expect(() => combined.parts.clear(), throwsUnsupportedError);
    },
  );

  test(
    'display windows retain outside affinity at a source gap, even when empty',
    () {
      final original = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: 'A', sourceRuneStart: 5),
        HtmlDisplayTextRun(text: 'B', sourceRuneStart: 50),
      ]);
      final left = original.slice(startUtf16: 0, endUtf16: 1);
      final right = original.slice(startUtf16: 1, endUtf16: 2);
      final empty = original.slice(startUtf16: 1, endUtf16: 1);
      expect(left.sourceAtUtf16(1).sourceRune, 50);
      expect(
        left
            .sourceAtUtf16(1, affinity: HtmlProjectionAffinity.upstream)
            .sourceRune,
        6,
      );
      expect(right.sourceAtUtf16(0).sourceRune, 50);
      expect(
        right
            .sourceAtUtf16(0, affinity: HtmlProjectionAffinity.upstream)
            .sourceRune,
        6,
      );
      expect(empty.sourceAtUtf16(0).sourceRune, 50);
      expect(
        empty
            .sourceAtUtf16(0, affinity: HtmlProjectionAffinity.upstream)
            .sourceRune,
        6,
      );
      expect(empty.sourceAtUtf16(0).isExact, isFalse);
      expect(empty.hasSameSourceMapping(project('', 50)), isFalse);
      final reconstructed = HtmlDisplayTextProjection.concatenate([
        HtmlDisplayTextSegment(left),
        HtmlDisplayTextSegment(empty),
        HtmlDisplayTextSegment(right),
      ]);
      expect(reconstructed.hasSameSourceMapping(original), isTrue);
      expect(right.parts.single.runIndex, 1);
    },
  );

  test(
    'slice cannot cut Unicode graphemes and keeps styled child run indices',
    () {
      final original = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: 'x👨‍👩‍👧‍👦', sourceRuneStart: 0),
        HtmlDisplayTextRun(text: 'e\u0301z', sourceRuneStart: 8),
      ]);
      final middle = original.slice(startUtf16: 1, endUtf16: 14);
      expect(middle.text, '👨‍👩‍👧‍👦e\u0301');
      expect(middle.parts.map((part) => (part.runIndex, part.utf16Start)), [
        (0, 0),
        (1, 11),
      ]);
      expect(middle.sourceAtUtf16(0).sourceRune, 1);
      expect(middle.sourceAtUtf16(middle.text.length).sourceRune, 10);
      expect(
        () => original.slice(startUtf16: 2, endUtf16: 14),
        throwsArgumentError,
      );
      expect(
        () => original.slice(startUtf16: 1, endUtf16: 13),
        throwsArgumentError,
      );
    },
  );

  test(
    'empty segments keep their source positions and cannot hide reversed source order',
    () {
      final only = HtmlDisplayTextProjection.concatenate([
        HtmlDisplayTextSegment(project('', 25)),
      ]);
      expect(only.sourceAtUtf16(0).sourceRune, 25);
      expect(
        HtmlDisplayTextProjection.concatenate([]).sourceAtUtf16(0).sourceRune,
        0,
      );
      expect(
        () => HtmlDisplayTextProjection.concatenate([
          HtmlDisplayTextSegment(project('A', 10)),
          HtmlDisplayTextSegment(project('', 30)),
          HtmlDisplayTextSegment(project('B', 20)),
        ]),
        throwsArgumentError,
      );
      expect(
        () => HtmlDisplayTextProjection.concatenate([
          HtmlDisplayTextSegment(project('AB', 10)),
          HtmlDisplayTextSegment(project('B', 11)),
        ]),
        throwsArgumentError,
      );
      expect(
        () => HtmlDisplayTextProjection.concatenate([
          HtmlDisplayTextSegment(project('A', 0), runIndexOffset: -1),
        ]),
        throwsArgumentError,
      );
    },
  );

  test(
    'composition enforces both text and structural budgets before publication',
    () {
      final segments = [
        HtmlDisplayTextSegment(project('AB', 0)),
        HtmlDisplayTextSegment(project('C', 2)),
      ];
      expect(
        () => HtmlDisplayTextProjection.concatenate(
          segments,
          maxOutputCodeUnits: 2,
        ),
        throwsA(isA<HtmlDisplayTextLimitException>()),
      );
      expect(
        () => HtmlDisplayTextProjection.concatenate(segments, maxSegments: 1),
        throwsA(isA<HtmlDisplayTextLimitException>()),
      );
      expect(
        () => HtmlDisplayTextProjection.concatenate([], maxSegments: -1),
        throwsArgumentError,
      );
    },
  );

  test(
    'every source affinity agrees after a Unicode projection is split and reassembled',
    () {
      final original = HtmlDisplayTextProjection.build(const [
        HtmlDisplayTextRun(text: ' A👨‍👩‍👧‍👦e', sourceRuneStart: 10),
        HtmlDisplayTextRun(text: '\u0301\r\n Z ', sourceRuneStart: 40),
      ], preserveCollapsibleEdges: true);
      final children = [
        for (final range in original.graphemeRanges(
          startUtf16: 0,
          endUtf16: original.text.length,
        ))
          HtmlDisplayTextSegment(
            original.slice(
              startUtf16: range.startUtf16,
              endUtf16: range.endUtf16,
            ),
          ),
      ];
      final combined = HtmlDisplayTextProjection.concatenate(children);
      expect(combined.hasSameSourceMapping(original), isTrue);
      for (var offset = 0; offset <= original.text.length; offset++) {
        for (final affinity in HtmlProjectionAffinity.values) {
          final before = original.sourceAtUtf16(offset, affinity: affinity);
          final after = combined.sourceAtUtf16(offset, affinity: affinity);
          expect(
            (after.sourceRune, after.displayUtf16, after.isExact),
            (before.sourceRune, before.displayUtf16, before.isExact),
          );
        }
      }
    },
  );
}
