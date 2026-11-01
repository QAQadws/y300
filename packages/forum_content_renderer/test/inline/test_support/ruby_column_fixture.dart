import 'package:flutter/painting.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

/// Independent source contexts for an already grouped, multi-level column.
List<ForumBodyParagraphContent> rubyColumnInput({
  String base = 'AB',
  double baseSize = 20,
  List<(String, double)> annotations = const [('xy', 10), ('z', 15), ('q', 5)],
  double lineHeight = 1,
}) {
  final parts = [(base, baseSize), ...annotations];
  final document = const ForumBodyParser().parse(
    html:
        '<p>${parts.map((part) => '<span style="font-size:${part.$2}px;line-height:$lineHeight">${part.$1}</span>').join()}</p>',
    sourceId: 'ruby-column',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(fontFamily: 'Ahem', fontSize: 20, height: 1),
      fontRevision: 'ahem',
      linkColor: const Color(0xff0000ff),
    ),
  );
  return [
    for (var i = 0; i < parts.length; i++)
      const ForumBodyParagraphContentBuilder().build(
        document: document,
        styles: styles,
        path: '0/$i',
        layoutMode: ForumBodyParagraphLayoutMode.intrinsicSingleLine,
      ),
  ];
}
