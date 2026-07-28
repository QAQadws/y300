import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_episode_refresh_service.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';

void main() {
  group('ComicSearchRefreshQueueSnapshot structured status', () {
    test('keeps raw head title and estimated duration', () {
      final snapshot = ComicSearchRefreshQueueSnapshot(
        entries: <ComicSearchRefreshQueueEntry>[
          _entry(id: 1, title: 'Queued Comic'),
        ],
        cadence: const Duration(milliseconds: 10500),
      );

      expect(snapshot.estimatedDuration, const Duration(milliseconds: 10500));
      expect(snapshot.headTitle, 'Queued Comic');
    });

    test('multiplies queue size by cadence', () {
      final snapshot = ComicSearchRefreshQueueSnapshot(
        entries: <ComicSearchRefreshQueueEntry>[
          _entry(id: 1, title: 'Queued Comic'),
          _entry(id: 2, title: 'Second Comic'),
        ],
        cadence: const Duration(seconds: 10),
      );

      expect(snapshot.estimatedDuration, const Duration(seconds: 20));
      expect(snapshot.headTitle, 'Queued Comic');
    });

    test('does not rewrite a blank raw head title', () {
      final snapshot = ComicSearchRefreshQueueSnapshot(
        entries: <ComicSearchRefreshQueueEntry>[_entry(id: 1, title: '   ')],
        cadence: const Duration(milliseconds: 10500),
      );

      expect(snapshot.headTitle, '   ');
    });
  });
}

ComicSearchRefreshQueueEntry _entry({required int id, required String title}) {
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
