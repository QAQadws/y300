import 'package:y300/features/comic/domain/services/title/comic_title_rules.dart';

typedef ComicDuplicateMetadataKey = ({String title, String author});

/// Matches effective, already parsed metadata, including user corrections.
class ComicDuplicateMetadataMatcher {
  const ComicDuplicateMetadataMatcher();

  ComicDuplicateMetadataKey? keyFor({
    required String? title,
    required String? author,
  }) {
    if (title == null || author == null) {
      return null;
    }
    final normalizedTitle = ComicTitleRules.normalizeForMatching(title);
    final normalizedAuthor = ComicTitleRules.normalizeForMatching(author);
    if (normalizedTitle.isEmpty || normalizedAuthor.isEmpty) {
      return null;
    }
    // Keep full names: search-keyword clipping or reparsing a book name could
    // collapse distinct works. Missing authors are never matching evidence.
    return (title: normalizedTitle, author: normalizedAuthor);
  }
}
