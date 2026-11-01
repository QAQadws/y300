import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';
import 'package:forum_content_renderer/src/inline/forum_body_inline_plan_input.dart';

ForumBodyInlinePlanInput _input(String html) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'raw-ruby-levels',
    conversionIdentity: 'none',
  );
  final cursor = ForumBodyTextFlowCursor(
    document: document,
    reader: ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  try {
    while (!cursor.isComplete) {
      final step = cursor.advance(maxEvents: 1);
      expect(step.workDone, lessThanOrEqualTo(1));
      if (cursor.current case ForumBodyTextFlowInline(:final content)) {
        return ForumBodyInlinePlanInput(content, 500);
      }
    }
    throw StateError('No inline content');
  } finally {
    cursor.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (html, display, parts) in [
    (
      '<ruby>A<rtc>word</rtc></ruby>',
      'Aword',
      [
        ['A', 'word'],
      ],
    ),
    (
      '<ruby>A<rtc> </rtc></ruby>',
      'A',
      [
        ['A', ''],
      ],
    ),
    (
      '<ruby>A<rtc>&nbsp;<rt>x</rt></rtc></ruby>',
      'A\u00a0x',
      [
        ['A', '\u00a0'],
        ['', 'x'],
      ],
    ),
    (
      '<ruby>A<rtc><rt>x</rt></rtc><rtc>word</rtc></ruby>',
      'Axword',
      [
        ['A', 'x', 'word'],
      ],
    ),
    (
      '<ruby><rb>A</rb><rb>B</rb><rtc>pre<rt>xx</rt></rtc></ruby>',
      'ApreBxx',
      [
        ['A', 'pre'],
        ['B', 'xx'],
      ],
    ),
    (
      '<ruby>A<rtc><rt>x</rt></rtc><rtc><rt>y</rt></rtc></ruby>',
      'Axy',
      [
        ['A', 'x', 'y'],
      ],
    ),
    (
      '<ruby><rt>x</rt><rt>y</rt><rtc><rt>u</rt></rtc></ruby>',
      'xuy',
      [
        ['', 'x', 'u'],
        ['', 'y', ''],
      ],
    ),
    (
      '<ruby><rb>A</rb><rb>B</rb><rtc><rt>xx</rt><rt>yy</rt></rtc><rtc><rt>uu</rt><rt>vv</rt></rtc></ruby>',
      'AxxuuByyvv',
      [
        ['A', 'xx', 'uu'],
        ['B', 'yy', 'vv'],
      ],
    ),
    (
      '<ruby><rb>A</rb><rb>B</rb><rt>xx</rt><rt>yy</rt><rtc><rt>uu</rt><rt>vv</rt></rtc><rt>zz</rt></ruby>',
      'AxxuuzzByyvv',
      [
        ['A', 'xx', 'uu', 'zz'],
        ['B', 'yy', 'vv', ''],
      ],
    ),
    (
      '<ruby><rb>A</rb><rb>B</rb><rtc><rt>xx</rt></rtc><rtc><rt>uu</rt><rt>vv</rt><rt>ww</rt></rtc></ruby>',
      'AxxuuBvvww',
      [
        ['A', 'xx', 'uu'],
        ['B', '', 'vv'],
        ['', '', 'ww'],
      ],
    ),
    (
      '<ruby><rt>xx</rt><rt>yy</rt><rtc><rt>uu</rt><rt>vv</rt></rtc></ruby>',
      'xxuuyyvv',
      [
        ['', 'xx', 'uu'],
        ['', 'yy', 'vv'],
      ],
    ),
    (
      '<ruby><rb>A</rb><rb>B</rb><rtc></rtc><rtc><rt>xx</rt><rt>yy</rt></rtc></ruby>',
      'AxxByy',
      [
        ['A', '', 'xx'],
        ['B', '', 'yy'],
      ],
    ),
    (
      '<ruby><rb>A</rb><rb>B</rb><rtc><rt></rt><rt>yy</rt></rtc><rtc><rt>uu</rt></rtc></ruby>',
      'AuuByy',
      [
        ['A', '', 'uu'],
        ['B', 'yy', ''],
      ],
    ),
  ]) {
    test('raw ordered levels preserve columns and original sources: $html', () {
      final input = _input(html);
      expect(input.content.projection.display.text, display);
      expect([
        for (final column in input.groups)
          [
            column.base.content.projection.text,
            for (final rank in column.annotations)
              rank.request.content.projection.text,
          ],
      ], parts);
      expect(input.rubyLevelIds.toSet(), {0});
      final glyphs = <ForumBodyParagraphContent>[];
      for (final column in input.groups) {
        for (final request in [
          column.base,
          ...column.annotations.map((a) => a.request),
        ]) {
          final content = request.content;
          if (content.projection.text.isEmpty) {
            if (content.isSourceFree) {
              expect(content.path, isNull);
              expect(content.runs, isEmpty);
            } else {
              // An actual empty RT retains its DOM range and resolved style;
              // only a missing pairing slot is an anonymous source-free value.
              expect(content.path, isNotNull);
            }
          } else {
            glyphs.add(content);
          }
        }
      }
      // The actual batching order follows the original level-major DOM order.
      final band = input.groups
          .expand((column) => column.nativeRequests)
          .whereType<ForumBodyTextBandChildRequest>()
          .first
          .band;
      expect(band.contexts.toSet(), glyphs.toSet());
      final starts = band.contexts
          .map((context) => context.projection.sourceAtUtf16(0).sourceRune)
          .toList();
      expect(starts, orderedEquals([...starts]..sort()));
      for (final context in input.content.contexts) {
        if (context.content.projection.text.length < 2) continue;
        final hit = input.content.projection.display.sourceAtUtf16(
          context.startUtf16 + 1,
        );
        expect(hit.isExact, isTrue);
        expect(
          hit.sourceRune,
          context.content.projection.sourceAtUtf16(1).sourceRune,
        );
      }
    });
  }

  for (final (style, levels, expected) in [
    (
      '',
      '<rt>x</rt><rtc><rt>u</rt></rtc><rt>z</rt>',
      [ForumBodyRubySide.over, ForumBodyRubySide.under, ForumBodyRubySide.over],
    ),
    (
      'ruby-position:alternate under',
      '<rt>x</rt><rtc><rt>u</rt></rtc><rt>z</rt>',
      [
        ForumBodyRubySide.under,
        ForumBodyRubySide.over,
        ForumBodyRubySide.under,
      ],
    ),
    (
      'ruby-position:over',
      '<rtc><rt>x</rt></rtc><rtc><rt>u</rt></rtc><rtc><rt>z</rt></rtc>',
      [ForumBodyRubySide.over, ForumBodyRubySide.over, ForumBodyRubySide.over],
    ),
    (
      'ruby-position:under',
      '<rtc><rt>x</rt></rtc><rtc><rt>u</rt></rtc>',
      [ForumBodyRubySide.under, ForumBodyRubySide.under],
    ),
    (
      '',
      '<rtc></rtc><rtc><rt>x</rt></rtc><rtc><rt style="ruby-position:under">u</rt></rtc>',
      [ForumBodyRubySide.over, ForumBodyRubySide.under, ForumBodyRubySide.over],
    ),
  ]) {
    test(
      'each actual level owns its side, including empty ranks: $style/$levels',
      () {
        final input = _input('<ruby style="$style">A$levels</ruby>');
        expect(
          input.groups.single.annotations.map((rank) => rank.side),
          expected,
        );
      },
    );
  }

  test('empty actual RT consumes its own column with its resolved style', () {
    final input = _input(
      '<ruby><rb>A</rb><rb>B</rb><rtc style="font-size:30px"><rt style="font-size:12px"></rt><rt>yy</rt></rtc><rtc><rt>uu</rt></rtc></ruby>',
    );
    expect(input.groups, hasLength(2));
    final empty = input.groups.first.annotations.first.request.content;
    expect(empty.path, isNotNull);
    expect(empty.projection.text, isEmpty);
    expect(empty.style.textStyle.fontSize, 12);
    expect(
      input
          .groups
          .last
          .annotations
          .first
          .request
          .content
          .style
          .textStyle
          .fontSize,
      30,
    );
    expect(input.groups.map((column) => column.nativeHandleCount), [2, 2]);
  });

  for (final html in [
    '<ruby>A<rtc style="white-space:pre"><rt>x</rt> <rt>y</rt></rtc><rt>z</rt></ruby>',
    '<ruby>A<rtc><rt>x<ruby>B<rt>b</rt></ruby></rt></rtc><rt>z</rt></ruby>',
    '<ruby>A<rtc><rt>x</rt></rtc><rtc style="ruby-position:inter-character"><rt>y</rt></rtc></ruby>',
  ]) {
    test(
      'unsupported later level does not flatten or partially admit: $html',
      () {
        expect(
          () => _input(html),
          throwsA(isA<ForumBodyParagraphInputException>()),
        );
      },
    );
  }
}
