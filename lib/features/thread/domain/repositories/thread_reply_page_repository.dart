import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/thread/domain/models/thread_reply_page.dart';

enum ThreadReplyPageCapability {
  stableThreadIdentity,
  orderedReplies,
  stablePostIdentity,
  pagination,
}

final class ThreadReplyPageReadCapabilities {
  const ThreadReplyPageReadCapabilities(this.values);

  final DataCapabilitySet<ThreadReplyPageCapability> values;

  bool supports(ThreadReplyPageCapability capability) {
    return values.supports(capability);
  }
}

abstract interface class ThreadReplyPageRepository {
  Future<DataReadResult<ThreadReplyPage, ThreadReplyPageReadCapabilities>>
  loadPage({required String tid, required int page});
}
