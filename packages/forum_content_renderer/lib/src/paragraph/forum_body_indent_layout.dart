import 'package:flutter/painting.dart';
import 'package:html_pagination_core/html_pagination_core.dart';

import '../inline/forum_body_native_space_span.dart';
import 'forum_body_first_line_indent.dart';
import 'forum_body_paragraph_geometry.dart';
import 'forum_body_paragraph_painter.dart';

/// Shape the real paragraph first. A source-free row or actual first-row
/// overflow can trigger fitting; only a reader request can be reduced. Three
/// layouts at most retain the same painter, dimensions, map and ownership.
ForumBodyFirstLineIndentGeometry layoutForumBodyFirstLineIndent({
  required TextPainter painter,
  required TextSpan body,
  required HtmlInlineTextProjection projection,
  required double width,
  required double requestedAdvance,
  required bool canReduce,
}) => layoutForumBodyFirstLineIndentWithPainter(
  painter: ForumBodyBorrowedTextPainter(painter),
  body: body,
  projection: projection,
  width: width,
  requestedAdvance: requestedAdvance,
  canReduce: canReduce,
);

ForumBodyFirstLineIndentGeometry layoutForumBodyFirstLineIndentWithPainter({
  required ForumBodyParagraphPainter painter,
  required TextSpan body,
  required HtmlInlineTextProjection projection,
  required double width,
  required double requestedAdvance,
  required bool canReduce,
}) {
  var advance = requestedAdvance > width ? width : requestedAdvance;
  var passes = 0;
  void shape() {
    painter.text = TextSpan(
      style: body.style,
      children: [
        ForumBodyNativeSpaceSpan.nonBreaking(advance),
        ...body.children!,
      ],
    );
    painter.layout(minWidth: width, maxWidth: width);
    passes++;
    validateForumBodyFirstLineIndentAdvanceWithPainter(
      painter,
      projection.enginePrefix.length,
      advance,
    );
  }

  bool prefixOnly() {
    final end = painter.lineBoundaryForRow(0, 0).range.end;
    // The paint range excludes a real hard separator. Such an intentionally
    // empty source row still owns the separator and must not be fitted away.
    if (end < projection.engineText.length &&
        forumBodyIsDisplayLineBreak(projection.engineText.codeUnitAt(end))) {
      return false;
    }
    return projection.displayOffsetAtEngineUtf16(end) == 0;
  }

  bool needsFit() =>
      prefixOnly() ||
      (advance > 0 && painter.computeLineMetrics().first.width > width + 1e-3);

  shape();
  if (needsFit() && canReduce) {
    final prefix = projection.enginePrefix.length;
    final firstAtom = projection.atoms.isEmpty ? null : projection.atoms.first;
    final end = firstAtom?.displayStartUtf16 == 0
        ? firstAtom!.engineEndUtf16
        : projection
              .engineAtDisplayUtf16(projection.display.firstGrapheme!.length)
              .engineUtf16;
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: prefix, extentOffset: end),
    );
    var firstWidth = 0.0;
    for (final box in boxes) {
      if (!box.left.isFinite || !box.right.isFinite || box.right < box.left) {
        throw const ForumBodyParagraphLayoutException(
          ForumBodyParagraphLayoutFailure.indent,
        );
      }
      firstWidth += box.right - box.left;
    }
    final available = width - firstWidth;
    // An opaque unit/cluster can need the complete width. If native wrapping
    // still rejects the measured fit, one final zero-advance layout gives text
    // the whole first row; this never changes fonts, source or reading mode.
    advance = available <= 0
        ? 0
        : available < advance
        ? available
        : advance / 2;
    shape();
    if (needsFit() && advance > 0) {
      advance = 0;
      shape();
    }
  }
  if (prefixOnly()) {
    throw const ForumBodyParagraphLayoutException(
      ForumBodyParagraphLayoutFailure.indent,
    );
  }
  return ForumBodyFirstLineIndentGeometry(
    requestedAdvance: requestedAdvance,
    appliedAdvance: advance,
    layoutPasses: passes,
  );
}
