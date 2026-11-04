import '../style/forum_body_style_options.dart';
import 'forum_body_paragraph_geometry.dart';

/// Tracking can extend native glyph boxes beyond a fitted line's edge. Positive
/// tracking retains a trailing half-advance at fractional wrap boundaries; RTL
/// and negative tracking can expose a full advance. Tracking stays in logical pixels.
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
    final overhang = spacing.abs();
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
