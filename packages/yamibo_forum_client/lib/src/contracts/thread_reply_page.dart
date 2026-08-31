/// Narrow paginated reply contract used by comment-style consumers.
library;

import 'data_read_contract.dart';

/// Source-neutral thread reply entry.
final class ThreadReplyEntry {
  /// Creates a [ThreadReplyEntry].
  const ThreadReplyEntry({
    required this.pid,
    required this.authorId,
    required this.authorName,
    required this.dateline,
    required this.floorNumber,
    required this.isFirst,
    required this.rawMessage,
  });

  /// Stable post identifier.
  final String pid;

  /// Stable author identifier.
  final String authorId;

  /// Author name.
  final String authorName;

  /// Dateline.
  final String dateline;

  /// Floor number.
  final int floorNumber;

  /// Is first.
  final bool isFirst;

  /// Raw message.
  final String rawMessage;
}

/// Source-neutral thread reply page.
final class ThreadReplyPage {
  /// Creates a [ThreadReplyPage].
  const ThreadReplyPage({
    required this.tid,
    required this.page,
    required this.perPage,
    required this.replyCount,
    required this.posts,
    this.lastPage,
    this.hasNext,
  });

  /// Stable thread identifier.
  final String tid;

  /// Requested or current one-based page.
  final int page;

  /// Per page.
  final int perPage;

  /// Reply count.
  final int replyCount;

  /// Posts.
  final List<ThreadReplyEntry> posts;

  /// Last page.
  final int? lastPage;

  /// Whether a following page is available when known.
  final bool? hasNext;

  /// Expected page count inferred from the server pagination summary.
  int get expectedPageCount {
    final size = perPage <= 0 ? 20 : perPage;
    final total = (replyCount < 0 ? 0 : replyCount) + 1;
    final pages = (total + size - 1) ~/ size;
    return pages < 1 ? 1 : pages;
  }
}

/// Capabilities exposed by thread reply page.
enum ThreadReplyPageCapability {
  /// Stable thread identity.
  stableThreadIdentity,

  /// Ordered replies.
  orderedReplies,

  /// Stable post identity.
  stablePostIdentity,

  /// Pagination.
  pagination,
}

/// Capabilities effective for one thread reply page read.
final class ThreadReplyPageReadCapabilities {
  /// Creates a [ThreadReplyPageReadCapabilities].
  const ThreadReplyPageReadCapabilities(this.values);

  /// Per-capability support values.
  final DataCapabilitySet<ThreadReplyPageCapability> values;

  /// Whether the requested capability is supported.
  bool supports(ThreadReplyPageCapability capability) =>
      values.supports(capability);
}

/// Loads thread reply page data through a source-neutral contract.
abstract interface class ThreadReplyPageRepository {
  /// Loads page and returns a structured result.
  Future<DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>
  loadPage({required String tid, required int page});
}
