import 'package:flutter/painting.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

({ForumBodyParagraphContent base, ForumBodyParagraphContent annotation})
rubyPairInput({
  String base = 'AB',
  String annotation = 'xy',
  double annotationSize = 10,
  String direction = 'ltr',
  double baseLineHeight = 1,
  double annotationLineHeight = 1,
  String fontRevision = 'ahem',
  ForumBodyParagraphLayoutMode layoutMode =
      ForumBodyParagraphLayoutMode.intrinsicSingleLine,
}) {
  final document = const ForumBodyParser().parse(
    html:
        '<p><span dir="$direction" style="line-height:$baseLineHeight">$base</span><span style="font-size:${annotationSize}px;line-height:$annotationLineHeight">$annotation</span></p>',
    sourceId: 'ruby-group',
    conversionIdentity: 'none',
  );
  final styles = const ForumBodyStyleResolver().resolve(
    document,
    ForumBodyReaderStyle(
      textStyle: const TextStyle(
        fontFamily: 'Ahem',
        fontSize: 20,
        height: 1,
        color: Color(0xff000000),
      ),
      fontRevision: fontRevision,
      linkColor: const Color(0xff0000ff),
    ),
  );
  ForumBodyParagraphContent build(String path) =>
      const ForumBodyParagraphContentBuilder().build(
        document: document,
        styles: styles,
        path: path,
        layoutMode: layoutMode,
      );
  return (base: build('0/0'), annotation: build('0/1'));
}
