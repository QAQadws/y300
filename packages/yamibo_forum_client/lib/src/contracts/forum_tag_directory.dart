/// Read contracts for tag identities and their ordered topic directories.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';

/// Query parameters for forum tag directory.
final class ForumTagDirectoryQuery {
  /// Creates a [ForumTagDirectoryQuery].
  const ForumTagDirectoryQuery({required this.tagId, this.page = 1});

  /// Tag id.
  final String tagId;

  /// Requested or current one-based page.
  final int page;

  /// Returns a copy with the supplied changes.
  ForumTagDirectoryQuery copyWith({String? tagId, int? page}) =>
      ForumTagDirectoryQuery(
        tagId: tagId ?? this.tagId,
        page: page ?? this.page,
      );
}

/// Source-neutral forum tag directory data.
final class ForumTagDirectoryData {
  /// Creates a [ForumTagDirectoryData].
  const ForumTagDirectoryData({
    required this.tag,
    required this.topics,
    required this.pagination,
  });

  /// Tag.
  final ForumTagIdentity tag;

  /// Topics.
  final List<ForumTagTopicSummary> topics;

  /// Pagination.
  final ForumTagPagination pagination;
}

/// Source-neutral forum tag identity.
final class ForumTagIdentity {
  /// Creates a [ForumTagIdentity].
  const ForumTagIdentity({required this.id, this.name});

  /// Stable tag identifier.
  final String id;

  /// Name.
  final String? name;
}

/// Source-neutral forum tag topic summary.
final class ForumTagTopicSummary {
  /// Creates a [ForumTagTopicSummary].
  const ForumTagTopicSummary({
    required this.tid,
    required this.title,
    this.threadUrl,
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

  /// Stable thread identifier.
  final String tid;

  /// Title.
  final String title;

  /// Thread url.
  final String? threadUrl;

  /// Forum id.
  final String? forumId;

  /// Forum name.
  final String? forumName;

  /// Stable author identifier.
  final String? authorId;

  /// Author name.
  final String? authorName;

  /// Created at.
  final String? createdAt;

  /// Reply count.
  final int? replyCount;

  /// View count.
  final int? viewCount;

  /// Last poster name.
  final String? lastPosterName;

  /// Last post at.
  final String? lastPostAt;

  /// Has image attachment.
  final bool? hasImageAttachment;

  /// Has attachment.
  final bool? hasAttachment;
}

/// Source-neutral forum tag pagination.
final class ForumTagPagination {
  /// Creates a [ForumTagPagination].
  const ForumTagPagination({
    required this.currentPage,
    this.totalPages,
    this.hasPrevious,
    this.hasNext,
  });

  /// Current one-based server page.
  final int currentPage;

  /// Exact total page count when the source proves it.
  final int? totalPages;

  /// Whether a preceding page is available when known.
  final bool? hasPrevious;

  /// Whether a following page is available when known.
  final bool? hasNext;
}

/// Capabilities exposed by forum tag directory.
enum ForumTagDirectoryCapability {
  /// Stable tag identity.
  stableTagIdentity,

  /// Ordered topics.
  orderedTopics,

  /// Stable topic identity.
  stableTopicIdentity,

  /// Topic title.
  topicTitle,

  /// Tag name.
  tagName,

  /// Topic forum.
  topicForum,

  /// Topic author.
  topicAuthor,

  /// Topic creation time.
  topicCreationTime,

  /// Topic reply count.
  topicReplyCount,

  /// Topic view count.
  topicViewCount,

  /// Topic last post.
  topicLastPost,

  /// Topic attachment flags.
  topicAttachmentFlags,

  /// Directional pagination.
  directionalPagination,

  /// Total page count.
  totalPageCount,
}

/// Capabilities declared by the forum tag directory source.
final class ForumTagDirectorySourceCapabilities {
  /// Creates a [ForumTagDirectorySourceCapabilities].
  const ForumTagDirectorySourceCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  /// Per-capability support values.
  final DataCapabilitySet<ForumTagDirectoryCapability> values;

  /// Pagination precision.
  final PaginationPrecision paginationPrecision;

  /// Whether the requested capability is supported.
  bool supports(ForumTagDirectoryCapability capability) =>
      values.supports(capability);

  /// Converts this value to read capabilities.
  ForumTagDirectoryReadCapabilities toReadCapabilities() =>
      ForumTagDirectoryReadCapabilities(
        values: values,
        paginationPrecision: paginationPrecision,
      );
}

/// Capabilities effective for one forum tag directory read.
final class ForumTagDirectoryReadCapabilities {
  /// Creates a [ForumTagDirectoryReadCapabilities].
  const ForumTagDirectoryReadCapabilities({
    required this.values,
    required this.paginationPrecision,
  });

  /// Per-capability support values.
  final DataCapabilitySet<ForumTagDirectoryCapability> values;

  /// Pagination precision.
  final PaginationPrecision paginationPrecision;

  /// Whether the requested capability is supported.
  bool supports(ForumTagDirectoryCapability capability) =>
      values.supports(capability);

  /// Returns the conservative intersection with another value.
  ForumTagDirectoryReadCapabilities intersect(
    ForumTagDirectoryReadCapabilities other,
  ) => ForumTagDirectoryReadCapabilities(
    values: values.intersect(other.values),
    paginationPrecision: paginationPrecision.intersect(
      other.paginationPrecision,
    ),
  );
}

/// Loads forum tag directory data through a source-neutral contract.
abstract interface class ForumTagDirectoryRepository {
  /// Capabilities declared by this source.
  ForumTagDirectorySourceCapabilities get capabilities;

  /// Loads data and returns a structured result.
  Future<
    DataReadResult<ForumTagDirectoryData, ForumTagDirectoryReadCapabilities>
  >
  load(
    ForumTagDirectoryQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  });
}
