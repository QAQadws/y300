import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

/// Source-local native text geometry shared by standalone paragraphs and band
/// children. It exposes no virtual band rows, native painter or owner disposal.
/// Ownership stays with the typed cache lease, including prepared paint costs.
abstract interface class ForumBodyTextLayout {
  bool get isDisposed;
  bool get isPaintPrepared;
  double get width;
  double get height;

  /// Alphabetic baseline of the first actual text line, in local coordinates.
  double get alphabeticBaseline;
  HtmlDisplayTextProjection get projection;
  void paint(Canvas canvas, Offset offset);
  HtmlProjectedSourcePosition sourceAt(Offset offset);
  List<TextBox> selectionBoxes(int startUtf16, int endUtf16);
}

/// Includes the native frame and actual font overhang under tight line-height.
/// This only queries an existing layout; it never shapes or prepares paint.
Rect forumBodyTextLayoutBounds(ForumBodyTextLayout layout) {
  if (layout.isDisposed) throw StateError('Text layout is retired');
  var bounds = Rect.fromLTWH(0, 0, layout.width, layout.height);
  for (final box in layout.selectionBoxes(0, layout.projection.text.length)) {
    bounds = bounds.expandToInclude(box.toRect());
  }
  return bounds;
}
