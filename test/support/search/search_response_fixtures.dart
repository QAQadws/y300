/// Transport-shaped fixtures used by the comic refresh tests.
///
/// Production code consumes [ForumSearchTopicSummary] directly; these small
/// values keep the large refresh fixture set readable without reintroducing a
/// legacy search service into `lib`.
final class SearchTestTopic {
  const SearchTestTopic({
    required this.tid,
    required this.title,
    required this.url,
    required this.fid,
    this.author,
    this.timeText,
  });

  final String tid;
  final String title;
  final String url;
  final String fid;
  final String? author;
  final String? timeText;
}

final class SearchTestResponse {
  const SearchTestResponse({
    required this.items,
    required this.rateLimited,
    this.retryAfter = Duration.zero,
  });

  final List<SearchTestTopic> items;
  final bool rateLimited;
  final Duration retryAfter;
}
