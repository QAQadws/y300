/// Read contract and capability model for a forum display page.
library;

import 'data_read_contract.dart';
import 'cache_load_policy.dart';
import 'forum_display_models.dart';

/// Capabilities exposed by forum display.
enum ForumDisplayCapability {
  /// Forum identity.
  forumIdentity,

  /// Ordered thread summaries.
  orderedThreadSummaries,

  /// Rich thread summaries.
  richThreadSummaries,

  /// Thread type query.
  threadTypeQuery,

  /// Last post ordering.
  lastPostOrdering,

  /// Opaque query parameters.
  opaqueQueryParameters,

  /// Forum chrome.
  forumChrome,

  /// Filters.
  filters,

  /// Sub forums.
  subForums,

  /// Top entries.
  topEntries,

  /// Posting entry.
  postingEntry,

  /// Search entry.
  searchEntry,

  /// Favorite state.
  favoriteState,

  /// Directional pagination.
  directionalPagination,

  /// Exact pagination.
  exactPagination,
}

/// Capabilities declared by the forum display source.
final class ForumDisplaySourceCapabilities {
  /// Creates a [ForumDisplaySourceCapabilities].
  const ForumDisplaySourceCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  /// Per-capability support values.
  final DataCapabilitySet<ForumDisplayCapability> values;

  /// Pagination precision.
  final PaginationPrecision paginationPrecision;

  /// Complete capability set used by the verified full source.
  static final full = ForumDisplaySourceCapabilities(
    values: DataCapabilitySet<ForumDisplayCapability>.supported(
      ForumDisplayCapability.values,
    ),
    paginationPrecision: PaginationPrecision.exact,
  );

  /// Whether the requested capability is supported.
  bool supports(ForumDisplayCapability capability) {
    return values.supports(capability);
  }

  /// Converts this value to read capabilities.
  ForumDisplayReadCapabilities toReadCapabilities() {
    return ForumDisplayReadCapabilities(
      values: values,
      paginationPrecision: paginationPrecision,
    );
  }
}

/// Capabilities effective for one forum display read.
final class ForumDisplayReadCapabilities {
  /// Creates a [ForumDisplayReadCapabilities].
  const ForumDisplayReadCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  /// Per-capability support values.
  final DataCapabilitySet<ForumDisplayCapability> values;

  /// Pagination precision.
  final PaginationPrecision paginationPrecision;

  /// Whether the requested capability is supported.
  bool supports(ForumDisplayCapability capability) {
    return values.supports(capability);
  }

  /// Returns the conservative intersection with another value.
  ForumDisplayReadCapabilities intersect(ForumDisplayReadCapabilities other) {
    return ForumDisplayReadCapabilities(
      values: values.intersect(other.values),
      paginationPrecision: paginationPrecision.intersect(
        other.paginationPrecision,
      ),
    );
  }
}

/// Loads forum display data through a source-neutral contract.
abstract interface class ForumDisplayRepository {
  /// Capabilities declared by this source.
  ForumDisplaySourceCapabilities get capabilities;

  /// Loads one forum-display page using [query] and [cachePolicy].
  Future<DataReadResult<ForumDisplayData, ForumDisplayReadCapabilities>>
  getForumDisplayByQuery(
    ForumDisplayQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}

/// Convenience operations for [ForumDisplayRepository].
extension ForumDisplayRepositoryConvenience on ForumDisplayRepository {
  /// Loads a forum-display page from a stable forum identifier.
  Future<DataReadResult<ForumDisplayData, ForumDisplayReadCapabilities>>
  getForumDisplay({
    required String fid,
    int page = 1,
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) {
    return getForumDisplayByQuery(
      ForumDisplayQuery.initial(fid: fid).copyWithPage(page),
      cachePolicy: cachePolicy,
    );
  }
}
