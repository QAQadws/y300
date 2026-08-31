/// Supplemental read contracts for ratings, post location, and author views.
library;

import 'cache_load_policy.dart';
import 'data_read_contract.dart';
import 'thread_detail_models.dart';

/// Query parameters for thread post ratings.
final class ThreadPostRatingsQuery {
  /// Creates a [ThreadPostRatingsQuery].
  const ThreadPostRatingsQuery({required this.tid, required this.pid});

  /// Stable thread identifier.
  final String tid;

  /// Stable post identifier.
  final String pid;
}

/// Source-neutral thread post ratings data.
final class ThreadPostRatingsData {
  /// Creates a [ThreadPostRatingsData].
  const ThreadPostRatingsData({
    required this.participantCount,
    required this.totalScoreText,
    required this.ratings,
  });

  /// Participant count.
  final int participantCount;

  /// Total score text.
  final String totalScoreText;

  /// Ratings.
  final List<ThreadPostRating> ratings;
}

/// Capabilities exposed by thread post ratings.
enum ThreadPostRatingsCapability {
  /// Stable post identity.
  stablePostIdentity,

  /// Ordered ratings.
  orderedRatings,

  /// Participant count.
  participantCount,

  /// Aggregate score.
  aggregateScore,

  /// User identity.
  userIdentity,

  /// Reason.
  reason,

  /// Dateline text.
  datelineText,
}

/// Capabilities declared by the thread post ratings source.
final class ThreadPostRatingsSourceCapabilities {
  /// Creates a [ThreadPostRatingsSourceCapabilities].
  const ThreadPostRatingsSourceCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ThreadPostRatingsCapability> values;

  /// Converts this value to read capabilities.
  ThreadPostRatingsReadCapabilities toReadCapabilities() =>
      ThreadPostRatingsReadCapabilities(values: values);
}

/// Capabilities effective for one thread post ratings read.
final class ThreadPostRatingsReadCapabilities {
  /// Creates a [ThreadPostRatingsReadCapabilities].
  const ThreadPostRatingsReadCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ThreadPostRatingsCapability> values;
}

/// Loads thread post ratings data through a source-neutral contract.
abstract interface class ThreadPostRatingsRepository {
  /// Capabilities declared by this source.
  ThreadPostRatingsSourceCapabilities get capabilities;

  /// Loads data and returns a structured result.
  Future<
    DataReadResult<ThreadPostRatingsData, ThreadPostRatingsReadCapabilities>
  >
  load(
    ThreadPostRatingsQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.networkFirst,
  });
}

/// Query parameters for thread post location.
final class ThreadPostLocationQuery {
  /// Creates a [ThreadPostLocationQuery].
  const ThreadPostLocationQuery({required this.tid, required this.pid});

  /// Stable thread identifier.
  final String tid;

  /// Stable post identifier.
  final String pid;
}

/// Source-neutral thread post location data.
final class ThreadPostLocationData {
  /// Creates a [ThreadPostLocationData].
  const ThreadPostLocationData({
    required this.tid,
    required this.pid,
    required this.page,
    required this.resolvedUri,
  });

  /// Stable thread identifier.
  final String tid;

  /// Stable post identifier.
  final String pid;

  /// Requested or current one-based page.
  final int page;

  /// Resolved uri.
  final Uri resolvedUri;
}

/// Capabilities exposed by thread post locator.
enum ThreadPostLocatorCapability {
  /// Stable thread identity.
  stableThreadIdentity,

  /// Stable post identity.
  stablePostIdentity,

  /// Exact page.
  exactPage,

  /// Resolved reference.
  resolvedReference,
}

/// Capabilities declared by the thread post locator source.
final class ThreadPostLocatorSourceCapabilities {
  /// Creates a [ThreadPostLocatorSourceCapabilities].
  const ThreadPostLocatorSourceCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ThreadPostLocatorCapability> values;

  /// Converts this value to read capabilities.
  ThreadPostLocatorReadCapabilities toReadCapabilities() =>
      ThreadPostLocatorReadCapabilities(values: values);
}

/// Capabilities effective for one thread post locator read.
final class ThreadPostLocatorReadCapabilities {
  /// Creates a [ThreadPostLocatorReadCapabilities].
  const ThreadPostLocatorReadCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ThreadPostLocatorCapability> values;
}

/// Loads thread post locator data through a source-neutral contract.
abstract interface class ThreadPostLocatorRepository {
  /// Capabilities declared by this source.
  ThreadPostLocatorSourceCapabilities get capabilities;

  /// Resolves a stable post target to its exact thread page.
  Future<
    DataReadResult<ThreadPostLocationData, ThreadPostLocatorReadCapabilities>
  >
  locate(
    ThreadPostLocationQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.networkFirst,
  });
}

/// Query parameters for thread author post.
final class ThreadAuthorPostQuery {
  /// Creates a [ThreadAuthorPostQuery].
  const ThreadAuthorPostQuery({
    required this.tid,
    required this.authorId,
    required this.page,
    this.pageSize = 200,
  });

  /// Stable thread identifier.
  final String tid;

  /// Stable author identifier.
  final String authorId;

  /// Requested or current one-based page.
  final int page;

  /// Page size.
  final int pageSize;
}

/// Source-neutral thread author post page.
final class ThreadAuthorPostPage {
  /// Creates a [ThreadAuthorPostPage].
  const ThreadAuthorPostPage({
    required this.tid,
    required this.subject,
    required this.posts,
    required this.currentPage,
    required this.pageSize,
    required this.totalReplyHint,
    required this.hasNext,
  });

  /// Stable thread identifier.
  final String tid;

  /// Subject.
  final String subject;

  /// Posts.
  final List<ThreadPost> posts;

  /// Current one-based server page.
  final int currentPage;

  /// Page size.
  final int pageSize;

  /// Total reply hint.
  final int totalReplyHint;

  /// Whether a following page is available when known.
  final bool hasNext;
}

/// Capabilities exposed by thread author post.
enum ThreadAuthorPostCapability {
  /// Stable thread identity.
  stableThreadIdentity,

  /// Author filter applied.
  authorFilterApplied,

  /// Ordered post identity.
  orderedPostIdentity,

  /// Renderable body.
  renderableBody,

  /// Attachment metadata.
  attachmentMetadata,

  /// Subject.
  subject,

  /// Requested page.
  requestedPage,

  /// Directional pagination.
  directionalPagination,
}

/// Capabilities declared by the thread author post source.
final class ThreadAuthorPostSourceCapabilities {
  /// Creates a [ThreadAuthorPostSourceCapabilities].
  const ThreadAuthorPostSourceCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ThreadAuthorPostCapability> values;

  /// Converts this value to read capabilities.
  ThreadAuthorPostReadCapabilities toReadCapabilities() =>
      ThreadAuthorPostReadCapabilities(values: values);
}

/// Capabilities effective for one thread author post read.
final class ThreadAuthorPostReadCapabilities {
  /// Creates a [ThreadAuthorPostReadCapabilities].
  const ThreadAuthorPostReadCapabilities({required this.values});

  /// Per-capability support values.
  final DataCapabilitySet<ThreadAuthorPostCapability> values;
}

/// Loads thread author post data through a source-neutral contract.
abstract interface class ThreadAuthorPostRepository {
  /// Capabilities declared by this source.
  ThreadAuthorPostSourceCapabilities get capabilities;

  /// Loads data and returns a structured result.
  Future<DataReadResult<ThreadAuthorPostPage, ThreadAuthorPostReadCapabilities>>
  load(
    ThreadAuthorPostQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.networkFirst,
  });
}
