import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';

class FavoriteParseAdmission {
  const FavoriteParseAdmission({
    this.enqueued = 0,
    this.existing = 0,
    this.rejected = 0,
  });

  final int enqueued;
  final int existing;
  final int rejected;
}

/// Acceptance means the request is durable, not that parsing has finished.
abstract interface class FavoriteParseService {
  Future<FavoriteParseAdmission> requestThreads(Set<String> tids);
  Future<void> requestConfirmed(ThreadFavoriteReceipt receipt, {String? title});
  Future<void> resume();
  Future<Set<String>> cancelThreads(Set<String> tids);
}

class FavoriteParseTarget {
  const FavoriteParseTarget({
    required this.tid,
    this.remoteFavoriteId,
    this.title,
    this.confirmed = false,
  });

  final String tid;
  final String? remoteFavoriteId;
  final String? title;
  final bool confirmed;
}

/// Uses the same execution lane and governor as directory synchronization.
abstract interface class FavoriteThreadParseExecutor {
  void noteMembershipChange(
    Set<String> tids, {
    required bool favorited,
    String? remoteFavoriteId,
    bool onlyIfUnknown = false,
  });
  bool isUnfavorited(String tid);
  Future<void> parseThread(
    FavoriteParseTarget target, {
    required Future<bool> Function() isCurrent,
  });
  Future<void> waitForPendingOperations();
}
