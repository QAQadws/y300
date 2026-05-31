import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_task_progress.dart';
import 'package:y300/features/comic/domain/services/comic_episode_refresh_service.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

void main() {
  group('ComicSearchQueueShelfTaskProgressListenable current baseline', () {
    test('maps active queue snapshot message from waitingMessage', () {
      final source = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot(
          entries: <ComicSearchRefreshQueueEntry>[
            _entry(id: 1, title: 'Queued Comic'),
          ],
          cadence: const Duration(milliseconds: 10500),
        ),
      );
      addTearDown(source.dispose);

      final listenable = ComicSearchQueueShelfTaskProgressListenable(source);
      final progress = listenable.value;

      expect(progress, isNotNull);
      expect(progress?.message, source.value.waitingMessage);
      expect(progress?.source, LibraryMutationSource.comicSearchQueue);
      expect(progress?.reloadOnCompletion, isTrue);
    });

    test('returns null when queue snapshot is empty', () {
      final source = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot.empty,
      );
      addTearDown(source.dispose);

      final listenable = ComicSearchQueueShelfTaskProgressListenable(source);
      expect(listenable.value, isNull);
    });
  });
}

ComicSearchRefreshQueueEntry _entry({
  required int id,
  required String title,
}) {
  return ComicSearchRefreshQueueEntry(
    id: id,
    comicId: 'comic:$id',
    title: title,
    request: ComicEpisodeRefreshRequest(
      comicId: 'comic:$id',
      sourceTid: '$id',
      displayTitle: title,
    ),
    origin: ComicSearchRefreshOrigin.favoriteSync,
    status: ComicSearchRefreshQueueStatus.pending,
    attempts: 0,
    availableAt: DateTime(2026, 5, 16),
    createdAt: DateTime(2026, 5, 16),
    updatedAt: DateTime(2026, 5, 16),
  );
}
