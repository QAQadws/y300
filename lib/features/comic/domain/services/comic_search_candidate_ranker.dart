import 'package:y300/features/comic/domain/services/comic_refresh_keyword_resolver.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';

class ComicSearchCandidate {
  const ComicSearchCandidate({
    required this.item,
    required this.score,
    required this.searchIndex,
  });

  final DiscuzSearchResultItem item;
  final double score;
  final int searchIndex;
}

abstract class ComicSearchCandidateRanker {
  int get discoveryTopK;

  List<ComicSearchCandidate> rank({
    required String threadSubject,
    required ComicRefreshKeyword keyword,
    required List<DiscuzSearchResultItem> items,
  });
}

class DefaultComicSearchCandidateRanker
    implements ComicSearchCandidateRanker {
  const DefaultComicSearchCandidateRanker({
    this.discoveryTopK = 3,
  });

  @override
  final int discoveryTopK;

  @override
  List<ComicSearchCandidate> rank({
    required String threadSubject,
    required ComicRefreshKeyword keyword,
    required List<DiscuzSearchResultItem> items,
  }) {
    final currentScore = _scoreTitleSimilarity(threadSubject, keyword.value);
    final minScore = currentScore <= 0 ? 0.50 : currentScore - 0.25;
    final candidates = <ComicSearchCandidate>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final candidate = ComicSearchCandidate(
        item: item,
        score: _scoreTitleSimilarity(item.title, keyword.value),
        searchIndex: index,
      );
      if (candidate.score >= minScore) {
        candidates.add(candidate);
      }
    }
    candidates.sort((a, b) {
      final scoreOrder = b.score.compareTo(a.score);
      if (scoreOrder != 0) {
        return scoreOrder;
      }
      return a.searchIndex.compareTo(b.searchIndex);
    });
    return candidates;
  }

  double _scoreTitleSimilarity(String title, String keyword) {
    final normalizedTitle = title.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final normalizedKeyword = keyword.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (normalizedTitle.isEmpty || normalizedKeyword.isEmpty) {
      return 0;
    }
    if (normalizedTitle.contains(normalizedKeyword)) {
      return 1;
    }
    final overlap = normalizedKeyword.split('').where(normalizedTitle.contains).length;
    return overlap / normalizedKeyword.length;
  }
}
