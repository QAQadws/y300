import '../style/forum_body_style_options.dart';
import 'forum_body_paragraph_geometry.dart';

/// Negative tracking can paint beyond either line edge even when native line
/// metrics fit. RTL alignment can expose a full tracking advance, not just the
/// half-advance seen at an LTR edge. Tracking remains in logical pixels.
/// Reserve both edges before wrapping; never clamp the resulting glyph boxes.
double forumBodyHorizontalTextInset(Iterable<ForumBodyResolvedStyle> styles) {
  var inset = 0.0;
  for (final style in styles) {
    final spacing = style.textStyle.letterSpacing ?? 0;
    if (!spacing.isFinite) {
      throw const ForumBodyParagraphLayoutException(
        ForumBodyParagraphLayoutFailure.width,
      );
    }
    final overhang = -spacing;
    if (overhang > inset) inset = overhang;
  }
  return inset;
}

double forumBodyInnerTextWidth(double width, double inset) {
  final inner = width - 2 * inset;
  if (!inner.isFinite || inner <= 0) {
    throw const ForumBodyParagraphLayoutException(
      ForumBodyParagraphLayoutFailure.width,
    );
  }
  return inner;
}
