import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';

abstract interface class ComicDownloadQueueRepository {
  Future<ComicDownloadRepositoryEnqueueResult> enqueueTargets(
    List<ComicDownloadTarget> targets, {
    required DateTime now,
  });

  Future<void> recoverInterrupted({required DateTime now});

  Future<ComicDownloadQueueEntry?> claimNext({required DateTime now});

  Future<List<ComicDownloadQueueEntry>> loadVisibleEntries();

  Future<ComicDownloadQueueEntry?> getById(int id);

  Future<void> updateProgress({
    required int id,
    required int completedImages,
    required int totalImages,
    required DateTime now,
  });

  Future<void> markFailed({
    required int id,
    required String error,
    required DateTime now,
  });

  Future<void> requestCancel({required int id, required DateTime now});

  Future<void> retry({required int id, required DateTime now});

  Future<void> delete(int id);

  Future<bool> deleteIfNotRunning(int id);

  Future<void> deleteByEpisode(String comicId, String episodeId);

  Future<void> deleteByComic(String comicId);
}
