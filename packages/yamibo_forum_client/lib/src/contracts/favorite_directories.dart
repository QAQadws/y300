/// Read contracts for remote forum and thread favorite directories.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';
import '../network/forum_request.dart';

/// Query parameters for favorite forum directory.
final class FavoriteForumDirectoryQuery {
  /// Creates a [FavoriteForumDirectoryQuery].
  const FavoriteForumDirectoryQuery({this.cancellation});

  /// Cancellation.
  final ForumRequestCancellation? cancellation;
}

/// Source-neutral favorite forum directory data.
final class FavoriteForumDirectoryData {
  /// Creates a [FavoriteForumDirectoryData].
  const FavoriteForumDirectoryData({required this.items});

  /// Items.
  final List<FavoriteForumEntry> items;
}

/// Source-neutral favorite forum entry.
final class FavoriteForumEntry {
  /// Creates a [FavoriteForumEntry].
  const FavoriteForumEntry({
    required this.fid,
    required this.title,
    this.remoteFavoriteId,
    this.description,
    this.threadCount,
    this.postCount,
    this.todayPostCount,
  });

  /// Stable forum identifier.
  final String fid;

  /// Title.
  final String title;

  /// Remote favorite id.
  final String? remoteFavoriteId;

  /// Description.
  final String? description;

  /// Thread count.
  final int? threadCount;

  /// Post count.
  final int? postCount;

  /// Today post count.
  final int? todayPostCount;
}

/// Capabilities exposed by favorite forum directory.
enum FavoriteForumDirectoryCapability {
  /// Stable forum identity.
  stableForumIdentity,

  /// Stable remote favorite identity.
  stableRemoteFavoriteIdentity,

  /// Ordered forums.
  orderedForums,

  /// Forum title.
  forumTitle,

  /// Forum description.
  forumDescription,

  /// Forum thread count.
  forumThreadCount,

  /// Forum post count.
  forumPostCount,

  /// Forum today post count.
  forumTodayPostCount,
}

/// Capabilities declared by the favorite forum directory source.
final class FavoriteForumDirectorySourceCapabilities {
  /// Creates a [FavoriteForumDirectorySourceCapabilities].
  const FavoriteForumDirectorySourceCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<FavoriteForumDirectoryCapability> values;

  /// Whether the requested capability is supported.
  bool supports(FavoriteForumDirectoryCapability capability) =>
      values.supports(capability);

  /// Converts this value to read capabilities.
  FavoriteForumDirectoryReadCapabilities toReadCapabilities() =>
      FavoriteForumDirectoryReadCapabilities(values: values);
}

/// Capabilities effective for one favorite forum directory read.
final class FavoriteForumDirectoryReadCapabilities {
  /// Creates a [FavoriteForumDirectoryReadCapabilities].
  const FavoriteForumDirectoryReadCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<FavoriteForumDirectoryCapability> values;

  /// Whether the requested capability is supported.
  bool supports(FavoriteForumDirectoryCapability capability) =>
      values.supports(capability);

  /// Returns the conservative intersection with another value.
  FavoriteForumDirectoryReadCapabilities intersect(
    FavoriteForumDirectoryReadCapabilities other,
  ) => FavoriteForumDirectoryReadCapabilities(
    values: values.intersect(other.values),
  );
}

/// Loads favorite forum directory data through a source-neutral contract.
abstract interface class FavoriteForumDirectoryRepository {
  /// Capabilities declared by this source.
  FavoriteForumDirectorySourceCapabilities get capabilities;

  /// Favorite forum directory data.
  Future<
    DataReadResult<
      FavoriteForumDirectoryData,
      FavoriteForumDirectoryReadCapabilities
    >
  >
  load(
    FavoriteForumDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}

/// Query parameters for favorite thread directory.
final class FavoriteThreadDirectoryQuery {
  /// Creates a [FavoriteThreadDirectoryQuery].
  const FavoriteThreadDirectoryQuery({this.page = 1, this.cancellation});

  /// Requested or current one-based page.
  final int page;

  /// Cancellation.
  final ForumRequestCancellation? cancellation;
}

/// Source-neutral favorite thread directory data.
final class FavoriteThreadDirectoryData {
  /// Creates a [FavoriteThreadDirectoryData].
  const FavoriteThreadDirectoryData({
    required this.items,
    required this.pagination,
  });

  /// Items.
  final List<FavoriteThreadReference> items;

