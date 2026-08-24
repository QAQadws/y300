import 'cache_load_policy.dart';
import 'data_read_contract.dart';
import 'thread_detail_models.dart';

final class ThreadPostRatingsQuery {
  const ThreadPostRatingsQuery({required this.tid, required this.pid});
  final String tid;
  final String pid;
}

final class ThreadPostRatingsData {
  const ThreadPostRatingsData({
    required this.participantCount,
    required this.totalScoreText,
    required this.ratings,
  });
  final int participantCount;
  final String totalScoreText;
  final List<ThreadPostRating> ratings;
}

enum ThreadPostRatingsCapability {
  stablePostIdentity,
  orderedRatings,
  participantCount,
  aggregateScore,
  userIdentity,
  reason,
  datelineText,
}

final class ThreadPostRatingsSourceCapabilities {
  const ThreadPostRatingsSourceCapabilities({required this.values});
  final DataCapabilitySet<ThreadPostRatingsCapability> values;
  ThreadPostRatingsReadCapabilities toReadCapabilities() =>
      ThreadPostRatingsReadCapabilities(values: values);
}

final class ThreadPostRatingsReadCapabilities {
  const ThreadPostRatingsReadCapabilities({required this.values});
  final DataCapabilitySet<ThreadPostRatingsCapability> values;
}

abstract interface class ThreadPostRatingsRepository {
  ThreadPostRatingsSourceCapabilities get capabilities;
  Future<
    DataReadResult<ThreadPostRatingsData, ThreadPostRatingsReadCapabilities>
  >
  load(
    ThreadPostRatingsQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.networkFirst,
  });
}

final class ThreadPostLocationQuery {
  const ThreadPostLocationQuery({required this.tid, required this.pid});
  final String tid;
  final String pid;
}

final class ThreadPostLocationData {
  const ThreadPostLocationData({
    required this.tid,
    required this.pid,
    required this.page,
    required this.resolvedUri,
  });
  final String tid;
  final String pid;
  final int page;
  final Uri resolvedUri;
}

enum ThreadPostLocatorCapability {
  stableThreadIdentity,
  stablePostIdentity,
  exactPage,
  resolvedReference,
}

final class ThreadPostLocatorSourceCapabilities {
  const ThreadPostLocatorSourceCapabilities({required this.values});
  final DataCapabilitySet<ThreadPostLocatorCapability> values;
  ThreadPostLocatorReadCapabilities toReadCapabilities() =>
      ThreadPostLocatorReadCapabilities(values: values);
}

final class ThreadPostLocatorReadCapabilities {
  const ThreadPostLocatorReadCapabilities({required this.values});
  final DataCapabilitySet<ThreadPostLocatorCapability> values;
}

abstract interface class ThreadPostLocatorRepository {
  ThreadPostLocatorSourceCapabilities get capabilities;
  Future<
    DataReadResult<ThreadPostLocationData, ThreadPostLocatorReadCapabilities>
  >
  locate(
    ThreadPostLocationQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.networkFirst,
  });
}

final class ThreadAuthorPostQuery {
  const ThreadAuthorPostQuery({
    required this.tid,
    required this.authorId,
    required this.page,
    this.pageSize = 200,
  });
  final String tid;
  final String authorId;
  final int page;
  final int pageSize;
}

final class ThreadAuthorPostPage {
  const ThreadAuthorPostPage({
    required this.tid,
    required this.subject,
    required this.posts,
    required this.currentPage,
    required this.pageSize,
    required this.totalReplyHint,
    required this.hasNext,
  });
  final String tid;
  final String subject;
  final List<ThreadPost> posts;
  final int currentPage;
  final int pageSize;
  final int totalReplyHint;
  final bool hasNext;
}

enum ThreadAuthorPostCapability {
  stableThreadIdentity,
  authorFilterApplied,
  orderedPostIdentity,
  renderableBody,
  attachmentMetadata,
  subject,
  requestedPage,
  directionalPagination,
}

final class ThreadAuthorPostSourceCapabilities {
  const ThreadAuthorPostSourceCapabilities({required this.values});
  final DataCapabilitySet<ThreadAuthorPostCapability> values;
  ThreadAuthorPostReadCapabilities toReadCapabilities() =>
      ThreadAuthorPostReadCapabilities(values: values);
}

final class ThreadAuthorPostReadCapabilities {
  const ThreadAuthorPostReadCapabilities({required this.values});
  final DataCapabilitySet<ThreadAuthorPostCapability> values;
}

abstract interface class ThreadAuthorPostRepository {
  ThreadAuthorPostSourceCapabilities get capabilities;
  Future<DataReadResult<ThreadAuthorPostPage, ThreadAuthorPostReadCapabilities>>
  load(
    ThreadAuthorPostQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.networkFirst,
  });
}
