import 'package:flutter/painting.dart';

import '../style/forum_body_length.dart';
import '../style/forum_body_style_options.dart';
import 'forum_body_paragraph_content.dart';
import 'forum_body_paragraph_geometry.dart';

/// Resolve one current request, never a source edit or a second reader scale.
double resolveForumBodyFirstLineIndent(
  ForumBodyParagraphContent content,
  double width,
  Map<double, double> scales,
) => resolveForumBodyFirstLineIndentValue(
  style: content.style,
  displayText: content.projection.text,
  appliesFirstLineIndent: content.appliesFirstLineIndent,
  layoutMode: content.layoutMode,
  width: width,
  scales: scales,
);

/// Pure prefix presence, separate from request-dependent numeric admission.
/// Invalid lengths are still rejected before shaping or warm-cache lookup.
bool forumBodyHasFirstLineIndent({
  required ForumBodyResolvedStyle style,
  required String displayText,
  required bool appliesFirstLineIndent,
  required ForumBodyParagraphLayoutMode layoutMode,
}) =>
    appliesFirstLineIndent &&
    layoutMode == ForumBodyParagraphLayoutMode.wrap &&
    displayText.isNotEmpty &&
    style.indent.value > 0 &&
    !(style.indentFromReader && _leadingSpace.hasMatch(displayText));

double resolveForumBodyFirstLineIndentValue({
  required ForumBodyResolvedStyle style,
  required String displayText,
  required bool appliesFirstLineIndent,
  required ForumBodyParagraphLayoutMode layoutMode,
  required double width,
  required Map<double, double> scales,
}) {
  if (!appliesFirstLineIndent ||
      layoutMode == ForumBodyParagraphLayoutMode.intrinsicSingleLine ||
      displayText.isEmpty ||
      style.indent.value == 0) {
    return 0;
  }
  final length = style.indent;
  if (layoutMode != ForumBodyParagraphLayoutMode.wrap ||
      !length.value.isFinite ||
      length.value < 0 ||
      length.unit == ForumBodyLengthUnit.auto ||
      length.unit == ForumBodyLengthUnit.rem) {
    throw const ForumBodyParagraphLayoutException(
      ForumBodyParagraphLayoutFailure.indent,
    );
  }
  // Respect a real preserved horizontal indent without deleting or rewriting
  // it. Explicit author CSS remains its own intent, even before such spaces.
  if (style.indentFromReader && _leadingSpace.hasMatch(displayText)) {
    return 0;
  }
  final size = style.textStyle.fontSize!;
  final advance = length.resolve(
    fontSize: style.indentFromReader ? scales[size]! : size,
    rootFontSize: size,
    reference: width,
  );
  // A requested nonzero prefix must remain present in the native span. Treat
  // numeric underflow as unrepresentable instead of shifting only its map.
  if (!advance.isFinite || advance <= 0 || advance >= width) {
    throw const ForumBodyParagraphLayoutException(
      ForumBodyParagraphLayoutFailure.indent,
    );
  }
  return advance;
}

void validateForumBodyFirstLineIndentAdvance(
  TextPainter painter,
  int prefixLength,
  double advance,
) {
  final boxes = painter.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: prefixLength),
  );
  var actual = 0.0;
  for (final box in boxes) {
    if (!box.left.isFinite ||
        !box.right.isFinite ||
        !box.top.isFinite ||
        !box.bottom.isFinite ||
        (box.bottom - box.top).abs() > 1e-3 ||
        box.right < box.left) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.indent,
      );
    }
    actual += box.right - box.left;
  }
  // Verify the bundled zero-ink font ABI instead of trusting a font name or
  // allowing native fallback metrics to alter an otherwise readable page.
  if (boxes.isEmpty || (actual - advance).abs() > 1e-3) {
    throw const ForumBodyParagraphLayoutException(
      ForumBodyParagraphLayoutFailure.indent,
    );
  }
}

final _leadingSpace = RegExp(
  r'^[\u0009\u0020\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000]',
);
