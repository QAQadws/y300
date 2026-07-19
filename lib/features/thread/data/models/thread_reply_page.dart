import 'package:y300/features/thread/data/models/thread_detail_models.dart';

/// One JSON `viewthread` page used by consumers that only need top-level posts.
///
/// The model intentionally keeps the complete [ThreadPost] values. Consumers
/// such as the comic comment loader decide which fields and interactions are
/// appropriate for their surface.
class ThreadReplyPage {
  const ThreadReplyPage({
    required this.tid,
    required this.page,
    required this.perPage,
    required this.replyCount,
    required this.posts,
    this.lastPage,
    this.hasNext,
  });

  factory ThreadReplyPage.fromThreadDetail(ThreadDetailData detail) {
    return ThreadReplyPage(
      tid: detail.tid,
      page: detail.currentPage,
      perPage: detail.perPage,
      replyCount: detail.replies,
      posts: List<ThreadPost>.unmodifiable(detail.posts),
      lastPage: detail.lastPage,
      hasNext: detail.nextPageUrl != null || detail.hasMore,
    );
  }

  final String tid;
  final int page;
  final int perPage;

  /// Discuz `replies` excludes the first post.
  final int replyCount;
  final List<ThreadPost> posts;
  final int? lastPage;
  final bool? hasNext;

  int get expectedPageCount {
    final pageSize = perPage <= 0 ? 20 : perPage;
    final totalPosts = (replyCount < 0 ? 0 : replyCount) + 1;
    final pages = (totalPosts + pageSize - 1) ~/ pageSize;
    return pages < 1 ? 1 : pages;
  }
}
