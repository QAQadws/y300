import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Paint bounds and logical code-unit coverage are distinct native facts.
/// Flutter's older boundary API only supplies paint bounds; its adapter leaves
/// separator normalization to the existing extraction path.
typedef ForumBodyParagraphLineRange = ({
  TextRange range,
  int? coverageEndUtf16,
});

/// The small native port shared by first-line fitting and row extraction.
/// A borrowed Flutter painter and the owned paragraph backend share algorithms,
/// without depending on TextPainter's private paragraph/cache implementation.
abstract interface class ForumBodyParagraphPainter {
  set text(TextSpan value);
  void layout({double minWidth = 0, double maxWidth = double.infinity});
  List<ui.LineMetrics> computeLineMetrics();
  ForumBodyParagraphLineRange lineBoundaryForRow(
    int lineNumber,
    int startUtf16,
  );
  List<TextBox> getBoxesForSelection(TextSelection selection);
}

final class ForumBodyBorrowedTextPainter implements ForumBodyParagraphPainter {
  const ForumBodyBorrowedTextPainter(this.painter);
  final TextPainter painter;
  @override
  set text(TextSpan value) => painter.text = value;
  @override
  void layout({double minWidth = 0, double maxWidth = double.infinity}) =>
      painter.layout(minWidth: minWidth, maxWidth: maxWidth);
  @override
  List<ui.LineMetrics> computeLineMetrics() => painter.computeLineMetrics();
  @override
  ForumBodyParagraphLineRange lineBoundaryForRow(
    int lineNumber,
    int startUtf16,
  ) => (
    range: painter.getLineBoundary(TextPosition(offset: startUtf16)),
    coverageEndUtf16: null,
  );
  @override
  List<TextBox> getBoxesForSelection(TextSelection selection) =>
      painter.getBoxesForSelection(selection);
}
