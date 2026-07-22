enum ComicDownloadQueueStatus { pending, running, cancelRequested, failed }

extension ComicDownloadQueueStatusX on ComicDownloadQueueStatus {
  String get dbValue => switch (this) {
    ComicDownloadQueueStatus.pending => 'pending',
    ComicDownloadQueueStatus.running => 'running',
    ComicDownloadQueueStatus.cancelRequested => 'cancel_requested',
    ComicDownloadQueueStatus.failed => 'failed',
  };

  static ComicDownloadQueueStatus fromDbValue(String value) => switch (value) {
    'running' => ComicDownloadQueueStatus.running,
    'cancel_requested' => ComicDownloadQueueStatus.cancelRequested,
    'failed' => ComicDownloadQueueStatus.failed,
    _ => ComicDownloadQueueStatus.pending,
  };
}

final class ComicDownloadTarget {
  const ComicDownloadTarget({
    required this.comicId,
    required this.episodeId,
    required this.comicTitle,
    required this.episodeTitle,
  });

  final String comicId;
  final String episodeId;
  final String comicTitle;
  final String episodeTitle;
}

final class ComicDownloadQueueEntry {
  const ComicDownloadQueueEntry({
    required this.id,
    required this.comicId,
    required this.episodeId,
    required this.comicTitle,
    required this.episodeTitle,
    required this.status,
    required this.completedImages,
    required this.totalImages,
    required this.createdAt,
    required this.updatedAt,
    this.lastError,
  });

  final int id;
  final String comicId;
  final String episodeId;
  final String comicTitle;
  final String episodeTitle;
  final ComicDownloadQueueStatus status;
  final int completedImages;
  final int? totalImages;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive =>
      status == ComicDownloadQueueStatus.pending ||
      status == ComicDownloadQueueStatus.running ||
      status == ComicDownloadQueueStatus.cancelRequested;
}

final class ComicDownloadQueueSnapshot {
  const ComicDownloadQueueSnapshot({required this.entries});

  final List<ComicDownloadQueueEntry> entries;

  ComicDownloadQueueEntry? get activeEntry {
    for (final entry in entries) {
      if (entry.status == ComicDownloadQueueStatus.running ||
          entry.status == ComicDownloadQueueStatus.cancelRequested) {
        return entry;
      }
    }
    return null;
  }

  int get waitingCount => entries
      .where((entry) => entry.status == ComicDownloadQueueStatus.pending)
      .length;

  int get failedCount => entries
      .where((entry) => entry.status == ComicDownloadQueueStatus.failed)
      .length;

  bool get isEmpty => entries.isEmpty;

  static const empty = ComicDownloadQueueSnapshot(
    entries: <ComicDownloadQueueEntry>[],
  );
}

final class ComicDownloadEnqueueResult {
  const ComicDownloadEnqueueResult({
    required this.requestedCount,
    required this.enqueuedCount,
    required this.deduplicatedCount,
    required this.skippedDownloadedCount,
  });

  final int requestedCount;
  final int enqueuedCount;
  final int deduplicatedCount;
  final int skippedDownloadedCount;

  int get acceptedCount => enqueuedCount + deduplicatedCount;
}

final class ComicDownloadRepositoryEnqueueResult {
  const ComicDownloadRepositoryEnqueueResult({
    required this.enqueuedCount,
    required this.deduplicatedCount,
  });

  final int enqueuedCount;
  final int deduplicatedCount;
}
