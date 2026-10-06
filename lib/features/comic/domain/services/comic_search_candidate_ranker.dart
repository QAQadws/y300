import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

class ComicSearchCandidate {
  const ComicSearchCandidate({
    required this.tid,
    required this.title,
    required this.searchIndex,
  });

  final String tid;
  final String title;
  final int searchIndex;
}

abstract class ComicSearchCandidateRanker {
  int get discoveryTopK;

  List<ComicSearchCandidate> rank({
    required List<ForumSearchTopicSummary> items,
  });
}

class DefaultComicSearchCandidateRanker implements ComicSearchCandidateRanker {
  const DefaultComicSearchCandidateRanker({this.discoveryTopK = 3});

  @override
  final int discoveryTopK;

  @override
  List<ComicSearchCandidate> rank({
    required List<ForumSearchTopicSummary> items,
  }) {
    final candidates = <ComicSearchCandidate>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      candidates.add(
        ComicSearchCandidate(
          tid: item.tid.trim(),
          title: item.title,
          searchIndex: index,
        ),
      );
    }
    // The server already matched the keyword. Keep the whole page for merging;
    // numeric TID order only determines which bodies are inspected first.
    candidates.sort((a, b) {
      final tidOrder = (int.tryParse(b.tid) ?? 0).compareTo(
        int.tryParse(a.tid) ?? 0,
      );
      if (tidOrder != 0) {
        return tidOrder;
      }
      return a.searchIndex.compareTo(b.searchIndex);
    });
    return candidates;
  }
}
