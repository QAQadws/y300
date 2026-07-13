enum NovelChapterSyncMode { initialFull, incremental }

class NovelChapterSyncCheckpoint {
  const NovelChapterSyncCheckpoint({
    required this.novelId,
    required this.publisherId,
    required this.lastCompletedAuthorPage,
    required this.lastSeenPid,
    required this.completedAt,
  });

  final String novelId;
  final String publisherId;
  final int lastCompletedAuthorPage;
  final String? lastSeenPid;
  final DateTime completedAt;
}

class NovelChapterSyncRequest {
  const NovelChapterSyncRequest({
    required this.novelId,
    required this.tid,
    required this.publisherId,
    required this.mode,
    this.checkpoint,
  });

  final String novelId;
  final String tid;
  final String publisherId;
  final NovelChapterSyncMode mode;
  final NovelChapterSyncCheckpoint? checkpoint;
}

enum NovelChapterSyncPhase {
  preparing,
  fetchingPage,
  parsingPage,
  committing,
  completed,
  failed,
}

class NovelChapterSyncProgress {
  const NovelChapterSyncProgress({
    required this.runId,
    required this.novelId,
    required this.mode,
    required this.phase,
    this.currentPage,
    this.totalPages,
    this.acceptedCount = 0,
    this.message,
  });

  final String runId;
  final String novelId;
  final NovelChapterSyncMode mode;
  final NovelChapterSyncPhase phase;
  final int? currentPage;
  final int? totalPages;
  final int acceptedCount;
  final String? message;
}

class NovelChapterSyncResult {
  const NovelChapterSyncResult({
    required this.mode,
    required this.fetchedPages,
    required this.insertedCount,
    required this.updatedCount,
    required this.totalCount,
    required this.checkpoint,
  });

  final NovelChapterSyncMode mode;
  final int fetchedPages;
  final int insertedCount;
  final int updatedCount;
  final int totalCount;
  final NovelChapterSyncCheckpoint checkpoint;
}
