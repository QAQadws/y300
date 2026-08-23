import 'package:y300/core/data_source/data_read_contract.dart';

enum ForumSearchScope { allForums, currentForum }

final class ForumSearchQuery {
  const ForumSearchQuery({
    required this.keyword,
    this.scope = ForumSearchScope.allForums,
    this.forumId,
  });

  final String keyword;
  final ForumSearchScope scope;
  final String? forumId;

  String get normalizedKeyword => keyword.trim();

  String? get normalizedForumId {
    final value = forumId?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  ForumSearchQuery normalized() {
    return ForumSearchQuery(
      keyword: normalizedKeyword,
      scope: scope,
      forumId: normalizedForumId,
    );
  }

  ForumSearchQuery copyWith({
    String? keyword,
    ForumSearchScope? scope,
    String? forumId,
    bool clearForumId = false,
  }) {
    return ForumSearchQuery(
      keyword: keyword ?? this.keyword,
      scope: scope ?? this.scope,
      forumId: clearForumId ? null : (forumId ?? this.forumId),
    );
  }
}

final class ForumSearchPageIdentity {
  const ForumSearchPageIdentity({required this.token, required this.page});

  final String token;
  final int page;

  @override
  bool operator ==(Object other) {
    return other is ForumSearchPageIdentity &&
        other.token == token &&
        other.page == page;
  }

  @override
  int get hashCode => Object.hash(token, page);
}

final class ForumSearchTopicSummary {
  const ForumSearchTopicSummary({
    required this.tid,
    required this.title,
    this.forumId,
    this.forumName,
    this.authorName,
    this.publishedAtText,
  });

  final String tid;
  final String title;
  final String? forumId;
  final String? forumName;
  final String? authorName;
  final String? publishedAtText;
}

final class ForumSearchPagination {
  const ForumSearchPagination({
    required this.currentPage,
    this.nextPage,
    this.precision = PaginationPrecision.unknown,
  });

  final int currentPage;
  final ForumSearchPageIdentity? nextPage;
  final PaginationPrecision precision;
}

final class ForumSearchData {
  const ForumSearchData({
    required this.query,
    required this.topics,
    required this.pagination,
  });

  final ForumSearchQuery query;
  final List<ForumSearchTopicSummary> topics;
  final ForumSearchPagination pagination;
}
