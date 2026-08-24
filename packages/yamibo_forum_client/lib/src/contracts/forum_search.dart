/// Query, pagination, and result contracts for forum search.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';

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
    final v = forumId?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  ForumSearchQuery normalized() => ForumSearchQuery(
    keyword: normalizedKeyword,
    scope: scope,
    forumId: normalizedForumId,
  );
}

final class ForumSearchPageIdentity {
  const ForumSearchPageIdentity({required this.token, required this.page});
  final String token;
  final int page;
  @override
  bool operator ==(Object other) =>
      other is ForumSearchPageIdentity &&
      other.token == token &&
      other.page == page;
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

enum ForumSearchCapability {
  stableTopicIdentity,
  orderedTopics,
  topicTitle,
  topicForum,
  topicAuthor,
  topicPublishedAt,
  directionalPagination,
  searchContinuation,
}

final class ForumSearchSourceCapabilities {
  const ForumSearchSourceCapabilities({
    required this.values,
    required this.paginationPrecision,
  });
  final DataCapabilitySet<ForumSearchCapability> values;
  final PaginationPrecision paginationPrecision;
  bool supports(ForumSearchCapability c) => values.supports(c);
  ForumSearchReadCapabilities toReadCapabilities() =>
      ForumSearchReadCapabilities(
        values: values,
        paginationPrecision: paginationPrecision,
      );
}

final class ForumSearchReadCapabilities {
  const ForumSearchReadCapabilities({
    required this.values,
    required this.paginationPrecision,
  });
  final DataCapabilitySet<ForumSearchCapability> values;
  final PaginationPrecision paginationPrecision;
  bool supports(ForumSearchCapability c) => values.supports(c);
  ForumSearchReadCapabilities intersect(ForumSearchReadCapabilities o) =>
      ForumSearchReadCapabilities(
        values: values.intersect(o.values),
        paginationPrecision: paginationPrecision.intersect(
          o.paginationPrecision,
        ),
      );
}

abstract interface class ForumSearchRepository {
  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>> load(
    ForumSearchQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>>
  loadNextPage(
    ForumSearchQuery query,
    ForumSearchPageIdentity page, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
