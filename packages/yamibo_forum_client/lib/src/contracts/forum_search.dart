/// Query, pagination, and result contracts for forum search.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';

/// Values describing forum search scope.
enum ForumSearchScope {
  /// All forums.
  allForums,

  /// Current forum.
  currentForum,
}

/// Query parameters for forum search.
final class ForumSearchQuery {
  /// Creates a [ForumSearchQuery].
  const ForumSearchQuery({
    required this.keyword,
    this.scope = ForumSearchScope.allForums,
    this.forumId,
  });

  /// Keyword.
  final String keyword;

  /// Scope.
  final ForumSearchScope scope;

  /// Forum id.
  final String? forumId;

  /// Trimmed search keyword.
  String get normalizedKeyword => keyword.trim();

  /// Trimmed forum identifier, when this is a scoped search.
  String? get normalizedForumId {
    final v = forumId?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  /// Returns a normalized copy suitable for a forum search request.
  ForumSearchQuery normalized() => ForumSearchQuery(
    keyword: normalizedKeyword,
    scope: scope,
    forumId: normalizedForumId,
  );
}

/// Source-neutral forum search page identity.
final class ForumSearchPageIdentity {
  /// Creates a [ForumSearchPageIdentity].
  const ForumSearchPageIdentity({required this.token, required this.page});

  /// Token.
  final String token;

  /// Requested or current one-based page.
  final int page;
  @override
  bool operator ==(Object other) =>
      other is ForumSearchPageIdentity &&
      other.token == token &&
      other.page == page;
  @override
  int get hashCode => Object.hash(token, page);
}

/// Source-neutral forum search topic summary.
final class ForumSearchTopicSummary {
  /// Creates a [ForumSearchTopicSummary].
  const ForumSearchTopicSummary({
    required this.tid,
    required this.title,
    this.forumId,
    this.forumName,
    this.authorName,
    this.publishedAtText,
  });

  /// Stable thread identifier.
  final String tid;

  /// Title.
  final String title;

  /// Forum id.
  final String? forumId;

  /// Forum name.
  final String? forumName;

  /// Author name.
  final String? authorName;

  /// Published at text.
  final String? publishedAtText;
}

/// Source-neutral forum search pagination.
final class ForumSearchPagination {
  /// Creates a [ForumSearchPagination].
  const ForumSearchPagination({
    required this.currentPage,
    this.nextPage,
    this.precision = PaginationPrecision.unknown,
  });

  /// Current one-based server page.
  final int currentPage;

  /// Next page.
  final ForumSearchPageIdentity? nextPage;

  /// Precision.
  final PaginationPrecision precision;
}

/// Source-neutral forum search data.
final class ForumSearchData {
  /// Creates a [ForumSearchData].
  const ForumSearchData({
    required this.query,
    required this.topics,
    required this.pagination,
  });

  /// Query.
  final ForumSearchQuery query;

  /// Topics.
  final List<ForumSearchTopicSummary> topics;

  /// Pagination.
  final ForumSearchPagination pagination;
}

/// Capabilities exposed by forum search.
enum ForumSearchCapability {
  /// Stable topic identity.
  stableTopicIdentity,

  /// Ordered topics.
  orderedTopics,

  /// Topic title.
  topicTitle,

  /// Topic forum.
  topicForum,

  /// Topic author.
  topicAuthor,

  /// Topic published at.
  topicPublishedAt,

  /// Directional pagination.
  directionalPagination,

  /// Search continuation.
  searchContinuation,
}

/// Capabilities declared by the forum search source.
final class ForumSearchSourceCapabilities {
  /// Creates a [ForumSearchSourceCapabilities].
  const ForumSearchSourceCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  /// Per-capability support values.
  final DataCapabilitySet<ForumSearchCapability> values;

  /// Pagination precision.
  final PaginationPrecision paginationPrecision;

  /// Whether the requested capability is supported.
  bool supports(ForumSearchCapability c) => values.supports(c);

  /// Converts this value to read capabilities.
  ForumSearchReadCapabilities toReadCapabilities() =>
      ForumSearchReadCapabilities(
        values: values,
        paginationPrecision: paginationPrecision,
      );
}

/// Capabilities effective for one forum search read.
final class ForumSearchReadCapabilities {
  /// Creates a [ForumSearchReadCapabilities].
  const ForumSearchReadCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  /// Per-capability support values.
  final DataCapabilitySet<ForumSearchCapability> values;

  /// Pagination precision.
  final PaginationPrecision paginationPrecision;

  /// Whether the requested capability is supported.
  bool supports(ForumSearchCapability c) => values.supports(c);

  /// Returns the conservative intersection with another value.
  ForumSearchReadCapabilities intersect(ForumSearchReadCapabilities o) =>
      ForumSearchReadCapabilities(
        values: values.intersect(o.values),
        paginationPrecision: paginationPrecision.intersect(
          o.paginationPrecision,
        ),
      );
}

/// Loads forum search data through a source-neutral contract.
abstract interface class ForumSearchRepository {
  /// Loads data and returns a structured result.
  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>> load(
    ForumSearchQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });

  /// Loads next page and returns a structured result.
  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>>
  loadNextPage(
    ForumSearchQuery query,
    ForumSearchPageIdentity page, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
