final class FavoriteForumDirectoryQuery {
  const FavoriteForumDirectoryQuery();
}

final class FavoriteForumDirectoryData {
  const FavoriteForumDirectoryData({required this.items});

  final List<FavoriteForumEntry> items;
}

final class FavoriteForumEntry {
  const FavoriteForumEntry({
    required this.fid,
    required this.title,
    this.remoteFavoriteId,
    this.description,
    this.threadCount,
    this.postCount,
    this.todayPostCount,
  });

  final String fid;
  final String title;
  final String? remoteFavoriteId;
  final String? description;
  final int? threadCount;
  final int? postCount;
  final int? todayPostCount;
}

final class FavoriteThreadDirectoryQuery {
  const FavoriteThreadDirectoryQuery({this.page = 1});

  final int page;
}

final class FavoriteThreadDirectoryData {
  const FavoriteThreadDirectoryData({
    required this.items,
    required this.pagination,
  });

  final List<FavoriteThreadReference> items;
  final FavoriteThreadPagination pagination;
}

final class FavoriteThreadReference {
  const FavoriteThreadReference({
    required this.tid,
    required this.title,
    this.remoteFavoriteId,
    this.description,
    this.authorName,
    this.replyCount,
    this.favoritedAt,
  });

  final String tid;
  final String title;
  final String? remoteFavoriteId;
  final String? description;
  final String? authorName;
  final int? replyCount;
  final DateTime? favoritedAt;
}

final class FavoriteThreadPagination {
  const FavoriteThreadPagination({
    required this.currentPage,
    this.pageSize,
    this.totalItems,
    this.totalPages,
    this.hasPrevious,
    this.hasNext,
  });

  final int currentPage;
  final int? pageSize;
  final int? totalItems;
  final int? totalPages;
  final bool? hasPrevious;
  final bool? hasNext;
}
