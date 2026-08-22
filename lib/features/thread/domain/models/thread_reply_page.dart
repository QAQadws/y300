/// A source-neutral top-level reply entry used by paged reply consumers.
final class ThreadReplyEntry {
  const ThreadReplyEntry({
    required this.pid,
    required this.authorId,
    required this.authorName,
    required this.dateline,
    required this.floorNumber,
    required this.isFirst,
    required this.rawMessage,
  });

  final String pid;
  final String authorId;
  final String authorName;
  final String dateline;
  final int floorNumber;
  final bool isFirst;
  final String rawMessage;
}

/// One paged reply document without leaking the full thread source model.
final class ThreadReplyPage {
  const ThreadReplyPage({
    required this.tid,
    required this.page,
    required this.perPage,
    required this.replyCount,
    required this.posts,
    this.lastPage,
    this.hasNext,
  });

  final String tid;
  final int page;
  final int perPage;

  /// Discuz `replies` excludes the first post.
  final int replyCount;
  final List<ThreadReplyEntry> posts;
  final int? lastPage;
  final bool? hasNext;

  int get expectedPageCount {
    final pageSize = perPage <= 0 ? 20 : perPage;
    final totalPosts = (replyCount < 0 ? 0 : replyCount) + 1;
    final pages = (totalPosts + pageSize - 1) ~/ pageSize;
    return pages < 1 ? 1 : pages;
  }
}
