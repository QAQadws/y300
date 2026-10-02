/// Source-neutral user topic and reply directories for a verified viewer.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';
import '../network/forum_request.dart' show ForumRequestCancellation;

/// Which user forum directory to read.
enum UserThreadDirectoryType {
  /// Topics opened by the account.
  threads,

  /// Replies posted by the account, grouped by topic by the source.
  replies,
}

/// Identifies a directory owner, expected viewer, and one page.
final class UserThreadDirectoryQuery {
  /// Creates a user directory query.
  const UserThreadDirectoryQuery({
    required this.userId,
    this.type = UserThreadDirectoryType.threads,
    this.page = 1,
    this.viewerUserId,
  });

  /// Target directory owner's identifier.
  final String userId;

  /// Expected authenticated viewer, distinct from the directory owner.
  /// Omission preserves existing self-account reads by using [userId].
  final String? viewerUserId;

  /// Directory kind.
  final UserThreadDirectoryType type;

  /// One-based requested page.
  final int page;

  @override
  bool operator ==(Object other) =>
      other is UserThreadDirectoryQuery &&
      other.userId == userId &&
      other.viewerUserId == viewerUserId &&
      other.type == type &&
      other.page == page;

  @override
  int get hashCode => Object.hash(userId, viewerUserId, type, page);
}

/// One topic group, retaining every advertised reply destination.
final class UserThreadSummary {
  /// Creates a topic group. Missing optional metadata stays unknown.
  const UserThreadSummary({
    required this.threadId,
    required this.title,
    required this.uri,
    this.authorName,
    this.authorUserId,
    this.avatarUrl,
    this.publishedAtText,
    this.excerpt,
    this.forumId,
    this.forumName,
    this.views,
    this.replies,
    this.images = const [],
    this.replyPreviews = const [],
  });

  /// Stable topic identifier.
  final String threadId;

  /// Topic title without status badges or markup.
  final String title;

  /// Validated topic destination.
  final Uri uri;

  /// Source author display name.
  final String? authorName;

  /// Source author identifier, when advertised.
  final String? authorUserId;

  /// Resolved author avatar reference.
  final String? avatarUrl;

  /// Source-formatted publication date.
  final String? publishedAtText;

  /// Plain-text topic excerpt; restrictions may leave it absent.
  final String? excerpt;

  /// Source forum identifier.
  final String? forumId;

  /// Source forum display name.
  final String? forumName;

  /// Advertised topic view count.
  final int? views;

  /// Advertised topic reply count.
  final int? replies;

  /// Resolved preview images, preserving source order.
  final List<String> images;

  /// Individual account replies; topic identity alone cannot deduplicate them.
  final List<UserThreadReplyPreview> replyPreviews;
}

/// One reply and its exact server-provided post location.
final class UserThreadReplyPreview {
  /// Creates a reply preview.
  const UserThreadReplyPreview({
    required this.postId,
    required this.excerpt,
    required this.uri,
  });

  /// Stable post identifier.
  final String postId;

  /// Plain-text preview, including the source's restricted-content placeholder.
  final String excerpt;

  /// Server find-post destination; no page is guessed from reply order.
  final Uri uri;
}

/// Server-confirmed page directions independent of visible topic group count.
final class UserThreadDirectoryPagination {
  /// Creates pagination evidence.
  const UserThreadDirectoryPagination({
    required this.currentPage,
    required this.hasNext,
    required this.hasPrevious,
    this.totalPages,
  });

  /// One-based page.
  final int currentPage;

  /// Whether a validated next-page link was advertised.
  final bool hasNext;

  /// Whether a validated previous-page link was advertised.
  final bool hasPrevious;

  /// Exact total only when proved by the source.
  final int? totalPages;
}

/// User topic groups and pagination evidence.
final class UserThreadDirectoryData {
  /// Creates a user directory page.
  const UserThreadDirectoryData({
    required this.items,
    required this.pagination,
  });

  /// Topic groups in server order.
  final List<UserThreadSummary> items;

  /// Server page directions.
  final UserThreadDirectoryPagination pagination;
}

/// Business capabilities of a user directory source.
enum UserThreadDirectoryCapability {
  /// Validated topic identifiers and destinations.
  stableIdentity,

  /// Server ordering.
  orderedItems,

  /// Plain-text excerpts.
  excerpt,

  /// Author metadata.
  author,

  /// Publication dates.
  publishedAtText,

  /// Forum identifiers and names.
  forum,

  /// View and reply counts.
  statistics,

  /// Preview image references.
  images,

  /// Individual reply identifiers and destinations.
  replyPreviews,

  /// Confirmed next and previous page directions.
  directionalPagination,

  /// Exact total page count.
  totalPageCount,
}

/// Declared source capabilities.
final class UserThreadDirectorySourceCapabilities {
  /// Creates source support evidence.
  const UserThreadDirectorySourceCapabilities({required this.values});

  /// Per-capability support.
  final DataCapabilitySet<UserThreadDirectoryCapability> values;

  /// Whether a capability is supported.
  bool supports(UserThreadDirectoryCapability capability) =>
      values.supports(capability);
}

/// Effective capabilities for one directory page.
final class UserThreadDirectoryReadCapabilities {
  /// Creates read support evidence.
  const UserThreadDirectoryReadCapabilities({
    required this.values,
    this.paginationPrecision = PaginationPrecision.directional,
  });

  /// Per-capability support.
  final DataCapabilitySet<UserThreadDirectoryCapability> values;

  /// Precision proved by pagination markup.
  final PaginationPrecision paginationPrecision;

  /// Whether a capability is supported.
  bool supports(UserThreadDirectoryCapability capability) =>
      values.supports(capability);

  /// Conservative support composition for merged pages.
  UserThreadDirectoryReadCapabilities intersect(
    UserThreadDirectoryReadCapabilities other,
  ) => UserThreadDirectoryReadCapabilities(
    values: values.intersect(other.values),
    paginationPrecision: paginationPrecision.intersect(
      other.paginationPrecision,
    ),
  );
}

/// Reads a target user's topics or replies under the viewer's permissions.
abstract interface class UserThreadDirectoryRepository {
  /// Declared source capabilities.
  UserThreadDirectorySourceCapabilities get capabilities;

  /// Loads one page. The standard source always reads the shared network
  /// without storing or falling back to another session's cached document.
  Future<
    DataReadResult<UserThreadDirectoryData, UserThreadDirectoryReadCapabilities>
  >
  load(
    UserThreadDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
    ForumRequestCancellation? cancellation,
  });
}
