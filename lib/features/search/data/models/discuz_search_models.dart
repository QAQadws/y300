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

enum DiscuzSearchScope {
  forum,
  curForum,
}

class DiscuzSearchContext {
  const DiscuzSearchContext._({
    required this.scope,
    this.srhfid,
  });

  const DiscuzSearchContext.forum()
    : this._(
        scope: DiscuzSearchScope.forum,
      );

  const DiscuzSearchContext.curForum({
    required String srhfid,
  }) : this._(
         scope: DiscuzSearchScope.curForum,
         srhfid: srhfid,
       );

  final DiscuzSearchScope scope;
  final String? srhfid;
}

class DiscuzSearchResult {
  const DiscuzSearchResult({
    required this.items,
    this.nextPageUrl,
  });

  final List<DiscuzSearchResultItem> items;
  final String? nextPageUrl;
}

class SearchRateLimitResult {
  const SearchRateLimitResult.allowed() : isAllowed = true, retryAfter = Duration.zero;

  const SearchRateLimitResult.blocked(this.retryAfter) : isAllowed = false;

  final bool isAllowed;
  final Duration retryAfter;
}
