import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final _reader = ForumBodyReaderStyle(
  textStyle: const TextStyle(
    fontFamily: 'Ahem',
    fontSize: 20,
    height: 1,
    color: Color(0xff000000),
  ),
  fontRevision: 'ahem',
  linkColor: const Color(0xff0000ff),
);

({
  ForumBodyInlineSpanContent content,
  ForumBodyParagraphContent base,
  ForumBodyParagraphContent annotation,
  List<ForumBodyParagraphContent> contexts,
})
mixedInlineInput({
  String prefix = 'X',
  String base = 'AB',
  String annotation = 'xy',
  String suffix = 'Y',
  String paragraphStyle = '',
  String direction = 'ltr',
  ForumBodyReaderStyle? reader,
}) {
  final document = const ForumBodyParser().parse(
    html:
        '<p dir="$direction" style="$paragraphStyle"><span style="color:red">$prefix</span>'
        '<ruby>$base<rp>(</rp><rt>$annotation</rt><rp>)</rp></ruby>'
        '<span style="color:blue">$suffix</span></p>',
    sourceId: 'mixed-inline',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    reader ?? _reader,
  );
  final flow = ForumBodyStyledFlowCursor(
    document: document,
    reader: reader ?? _reader,
  );
  try {
    while (flow.moveNext()) {
      if (flow.current!.node.path == '0/1' &&
          flow.current!.phase == ForumBodyFlowPhase.open) {
        break;
      }
    }
    final cursor = ForumBodyRubyContentCursor.openCurrent(flow);
    try {
      ForumBodyRubyGroupContent? group;
      for (var work = 0; work < 100; work++) {
        final step = cursor.advance(maxEvents: 1);
        expect(step.workDone, lessThanOrEqualTo(1));
        if (step.hasOutput) group = cursor.current;
        if (step.isComplete) break;
      }
      final baseContent =
          (group!.base.single as ForumBodyRubyTextContent).content;
      final annotationContent =
          (group.annotations.single.parts.single as ForumBodyRubyTextContent)
              .content;
      ForumBodyParagraphContent build(String path) =>
          const ForumBodyParagraphContentBuilder().build(
            document: document,
            styles: styles,
            path: path,
            layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
          );
      final prefixContent = build('0/0');
      final contexts = [
        prefixContent,
        baseContent,
        annotationContent,
        build('0/2'),
      ];
      final start = prefixContent.projection.text.length;
      final end =
          start +
          baseContent.projection.text.length +
          annotationContent.projection.text.length;
      return (
        content: ForumBodyInlineSpanContent.compose(
          identity: document.identity,
          path: '0',
          fontRevision: styles.fontRevision,
          styleRevision: styles.resolverRevision,
          style: styles.byPath['0']!,
          contexts: contexts,
          atomicRanges: [(startUtf16: start, endUtf16: end)],
        ),
        base: baseContent,
        annotation: annotationContent,
        contexts: contexts,
      );
    } finally {
      cursor.close();
    }
  } finally {
    flow.close();
  }
}
