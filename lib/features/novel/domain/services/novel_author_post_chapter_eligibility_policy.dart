import 'package:html/parser.dart' as html_parser;
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

abstract interface class NovelAuthorPostChapterEligibilityPolicy {
  bool isEligible({required ThreadPost post, required String rawHtml});
}

/// Rejects publisher replies that quote another forum floor. A Discuz quote
/// reply is conversation around the work, not a novel chapter.
class DiscuzNovelAuthorPostChapterEligibilityPolicy
    implements NovelAuthorPostChapterEligibilityPolicy {
  const DiscuzNovelAuthorPostChapterEligibilityPolicy();

  static final RegExp _attributedQuote = RegExp(
    r'(?:发表于|發表於)\s*\d{4}[-/.年]\d{1,2}[-/.月]\d{1,2}',
  );

  @override
  bool isEligible({required ThreadPost post, required String rawHtml}) {
    if (post.isFirst || post.number == 1 || rawHtml.trim().isEmpty) {
      return true;
    }
    final fragment = html_parser.parseFragment(rawHtml);
    if (fragment.querySelector('.quote') != null) {
      return false;
    }
    return !fragment
        .querySelectorAll('blockquote')
        .map((element) => element.text.trim())
        .any(_attributedQuote.hasMatch);
  }
}
