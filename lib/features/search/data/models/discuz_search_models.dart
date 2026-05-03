class DiscuzSearchResultItem {
  const DiscuzSearchResultItem({
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

class DiscuzSearchResult {
  const DiscuzSearchResult({
    required this.items,
  });

  final List<DiscuzSearchResultItem> items;
}

class SearchRateLimitResult {
  const SearchRateLimitResult.allowed() : isAllowed = true, retryAfter = Duration.zero;

  const SearchRateLimitResult.blocked(this.retryAfter) : isAllowed = false;

  final bool isAllowed;
  final Duration retryAfter;
}

