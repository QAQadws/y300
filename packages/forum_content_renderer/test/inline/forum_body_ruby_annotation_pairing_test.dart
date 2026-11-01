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
}
