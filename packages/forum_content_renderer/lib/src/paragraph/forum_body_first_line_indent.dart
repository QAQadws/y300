import '../style/forum_body_length.dart';
import 'forum_body_paragraph_content.dart';
import 'forum_body_paragraph_geometry.dart';

/// Resolve one current request, never a source edit or a second reader scale.
double resolveForumBodyFirstLineIndent(
  ForumBodyParagraphContent content,
  double width,
  Map<double, double> scales,
) {
  if (!content.appliesFirstLineIndent ||
      content.layoutMode == ForumBodyParagraphLayoutMode.intrinsicSingleLine ||
      content.projection.text.isEmpty ||
      content.style.indent.value == 0) {
    return 0;
  }
  final style = content.style;
  final length = style.indent;
  if (content.layoutMode != ForumBodyParagraphLayoutMode.wrap ||
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
  if (style.indentFromReader &&
      _leadingSpace.hasMatch(content.projection.text)) {
    return 0;
  }
  final size = style.textStyle.fontSize!;
  final advance = length.resolve(
    fontSize: style.indentFromReader ? scales[size]! : size,
    rootFontSize: size,
    reference: width,
  );
  if (!advance.isFinite || advance < 0 || advance >= width) {
    throw const ForumBodyParagraphLayoutException(
      ForumBodyParagraphLayoutFailure.indent,
    );
  }
  return advance;
}

final _leadingSpace = RegExp(
  r'^[\u0009\u0020\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000]',
);