  /// Pagination.
  final FavoriteThreadPagination pagination;
}

/// Source-neutral favorite thread reference.
final class FavoriteThreadReference {
  /// Creates a [FavoriteThreadReference].
  const FavoriteThreadReference({
    required this.tid,
    required this.title,
    this.remoteFavoriteId,
    this.description,
    this.authorName,
    this.replyCount,
    this.favoritedAt,
  });

  /// Stable thread identifier.
  final String tid;

  /// Title.
  final String title;

  /// Remote favorite id.
  final String? remoteFavoriteId;

  /// Description.
  final String? description;

  /// Author name.
  final String? authorName;

  /// Reply count.
  final int? replyCount;

  /// Favorited at.
  final DateTime? favoritedAt;
}

/// Source-neutral favorite thread pagination.
final class FavoriteThreadPagination {
  /// Creates a [FavoriteThreadPagination].
  const FavoriteThreadPagination({
    required this.currentPage,
    this.pageSize,
    this.totalItems,
    this.totalPages,
    this.hasPrevious,
    this.hasNext,
  });

  /// Current one-based server page.
  final int currentPage;

  /// Page size.
  final int? pageSize;

  /// Total items.
  final int? totalItems;

  /// Exact total page count when the source proves it.
  final int? totalPages;

  /// Whether a preceding page is available when known.
  final bool? hasPrevious;

  /// Whether a following page is available when known.
  final bool? hasNext;
}

/// Capabilities exposed by favorite thread directory.
enum FavoriteThreadDirectoryCapability {
  /// Stable thread identity.
  stableThreadIdentity,

  /// Stable remote favorite identity.
  stableRemoteFavoriteIdentity,

  /// Ordered threads.
  orderedThreads,

  /// Thread title.
  threadTitle,

  /// Thread description.
  threadDescription,

  /// Thread author.
  threadAuthor,

  /// Thread reply count.
  threadReplyCount,

  /// Favorited at.
  favoritedAt,

  /// Directional pagination.
  directionalPagination,

  /// Page size.
  pageSize,

  /// Total item count.
  totalItemCount,

  /// Total page count.
  totalPageCount,
}

/// Capabilities declared by the favorite thread directory source.
final class FavoriteThreadDirectorySourceCapabilities {
  /// Creates a [FavoriteThreadDirectorySourceCapabilities].
  const FavoriteThreadDirectorySourceCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  /// Per-capability support values.
  final DataCapabilitySet<FavoriteThreadDirectoryCapability> values;

  /// Pagination precision.
  final PaginationPrecision paginationPrecision;

  /// Whether the requested capability is supported.
  bool supports(FavoriteThreadDirectoryCapability capability) =>
      values.supports(capability);

  /// Converts this value to read capabilities.
  FavoriteThreadDirectoryReadCapabilities toReadCapabilities() =>
      FavoriteThreadDirectoryReadCapabilities(
        values: values,
        paginationPrecision: paginationPrecision,
      );
}

/// Capabilities effective for one favorite thread directory read.
final class FavoriteThreadDirectoryReadCapabilities {
  /// Creates a [FavoriteThreadDirectoryReadCapabilities].
  const FavoriteThreadDirectoryReadCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  /// Per-capability support values.
  final DataCapabilitySet<FavoriteThreadDirectoryCapability> values;

  /// Pagination precision.
  final PaginationPrecision paginationPrecision;

  /// Whether the requested capability is supported.
  bool supports(FavoriteThreadDirectoryCapability capability) =>
      values.supports(capability);

  /// Returns the conservative intersection with another value.
  FavoriteThreadDirectoryReadCapabilities intersect(
    FavoriteThreadDirectoryReadCapabilities other,
  ) => FavoriteThreadDirectoryReadCapabilities(
    values: values.intersect(other.values),
    paginationPrecision: paginationPrecision.intersect(
      other.paginationPrecision,
    ),
  );
}

/// Loads favorite thread directory data through a source-neutral contract.
abstract interface class FavoriteThreadDirectoryRepository {
  /// Capabilities declared by this source.
  FavoriteThreadDirectorySourceCapabilities get capabilities;

  /// Favorite thread directory data.
  Future<
    DataReadResult<
      FavoriteThreadDirectoryData,
      FavoriteThreadDirectoryReadCapabilities
    >
  >
  load(
    FavoriteThreadDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
