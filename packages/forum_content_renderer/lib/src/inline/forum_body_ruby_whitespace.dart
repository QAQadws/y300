import '../paragraph/forum_body_paragraph_content.dart';

// CSS Text leaves this contextual transformation to the UA. Keep a conservative
// Han/Kana rule, including their shared punctuation; Latin, Hangul and ambiguous
// edges keep the space. Actual source LF provenance is checked by the core port.
final _hanKana = RegExp(
  r'^[\p{Script_Extensions=Han}\p{Script_Extensions=Hiragana}\p{Script_Extensions=Katakana}]',
  unicode: true,
);
final _mark = RegExp(r'^\p{M}', unicode: true);

ForumBodyParagraphContent resolveForumBodyRubyGapWhitespace({
  required ForumBodyParagraphContent gap,
  required ForumBodyParagraphContent previous,
  required ForumBodyParagraphContent next,
}) => gap.resolveWhitespaceSegmentBreaks(
  precedingGrapheme: previous.projection.lastGrapheme,
  followingGrapheme: next.projection.firstGrapheme,
  shouldRemove: (before, after) =>
      before != null &&
      after != null &&
      _hanKana.hasMatch(before) &&
      _hanKana.hasMatch(after) &&
      !_mark.hasMatch(before) &&
      !_mark.hasMatch(after),
);
