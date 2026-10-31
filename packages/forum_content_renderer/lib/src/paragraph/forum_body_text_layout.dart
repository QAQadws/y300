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
