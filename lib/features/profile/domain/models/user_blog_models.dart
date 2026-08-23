enum UserBlogFeedScope { friends, self, public }

enum UserBlogOrder { latest, recommended }

final class UserBlogDirectoryQuery {
  const UserBlogDirectoryQuery({
    required this.scope,
    this.order,
    this.page = 1,
  });

  const UserBlogDirectoryQuery.public({
    this.order = UserBlogOrder.latest,
    this.page = 1,
  }) : scope = UserBlogFeedScope.public;

  const UserBlogDirectoryQuery.friends({this.page = 1})
    : scope = UserBlogFeedScope.friends,
      order = null;

  const UserBlogDirectoryQuery.self({this.page = 1})
    : scope = UserBlogFeedScope.self,
      order = null;

  final UserBlogFeedScope scope;
  final UserBlogOrder? order;
  final int page;

  UserBlogDirectoryQuery copyWith({
    UserBlogFeedScope? scope,
    UserBlogOrder? order,
    int? page,
    bool clearOrder = false,
  }) {
    return UserBlogDirectoryQuery(
      scope: scope ?? this.scope,
      order: clearOrder ? null : (order ?? this.order),
      page: page ?? this.page,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is UserBlogDirectoryQuery &&
        other.scope == scope &&
        other.order == order &&
        other.page == page;
  }

  @override
  int get hashCode => Object.hash(scope, order, page);
}

final class UserBlogDirectoryData {
  const UserBlogDirectoryData({
    required this.scope,
    required this.order,
    required this.items,
    required this.pagination,
  });

  final UserBlogFeedScope scope;
  final UserBlogOrder? order;
  final List<UserBlogSummary> items;
  final UserBlogPagination pagination;
}

final class UserBlogSummary {
  const UserBlogSummary({
    required this.blogId,
    required this.ownerUserId,
    required this.title,
    this.authorName,
    this.excerpt,
    this.avatarUrl,
    this.publishedAtText,
  });

  final String blogId;
  final String ownerUserId;
  final String title;
  final String? authorName;
  final String? excerpt;
  final String? avatarUrl;
  final String? publishedAtText;
}

final class UserBlogPagination {
  const UserBlogPagination({
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

final class UserBlogDetailQuery {
  const UserBlogDetailQuery({
    required this.ownerUserId,
    required this.blogId,
  });

  final String ownerUserId;
  final String blogId;

  @override
  bool operator ==(Object other) {
    return other is UserBlogDetailQuery &&
        other.ownerUserId == ownerUserId &&
        other.blogId == blogId;
  }

  @override
  int get hashCode => Object.hash(ownerUserId, blogId);
}

final class UserBlogDetailData {
  const UserBlogDetailData({
    required this.blogId,
    required this.ownerUserId,
    required this.title,
    required this.bodyHtml,
    required this.comments,
    this.authorName,
    this.avatarUrl,
    this.publishedAtText,
    this.viewCount,
    this.commentCount,
    this.commentsOpen,
  });

  final String blogId;
  final String ownerUserId;
  final String title;
  final String bodyHtml;
  final String? authorName;
  final String? avatarUrl;
  final String? publishedAtText;
  final int? viewCount;
  final int? commentCount;
  final List<UserBlogComment> comments;
  final bool? commentsOpen;
}

final class UserBlogComment {
  const UserBlogComment({
    required this.commentId,
    required this.authorName,
    required this.bodyHtml,
    this.authorUserId,
    this.avatarUrl,
    this.publishedAtText,
  });

  final String commentId;
  final String authorName;
  final String bodyHtml;
  final String? authorUserId;
  final String? avatarUrl;
  final String? publishedAtText;
}
