import '../paragraph/forum_body_paragraph_content.dart';
import '../style/forum_body_style_options.dart';

/// Whitespace windows keep the original projection/affinity and may only end
/// at a real grapheme boundary. They never create another source context.
ForumBodyParagraphContent trimForumBodyInlineText(
  ForumBodyParagraphContent context, {
  required bool leading,
  required bool trailing,
}) {
  var start = 0;
  var end = context.projection.text.length;
  if (leading && forumBodyInlineHasCollapsibleEdge(context, leading: true)) {
    start++;
  }
  if (trailing &&
      end > start &&
      forumBodyInlineHasCollapsibleEdge(context, leading: false)) {
    end--;
  }
  if (start == 0 && end == context.projection.text.length) return context;
  return windowForumBodyInlineText(context, start, end);
}

ForumBodyParagraphContent windowForumBodyInlineText(
  ForumBodyParagraphContent context,
  int start,
  int end,
) {
  if (context.projection.sourceAtUtf16(start).displayUtf16 != start ||
      context.projection.sourceAtUtf16(end).displayUtf16 != end) {
    throw ForumBodyParagraphInputException(
      ForumBodyParagraphInputFailure.structure,
      context.path,
    );
  }
  return context.displayWindow(startUtf16: start, endUtf16: end);
}

bool forumBodyInlineHasCollapsibleEdge(
  ForumBodyParagraphContent context, {
  required bool leading,
}) {
  final projection = context.projection;
  if (projection.text.isEmpty) return false;
  final part = leading ? projection.parts.first : projection.parts.last;
  final index = leading ? 0 : projection.text.length - 1;
  final mode = context.runs[part.runIndex].style.whiteSpace;
  return projection.text.codeUnitAt(index) == 32 &&
      (mode == ForumBodyWhiteSpace.normal ||
          mode == ForumBodyWhiteSpace.preLine);
}
