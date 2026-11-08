import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Geometry of hard-break paragraphs within one retained RichText. The original
/// spans, shaping and layout stay intact; these local UTF-16 selections are
/// renderer coordinates and must never be used as persisted reading anchors.
class ForumHtmlParagraphMetrics extends SingleChildRenderObjectWidget {
  const ForumHtmlParagraphMetrics({super.key, required super.child});

  @override
  RenderForumHtmlParagraphMetrics createRenderObject(BuildContext context) =>
      RenderForumHtmlParagraphMetrics();
}

class RenderForumHtmlParagraphMetrics extends RenderProxyBox {
  List<Rect> _paragraphs = const [];
  List<Rect> get paragraphs => _paragraphs;

  @override
  void performLayout() {
    super.performLayout();
    RenderParagraph? paragraph;
    void find(RenderObject object) {
      if (paragraph != null) return;
      if (object is RenderParagraph) {
        paragraph = object;
      } else {
        object.visitChildren(find);
      }
    }

    if (child != null) find(child!);
    final text = paragraph;
    if (text == null) {
      _paragraphs = const [];
      return;
    }
    final plain = text.text.toPlainText(includeSemanticsLabels: false);
    final transform = text.getTransformTo(this);
    final bounds = <Rect>[];
    var start = 0;
    for (var end = 0; end <= plain.length; end++) {
      if (end < plain.length && plain.codeUnitAt(end) != 10) continue;
      if (plain.substring(start, end).trim().isNotEmpty) {
        Rect? rect;
        for (final box in text.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end),
          boxHeightStyle: ui.BoxHeightStyle.includeLineSpacingMiddle,
        )) {
          rect = rect?.expandToInclude(box.toRect()) ?? box.toRect();
        }
        if (rect != null && rect.height > 0) {
          bounds.add(MatrixUtils.transformRect(transform, rect));
        }
      }
      start = end + 1;
    }
    _paragraphs = List.unmodifiable(bounds);
  }
}
