import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';

abstract class ComicSearchRefreshQueueRepository {
  Future<ComicSearchRefreshQueueUpsertResult> enqueue(
    ComicSearchRefreshQueueDraft draft, {
    required DateTime now,
  });

  Future<void> resetRunningToPending({
    required DateTime now,
  });

  Future<ComicSearchRefreshQueueEntry?> claimNextPending({
    required DateTime now,
  });

  Future<void> markCompleted({
    required int id,
    required DateTime now,
  });

  Future<void> markRetry({
    required int id,
    required int attempts,
    required String lastError,
    required DateTime availableAt,
    required DateTime now,
  });

  Future<void> markFailed({
    required int id,
    required int attempts,
    required String lastError,
    required DateTime now,
  });

  Future<List<ComicSearchRefreshQueueEntry>> loadActiveEntries();
}
