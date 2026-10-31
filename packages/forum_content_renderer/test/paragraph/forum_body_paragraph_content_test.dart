import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

({ForumBodyDocument document, ForumBodyStyleResult styles}) prepare(
  String html,
) {
  final document = const ForumBodyParser().parse(
    html: html,
    sourceId: 'paragraph',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontSize: 20,
        fontFamily: 'Reader',
        color: Color(0xff222222),
      ),
      fontRevision: 'loaded-1',
      linkColor: const Color(0xff0000ff),
    ),
  );
  return (document: document, styles: styles);
}

void main() {
  test('inline IR is projected once with style/link/source ownership', () {
    final input = prepare(
      '<p> 甲 <b> 乙</b><br><a href="target">👨‍👩‍👧‍👦e<i>́</i></a></p>',
    );
    final paragraph = const ForumBodyParagraphContentBuilder().build(
      document: input.document,
      styles: input.styles,
      path: '0',
    );
    expect(paragraph.projection.text, '甲 乙\n👨‍👩‍👧‍👦é');
    expect(paragraph.textSpan.toPlainText(), paragraph.projection.text);
    expect(
      paragraph.runs.any((run) => run.style.linkTarget == 'target'),
      isTrue,
    );
    expect(
      paragraph.runs.any(
        (run) => run.style.textStyle.fontWeight == FontWeight.w700,
      ),
      isTrue,
    );
    expect(paragraph.fontRevision, 'loaded-1');
    expect(paragraph.styleRevision, ForumBodyStyleResolver.revision);
    expect(paragraph.identity, input.document.identity);
    expect(identical(paragraph.textSpan, paragraph.textSpan), isTrue);
    expect(() => input.document.nodesByPath.clear(), throwsUnsupportedError);
    expect(() => paragraph.runs.clear(), throwsUnsupportedError);
  });

  test('anonymous top-level inline content preserves literal indentation', () {
    final input = prepare('　甲<font face="Other" size="5">乙</font><br>丙');
    final paragraph = const ForumBodyParagraphContentBuilder().build(
      document: input.document,
      styles: input.styles,
    );
    expect(paragraph.projection.text, '　甲乙\n丙');
    expect(
      paragraph.runs.every((run) => run.style.textStyle.fontFamily == 'Reader'),
      isTrue,
    );
  });

  test('hidden content leaves source gaps; visibility retains geometry text', () {
    final input = prepare(
      '<p>甲<span hidden>secret</span><span style="visibility:hidden">乙</span>丙</p>',
    );
    final paragraph = const ForumBodyParagraphContentBuilder().build(
      document: input.document,
      styles: input.styles,
      path: '0',
    );
    expect(paragraph.projection.text, '甲乙丙');
    expect(paragraph.projection.sourceAtUtf16(1).isExact, isFalse);
    final spans = paragraph.textSpan.children!.whereType<TextSpan>().toList();
    expect(
      spans.firstWhere((span) => span.text == '乙').style!.foreground!.color,
      const Color(0x00000000),
    );
  });

  test('preformatted text is not normalized again by the span builder', () {
    final input = prepare('<p style="white-space:pre-wrap"> 甲\n 乙 </p>');
    final paragraph = const ForumBodyParagraphContentBuilder().build(
      document: input.document,
      styles: input.styles,
      path: '0',
    );
    expect(paragraph.textSpan.toPlainText(), ' 甲\n 乙 ');
  });

  test(
    'complex structures and inline boxes never silently lose their content',
    () {
      for (final html in [
        '<p>甲<img src="x">乙</p>',
        '<p><ruby>字<rt>zi</rt></ruby></p>',
        '<div><p>nested</p></div>',
        '<p><span style="padding:2px">box</span></p>',
      ]) {
        final input = prepare(html);
        expect(
          () => const ForumBodyParagraphContentBuilder().build(
            document: input.document,
            styles: input.styles,
            path: '0',
          ),
          throwsA(
            isA<ForumBodyParagraphInputException>().having(
              (e) => e.failure,
              'failure',
              ForumBodyParagraphInputFailure.structure,
            ),
          ),
        );
      }
    },
  );

  test('document provenance and input/run budgets are enforced', () {
    final input = prepare('<p>甲<b>乙</b></p>');
    final other = prepare('<p>other</p>');
    expect(
      () => const ForumBodyParagraphContentBuilder().build(
        document: input.document,
        styles: other.styles,
        path: '0',
      ),
      throwsA(
        isA<ForumBodyParagraphInputException>().having(
          (e) => e.failure,
          'failure',
          ForumBodyParagraphInputFailure.identity,
        ),
      ),
    );
    for (final (builder, reason) in [
      (
        const ForumBodyParagraphContentBuilder(maxInputCodeUnits: 1),
        ForumBodyParagraphInputFailure.inputLimit,
      ),
      (
        const ForumBodyParagraphContentBuilder(maxRuns: 1),
        ForumBodyParagraphInputFailure.runLimit,
      ),
    ]) {
      expect(
        () => builder.build(
          document: input.document,
          styles: input.styles,
          path: '0',
        ),
        throwsA(
          isA<ForumBodyParagraphInputException>().having(
            (e) => e.failure,
            'failure',
            reason,
          ),
        ),
      );
    }
  });
}
