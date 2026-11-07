import 'package:forum_content_renderer/forum_text.dart';
import 'package:flutter_test/flutter_test.dart';

HtmlDisplayTextProjection _gap(
  String text, {
  HtmlDisplayWhiteSpace mode = HtmlDisplayWhiteSpace.normal,
  bool suppress = false,
}) => HtmlDisplayTextProjection.build(
  [HtmlDisplayTextRun(text: text, sourceRuneStart: 10, whiteSpace: mode)],
  preserveCollapsibleEdges: true,
  suppressLineBreaks: suppress,
);

void main() {
  test('equal spaces retain distinct actual segment-break origins', () {
    final explicit = _gap(' ');
    final line = _gap('\n');
    expect(explicit.text, line.text);
    expect(explicit.hasSameSourceMapping(line), isTrue);
    expect(explicit.hasCollapsibleSegmentBreaks, isFalse);
    expect(line.hasCollapsibleSegmentBreaks, isTrue);
    var calls = 0;
    expect(
      explicit.resolveWhitespaceSegmentBreaks(
        shouldRemove: (before, after) {
          calls++;
          return true;
        },
      ),
      same(explicit),
    );
    expect(calls, 0);
    expect(
      line.resolveWhitespaceSegmentBreaks(shouldRemove: (_, _) => false),
      same(line),
    );
  });

  test(
    'split CRLF collapse keeps original source fences and no phantom glyph',
    () {
      final projection = HtmlDisplayTextProjection.build([
        const HtmlDisplayTextRun(text: ' \r', sourceRuneStart: 10),
        const HtmlDisplayTextRun(text: '\n\t ', sourceRuneStart: 12),
      ], preserveCollapsibleEdges: true);
      final seen = <(String?, String?)>[];
      final resolved = projection.resolveWhitespaceSegmentBreaks(
        precedingGrapheme: 'á',
        followingGrapheme: '🦊',
        shouldRemove: (a, b) {
          seen.add((a, b));
          return true;
        },
      );
      expect(seen, [('á', '🦊')]);
      expect(projection.text, ' ');
      expect(resolved.text, '');
      expect(resolved.parts, isEmpty);
      expect(resolved.hasCollapsibleSegmentBreaks, isFalse);
      expect(resolved.sourceEnvelope(startUtf16: 0, endUtf16: 0), isNull);
      expect(resolved.sourceAtUtf16(0).sourceRune, 15);
      expect(
        resolved
            .sourceAtUtf16(0, affinity: HtmlProjectionAffinity.upstream)
            .sourceRune,
        10,
      );
      expect(resolved.sourceAtUtf16(0).isExact, isFalse);
      expect(projection.text, ' ');
    },
  );

  for (final mode in HtmlDisplayWhiteSpace.values) {
    test('only real collapsible breaks are removable ($mode)', () {
      final raw = _gap('\n', mode: mode);
      final suppressed = _gap('\n', mode: mode, suppress: true);
      final normal =
          mode == HtmlDisplayWhiteSpace.normal ||
          mode == HtmlDisplayWhiteSpace.singleLine;
      expect(raw.hasCollapsibleSegmentBreaks, normal);
      expect(
        raw.resolveWhitespaceSegmentBreaks(shouldRemove: (_, _) => true).text,
        normal ? '' : '\n',
      );
      expect(
        suppressed
            .resolveWhitespaceSegmentBreaks(shouldRemove: (_, _) => true)
            .text,
        '',
      );
    });
  }

  test(
    'preserved spaces, tab and nonbreaking gaps survive removed suppression',
    () {
      final projection = _gap(
        ' \t\n \u00a0\u3000',
        mode: HtmlDisplayWhiteSpace.pre,
        suppress: true,
      );
      final contexts = <(String?, String?)>[];
      final resolved = projection.resolveWhitespaceSegmentBreaks(
        shouldRemove: (a, b) {
          contexts.add((a, b));
          return true;
        },
      );
      expect(contexts, [('\t', ' ')]);
      expect(resolved.text, ' \t \u00a0\u3000');
      expect(
        resolved
            .sourceAtUtf16(2, affinity: HtmlProjectionAffinity.upstream)
            .sourceRune,
        12,
      );
      expect(resolved.sourceAtUtf16(2).sourceRune, 13);
      expect(resolved.sourceAtUtf16(2).isExact, isFalse);
    },
  );

  test(
    'slice and explicit run ownership preserve origins without normalizing again',
    () {
      final raw = _gap('\n');
      final projection = HtmlDisplayTextProjection.concatenate([
        HtmlDisplayTextSegment(_gap(' ')),
        HtmlDisplayTextSegment(
          HtmlDisplayTextProjection.build([
            const HtmlDisplayTextRun(text: '\n', sourceRuneStart: 11),
          ], preserveCollapsibleEdges: true),
          runIndexOffset: 1,
        ),
        HtmlDisplayTextSegment(
          HtmlDisplayTextProjection.build([
            const HtmlDisplayTextRun(
              text: '\t\u00a0',
              sourceRuneStart: 12,
              whiteSpace: HtmlDisplayWhiteSpace.pre,
            ),
          ], preserveCollapsibleEdges: true),
          runIndexOffset: 2,
        ),
      ]);
      expect(
        raw.slice(startUtf16: 0, endUtf16: 1).hasCollapsibleSegmentBreaks,
        isTrue,
      );
      expect(
        projection
            .slice(startUtf16: 0, endUtf16: 1)
            .hasCollapsibleSegmentBreaks,
        isFalse,
      );
      expect(
        projection
            .slice(startUtf16: 1, endUtf16: 2)
            .hasCollapsibleSegmentBreaks,
        isTrue,
      );
      final resolved = projection.resolveWhitespaceSegmentBreaks(
        shouldRemove: (_, _) => true,
      );
      expect(resolved.text, ' \t\u00a0');
      expect(resolved.parts.map((p) => (p.runIndex, p.text, p.utf16Start)), [
        (0, ' ', 0),
        (2, '\t\u00a0', 1),
      ]);
      expect(
        resolved
            .sourceAtUtf16(1, affinity: HtmlProjectionAffinity.upstream)
            .sourceRune,
        11,
      );
      expect(resolved.sourceAtUtf16(1).sourceRune, 12);
      expect(projection.text, '  \t\u00a0');
    },
  );

  test(
    'context is one grapheme and non-whitespace is never partly rewritten',
    () {
      for (final bad in ['', 'ab', '😀x']) {
        expect(
          () => _gap('\n').resolveWhitespaceSegmentBreaks(
            shouldRemove: (_, _) => true,
            precedingGrapheme: bad,
          ),
          throwsArgumentError,
        );
      }
      for (final text in ['x\ny', ' \u0301', '😀']) {
        expect(
          () => _gap(
            text,
          ).resolveWhitespaceSegmentBreaks(shouldRemove: (_, _) => true),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'first and last contexts respect independent graphemes and supplementary text',
    () {
      final projection = HtmlDisplayTextProjection.build([
        const HtmlDisplayTextRun(text: 'á🦊', sourceRuneStart: 5),
      ]);
      expect(projection.firstGrapheme, 'á');
      expect(projection.lastGrapheme, '🦊');
      expect(_gap('').firstGrapheme, isNull);
      expect(_gap('').lastGrapheme, isNull);
    },
  );
}
