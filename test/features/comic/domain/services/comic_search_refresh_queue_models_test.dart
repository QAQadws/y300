import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/domain/services/comic_episode_refresh_service.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';

void main() {
  group('ComicSearchRefreshQueueSnapshot current baseline', () {
    test('waitingMessage uses head title and fractional second format', () {
      final snapshot = ComicSearchRefreshQueueSnapshot(
        entries: <ComicSearchRefreshQueueEntry>[
          _entry(id: 1, title: 'Queued Comic'),
        ],
        cadence: const Duration(milliseconds: 10500),
      );

      expect(snapshot.estimatedDuration, const Duration(milliseconds: 10500));
      expect(
        snapshot.waitingMessage,
        'Queued Comic 正在等待搜索 预计耗时10.5s',
      );
    });

    test('waitingMessage keeps integer second format when tenths end with zero', () {
      final snapshot = ComicSearchRefreshQueueSnapshot(
        entries: <ComicSearchRefreshQueueEntry>[
          _entry(id: 1, title: 'Queued Comic'),
        ],
        cadence: const Duration(seconds: 10),
      );

      expect(snapshot.estimatedDuration, const Duration(seconds: 10));
      expect(
        snapshot.waitingMessage,
        'Queued Comic 正在等待搜索 预计耗时10s',
      );
    });

    test('waitingMessage returns null when head title is blank', () {
      final snapshot = ComicSearchRefreshQueueSnapshot(
        entries: <ComicSearchRefreshQueueEntry>[
          _entry(id: 1, title: '   '),
        ],
        cadence: const Duration(milliseconds: 10500),
      );

      expect(snapshot.waitingMessage, isNull);
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
