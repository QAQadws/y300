import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_annotation_input.dart';
import 'package:forum_content_renderer/src/inline/forum_body_ruby_annotation_pairing.dart';

ForumBodyRubyGroupContent _group(String html) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'ruby-span-pairing',
    conversionIdentity: 'none',
  );
  final flow = ForumBodyStyledFlowCursor(
    document: document,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  try {
    while (flow.moveNext()) {
      if (flow.current!.phase == ForumBodyFlowPhase.open &&
          flow.current!.node is ForumBodyElement &&
          (flow.current!.node as ForumBodyElement).kind ==
              ForumBodyElementKind.ruby) {
        break;
      }
    }
    final cursor = ForumBodyRubyContentCursor.openCurrent(flow);
    try {
      ForumBodyRubyGroupContent? group;
      for (var work = 0; !cursor.isComplete && work < 5000; work++) {
        final step = cursor.advance(maxEvents: 1);
        expect(step.workDone, lessThanOrEqualTo(1));
        if (step.hasOutput) {
          expect(group, isNull);
          group = cursor.current;
        }
      }
      expect(cursor.isComplete, isTrue);
      return group!;
    } finally {
      cursor.close();
    }
  } finally {
    flow.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('root whitespace belongs only to its original implicit level', () {
    final group = _group(
      '<ruby><rb>A</rb><rb>B</rb><rtc>whole</rtc><rt>x</rt> <rt>y</rt></ruby>',
    );
    expect(group.annotationGaps.single.beforeAnnotationIndex, 2);
    final paired = ForumBodyRubyAnnotationPairing(
      group: group,
      baseColumnCount: 2,
    );
    expect(paired.levels.length, 2);
    expect(paired.levels.first.gaps, isEmpty);
    final level = paired.levels.last;
    final gap = level.gaps.single;
    expect(gap.content, same(group.annotationGaps.single.content));
    expect(gap.beforeColumn, 1);
    expect(gap.previous, same(level.spans[0]));
    expect(gap.next, same(level.spans[1]));
    expect(gap.content.style.textStyle.fontSize, 20);
    expect(paired.columnRanges, [(startColumn: 0, endColumn: 2)]);
  });

  test(
    'root gap cannot target RTC, a first RT or a missing original entry',
    () {
      final original = _group(
        '<ruby>A<rt>x</rt> <rt>y</rt><rtc>all</rtc></ruby>',
      );
      final gap = original.annotationGaps.single;
      for (final index in [-1, 0, 2, 3]) {
        final group = ForumBodyRubyGroupContent(
          identity: original.identity,
          fontRevision: original.fontRevision,
          styleRevision: original.styleRevision,
          style: original.style,
          rootPath: original.rootPath,
          index: original.index,
          base: original.base,
          annotations: original.annotations,
          annotationGaps: [
            (beforeAnnotationIndex: index, content: gap.content),
          ],
        );
        expect(
          () =>
              ForumBodyRubyAnnotationPairing(group: group, baseColumnCount: 1),
          throwsA(isA<ForumBodyParagraphInputException>()),
        );
      }
    },
  );
  for (final (html, bases, columns, annotated, intervals) in [
    (
      '<ruby><rb>A</rb><rb>B</rb><rtc>word</rtc></ruby>',
      2,
      2,
      2,
      [
        [(0, 2)],
      ],
    ),
    (
      '<ruby><rb>A</rb><rb>B</rb><rtc><rt>word</rt></rtc></ruby>',
      2,
      2,
      1,
      [
        [(0, 1)],
      ],
    ),
    (
      '<ruby><rb>A</rb><rb>B</rb><rtc>pre<rt>x</rt>post</rtc></ruby>',
      2,
      3,
      3,
      [
        [(0, 1), (1, 2), (2, 3)],
      ],
    ),
    (
      '<ruby>A<rt>x</rt><rtc>word</rtc><rt>z</rt></ruby>',
      1,
      1,
      1,
      [
        [(0, 1)],
        [(0, 1)],
        [(0, 1)],
      ],
    ),
    (
      '<ruby><rb>A</rb><rb>B</rb><rtc>group</rtc><rtc><rt>x</rt><rt>y</rt><rt>z</rt></rtc></ruby>',
      2,
      3,
      3,
      [
        [(0, 3)],
        [(0, 1), (1, 2), (2, 3)],
      ],
    ),
    (
      '<ruby><rtc>orphan</rtc></ruby>',
      0,
      1,
      1,
      [
        [(0, 1)],
      ],
    ),
    (
      '<ruby>A<rtc> </rtc></ruby>',
      1,
      1,
      1,
      [
        [(0, 1)],
      ],
    ),
    (
      '<ruby>A<rtc></rtc><rtc>word</rtc></ruby>',
      1,
      1,
      1,
      [
        [],
        [(0, 1)],
      ],
    ),
    ('<ruby><rb>A</rb><rb>B</rb><rtc></rtc></ruby>', 2, 2, 0, [[]]),
    ('<ruby>A</ruby>', 1, 1, 0, [[]]),
  ]) {
    test(
      'actual anonymous/explicit unit intervals survive cursor retirement: $html',
      () {
        final group = _group(html);
        final pairing = ForumBodyRubyAnnotationPairing(
          group: group,
          baseColumnCount: bases,
        );
        expect(pairing.columnCount, columns);
        expect(pairing.annotatedColumnCount, annotated);
        expect([
          for (final level in pairing.levels)
            [
              for (final span in level.spans)
                (span.startColumn, span.endColumn),
            ],
        ], intervals);
        final multi = intervals
            .expand((level) => level)
            .any((interval) => interval.$2 - interval.$1 > 1);
        expect(pairing.hasMultiColumnSpans, multi);
        expect(() => pairing.levels.clear(), throwsUnsupportedError);
        for (final level in pairing.levels) {
          expect(() => level.spans.clear(), throwsUnsupportedError);
        }
      },
    );
  }

  test(
    'one spanning box retains actual context and no fabricated RT/source copy',
    () {
      final group = _group(
        '<ruby><rb>A</rb><rb>B</rb><rtc style="font-size:30px">word<b>bold</b></rtc></ruby>',
      );
      final rtc =
          group.annotations.single as ForumBodyRubyAnnotationContainerContent;
      final original = (rtc.parts.single as ForumBodyRubyTextContent).content;
      final pairing = ForumBodyRubyAnnotationPairing(
        group: group,
        baseColumnCount: 2,
      );
      final box =
          pairing.levels.single.spans.single.box
              as ForumBodyRubyAnonymousAnnotationInput;
      expect(box.content, same(original));
      expect(box.path, original.path);
      expect(box.content.projection.text, 'wordbold');
      expect(box.content.projection.sourceAtUtf16(1).sourceRune, 3);
      expect(box.content.runs.first.style.role, ForumBodyTextRole.ruby);
      expect(box.content.runs.first.style.textStyle.fontSize, 30);
      expect(box.content.runs.last.style.textStyle.fontWeight, FontWeight.w700);
      expect(
        rtc.parts.single,
        isNot(isA<ForumBodyRubyTextAnnotationContent>()),
      );
    },
  );

  test('anonymous and explicit boxes keep their own ordered identities', () {
    final group = _group(
      '<ruby><rb>A</rb><rb>B</rb><rtc>pre<rt>xx</rt>post</rtc><rtc>all</rtc></ruby>',
    );
    final rtc =
        group.annotations.first as ForumBodyRubyAnnotationContainerContent;
    final pairing = ForumBodyRubyAnnotationPairing(
      group: group,
      baseColumnCount: 2,
    );
    final boxes = pairing.levels.first.spans.map((span) => span.box).toList();
    expect(
      (boxes[0] as ForumBodyRubyAnonymousAnnotationInput).content,
      same((rtc.parts[0] as ForumBodyRubyTextContent).content),
    );
    expect(
      (boxes[1] as ForumBodyRubyExplicitAnnotationInput).annotation,
      same(rtc.parts[1]),
    );
    expect(
      (boxes[2] as ForumBodyRubyAnonymousAnnotationInput).content,
      same((rtc.parts[2] as ForumBodyRubyTextContent).content),
    );
    expect(pairing.levels.map((level) => level.side), [
      ForumBodyRubySide.over,
      ForumBodyRubySide.under,
    ]);
    expect(pairing.levels.last.spans.single.endColumn, 3);
  });

  test('empty levels retain side order before anonymous spans', () {
    final pairing = ForumBodyRubyAnnotationPairing(
      group: _group('<ruby>A<rtc></rtc><rtc>word</rtc><rt>x</rt></ruby>'),
      baseColumnCount: 1,
    );
    expect(pairing.levels.map((level) => level.side), [
      ForumBodyRubySide.over,
      ForumBodyRubySide.under,
      ForumBodyRubySide.over,
    ]);
    expect(pairing.levels.first.spans, isEmpty);
  });

  test(
    'real RTC gap keeps current source and adjacent RTs without joining columns',
    () {
      final group = _group(
        '<ruby><rb>a\u0301</rb><rb>😀</rb><rtc><rt>x</rt> <rt>y</rt></rtc></ruby>',
      );
      final rtc =
          group.annotations.single as ForumBodyRubyAnnotationContainerContent;
      final original = (rtc.parts[1] as ForumBodyRubyTextContent).content;
      final inputs = resolveForumBodyRubyAnnotationInputs(group);
      expect(inputs.single.boxes.length, 2);
      expect(inputs.single.gaps.single.beforeBox, 1);
      expect(inputs.single.gaps.single.content, same(original));
      final paired = ForumBodyRubyAnnotationPairing(
        group: group,
        baseColumnCount: 2,
      );
      expect(paired.columnCount, 2);
      expect(paired.annotatedColumnCount, 2);
      expect(paired.hasMultiColumnSpans, isFalse);
      expect(paired.hasAnnotationGaps, isTrue);
      expect(paired.columnRanges, [
        (startColumn: 0, endColumn: 1),
        (startColumn: 1, endColumn: 2),
      ]);
      final level = paired.levels.single;
      final gap = level.gaps.single;
      expect(gap.beforeColumn, 1);
      expect(gap.content, same(original));
      expect(gap.previous, same(level.spans[0]));
      expect(gap.next, same(level.spans[1]));
      expect(gap.content.projection.text, ' ');
      // Combining code points and a supplementary character are not UTF-16
      // units, nor may a column ordinal be used as a source coordinate.
      expect(gap.content.projection.sourceAtUtf16(0).sourceRune, 4);
      expect(() => level.gaps.clear(), throwsUnsupportedError);
      expect(() => inputs.single.gaps.clear(), throwsUnsupportedError);
      expect(() => paired.columnRanges.clear(), throwsUnsupportedError);
    },
  );

  test(
    'styled gap belongs to actual RTC and outer indentation does not enter pairing',
    () {
      final group = _group(
        '<ruby><rb>A</rb><rb>B</rb><rtc style="font-size:30px;white-space:pre"> \t<rt style="font-size:12px">x</rt> \t <rt style="font-size:18px">y</rt>\t </rtc></ruby>',
      );
      final rtc =
          group.annotations.single as ForumBodyRubyAnnotationContainerContent;
      final paired = ForumBodyRubyAnnotationPairing(
        group: group,
        baseColumnCount: 2,
      );
      final gap = paired.levels.single.gaps.single;
      expect(
        gap.content,
        same((rtc.parts[2] as ForumBodyRubyTextContent).content),
      );
      expect(gap.content.projection.text, ' \t ');
      expect(gap.content.runs.single.style.role, ForumBodyTextRole.ruby);
      expect(gap.content.runs.single.style.textStyle.fontSize, 30);
      expect(gap.content.runs.single.style.whiteSpace, ForumBodyWhiteSpace.pre);
      expect(
        paired.levels.single.spans.map(
          (s) => (s.box as ForumBodyRubyExplicitAnnotationInput)
              .annotation
              .style
              .textStyle
              .fontSize,
        ),
        [12, 18],
      );
      expect(paired.columnCount, 2);
      expect(paired.levels.single.gaps.length, 1);
    },
  );

  test(
    'empty actual RTs and excess columns preserve gap edges and rank topology',
    () {
      final paired = ForumBodyRubyAnnotationPairing(
        group: _group(
          '<ruby style="ruby-position:alternate under">A<rtc></rtc><rtc><rt></rt> <rt>y</rt> <rt></rt></rtc></ruby>',
        ),
        baseColumnCount: 1,
      );
      expect(paired.columnCount, 3);
      expect(paired.levels.map((l) => l.side), [
        ForumBodyRubySide.under,
        ForumBodyRubySide.over,
      ]);
      expect(paired.levels.first.gaps, isEmpty);
      final level = paired.levels.last;
      expect(level.spans.map((s) => (s.startColumn, s.endColumn)), [
        (0, 1),
        (1, 2),
        (2, 3),
      ]);
      expect(level.gaps.map((g) => g.beforeColumn), [1, 2]);
      for (final gap in level.gaps) {
        expect(gap.previous, same(level.spans[gap.beforeColumn - 1]));
        expect(gap.next, same(level.spans[gap.beforeColumn]));
      }
      expect(paired.columnRanges.length, 3);
    },
  );

  test(
    'actual spanning annotation closes ranges while spaces never consume a unit',
    () {
      final paired = ForumBodyRubyAnnotationPairing(
        group: _group(
          '<ruby><rb>A</rb><rb>B</rb><rtc>pre<rt>x</rt> <rt>y</rt></rtc><rtc>all</rtc></ruby>',
        ),
        baseColumnCount: 2,
      );
      expect(paired.columnCount, 3);
      expect(paired.levels.first.spans.length, 3);
      expect(paired.levels.first.gaps.single.beforeColumn, 2);
      expect(
        paired.levels.first.gaps.single.previous,
        same(paired.levels.first.spans[1]),
      );
      expect(
        paired.levels.first.gaps.single.next,
        same(paired.levels.first.spans[2]),
      );
      expect(paired.levels.last.gaps, isEmpty);
      expect(paired.levels.last.spans.single.endColumn, 3);
      expect(paired.columnRanges, [(startColumn: 0, endColumn: 3)]);
    },
  );

  test('equal gap text at different levels keeps distinct original contexts', () {
    final paired = ForumBodyRubyAnnotationPairing(
      group: _group(
        '<ruby><rb>A</rb><rb>B</rb><rb>C</rb><rtc><rt>x</rt> <rt>y</rt><rt>z</rt></rtc><rtc><rt>u</rt><rt>v</rt> <rt>w</rt></rtc></ruby>',
      ),
      baseColumnCount: 3,
    );
    final first = paired.levels.first.gaps.single;
    final second = paired.levels.last.gaps.single;
    expect(first.content.projection.text, second.content.projection.text);
    expect(identical(first.content, second.content), isFalse);
    expect(first.beforeColumn, 1);
    expect(second.beforeColumn, 2);
    expect(
      first.content.projection.sourceAtUtf16(0).sourceRune,
      lessThan(second.content.projection.sourceAtUtf16(0).sourceRune),
    );
    expect(paired.columnRanges.length, 3);
  });

  test(
    'sole whitespace annotation stays an actual anonymous box rather than a gap',
    () {
      final paired = ForumBodyRubyAnnotationPairing(
        group: _group('<ruby><rb>A</rb><rb>B</rb><rtc> </rtc></ruby>'),
        baseColumnCount: 2,
      );
      expect(paired.hasAnnotationGaps, isFalse);
      expect(
        paired.levels.single.spans.single.box,
        isA<ForumBodyRubyAnonymousAnnotationInput>(),
      );
      expect(paired.levels.single.spans.single.isMultiColumn, isTrue);
      expect(paired.columnRanges, [(startColumn: 0, endColumn: 2)]);
    },
  );
}
