enum NovelChapterSyncMode {
  /// First hydration for a work that does not yet have a complete chapter set.
  initialFull,

  /// Revisit the persisted overlap page and append/update chapters from there.
  incremental,

  /// Rebuild an already hydrated work from author-filtered page one.
  ///
  /// Unlike [initialFull], a failed refresh must not invalidate the existing
  /// ready chapter set.
  fullRefresh,
}

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

enum NovelChapterSyncFailureCode {
  missingSourceState,
  missingPublisherId,
  missingSourceTid,
  missingCheckpoint,
  interrupted,
  synchronizationFailed,
  unknown,
}

extension NovelChapterSyncFailureCodeCodec on NovelChapterSyncFailureCode {
  String get storageValue => 'novel_sync_$name';

  static NovelChapterSyncFailureCode fromStorage(String? value) {
    return NovelChapterSyncFailureCode.values.firstWhere(
      (code) => code.storageValue == value,
      orElse: () => NovelChapterSyncFailureCode.unknown,
    );
  }
}

final class NovelChapterSyncException implements Exception {
  const NovelChapterSyncException(this.code, {this.detail});

  final NovelChapterSyncFailureCode code;
  final Object? detail;

  @override
  String toString() => 'NovelChapterSyncException(${code.name})';
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
    this.failureCode,
    this.diagnosticDetail,
  });

  final String runId;
  final String novelId;
  final NovelChapterSyncMode mode;
  final NovelChapterSyncPhase phase;
  final int? currentPage;
  final int? totalPages;
  final int acceptedCount;
  final NovelChapterSyncFailureCode? failureCode;
  final Object? diagnosticDetail;
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
