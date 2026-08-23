import 'data_read_contract.dart';

final class ThreadReplyEntry {
  const ThreadReplyEntry({
    required this.pid,
    required this.authorId,
    required this.authorName,
    required this.dateline,
    required this.floorNumber,
    required this.isFirst,
    required this.rawMessage,
  });
  final String pid;
  final String authorId;
  final String authorName;
  final String dateline;
  final int floorNumber;
  final bool isFirst;
  final String rawMessage;
}

final class ThreadReplyPage {
  const ThreadReplyPage({
    required this.tid,
    required this.page,
    required this.perPage,
    required this.replyCount,
    required this.posts,
    this.lastPage,
    this.hasNext,
  });
  final String tid;
  final int page;
  final int perPage;
  final int replyCount;
  final List<ThreadReplyEntry> posts;
  final int? lastPage;
  final bool? hasNext;
  int get expectedPageCount {
    final size = perPage <= 0 ? 20 : perPage;
    final total = (replyCount < 0 ? 0 : replyCount) + 1;
    final pages = (total + size - 1) ~/ size;
    return pages < 1 ? 1 : pages;
  }
}

enum ThreadReplyPageCapability {
  stableThreadIdentity,
  orderedReplies,
  stablePostIdentity,
  pagination,
}

final class ThreadReplyPageReadCapabilities {
  const ThreadReplyPageReadCapabilities(this.values);
  final DataCapabilitySet<ThreadReplyPageCapability> values;
  bool supports(ThreadReplyPageCapability capability) =>
      values.supports(capability);
}

abstract interface class ThreadReplyPageRepository {
  Future<DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>
  loadPage({required String tid, required int page});
}
