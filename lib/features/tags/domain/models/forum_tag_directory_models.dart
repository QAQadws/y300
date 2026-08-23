final class ForumTagDirectoryQuery {
  const ForumTagDirectoryQuery({required this.tagId, this.page = 1});

  final String tagId;
  final int page;

  ForumTagDirectoryQuery copyWith({String? tagId, int? page}) {
    return ForumTagDirectoryQuery(
      tagId: tagId ?? this.tagId,
      page: page ?? this.page,
    );
  }
}

final class ForumTagDirectoryData {
  const ForumTagDirectoryData({
    required this.tag,
    required this.topics,
    required this.pagination,
  });

  final ForumTagIdentity tag;
  final List<ForumTagTopicSummary> topics;
  final ForumTagPagination pagination;
}

final class ForumTagIdentity {
  const ForumTagIdentity({required this.id, this.name});

  final String id;
  final String? name;
}

final class ForumTagTopicSummary {
  const ForumTagTopicSummary({
    required this.tid,
    required this.title,
    this.forumId,
    this.forumName,
    this.authorId,
    this.authorName,
    this.createdAt,
    this.replyCount,
    this.viewCount,
    this.lastPosterName,
    this.lastPostAt,
    this.hasImageAttachment,
    this.hasAttachment,
  });

  final String tid;
  final String title;
  final String? forumId;
  final String? forumName;
  final String? authorId;
  final String? authorName;
  final String? createdAt;
  final int? replyCount;
  final int? viewCount;
  final String? lastPosterName;
  final String? lastPostAt;
  final bool? hasImageAttachment;
  final bool? hasAttachment;
}

final class ForumTagPagination {
  const ForumTagPagination({
    required this.currentPage,
    this.totalPages,
    this.hasPrevious,
    this.hasNext,
  });

  final int currentPage;
  final int? totalPages;
  final bool? hasPrevious;
  final bool? hasNext;
}
