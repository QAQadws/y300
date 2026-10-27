import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_progress.dart';
import 'package:y300/features/favorites/domain/services/favorite_parse_service.dart';

void main() {
  test('an active detail keeps its title while the directory waits and resumes its own phase afterwards', () {
    final tracker = FavoriteSyncProgressTracker();
    addTearDown(tracker.notifier.dispose);
    tracker.beginRound();
    tracker.round(
      const FavoriteSyncProgress(
        phase: FavoriteSyncProgressPhase.fetchingList,
        current: 1,
        total: 3,
      ),
    );
    tracker.queue(const FavoriteParseQueueStatus(pendingTids: {'200', '300'}));
    tracker.detail('200', 'Raw title');
    tracker.round(
      const FavoriteSyncProgress(
        phase: FavoriteSyncProgressPhase.fetchingList,
        current: 2,
        total: 3,
      ),
    );
    expect(tracker.notifier.value.subject, 'Raw title');
    expect(tracker.notifier.value.foregroundQueued, 1);
    tracker.detailSettled('200', succeeded: true);
    expect(
      tracker.notifier.value.phase,
      FavoriteSyncProgressPhase.fetchingList,
    );
    tracker.endRound();
    expect(tracker.notifier.value.isActive, isTrue);
    tracker.queue(const FavoriteParseQueueStatus());
    expect(tracker.notifier.value.phase, FavoriteSyncProgressPhase.completed);
  });

  test('failures are deduplicated and remain until explicit success and the durable status both agree', () {
    final tracker = FavoriteSyncProgressTracker();
    addTearDown(tracker.notifier.dispose);
    tracker.beginForeground('200');
    tracker.detail('200', 'Raw title');
    tracker.detailSettled('200', succeeded: false);
    tracker.queue(const FavoriteParseQueueStatus(failedTids: {'200'}));
    tracker.endForeground('200');
    expect(tracker.notifier.value.isActive, isFalse);
    expect(tracker.notifier.value.failedCount, 1);
    expect(tracker.notifier.value.phase, FavoriteSyncProgressPhase.failed);
    tracker.beginForeground('200');
    tracker.detailSettled('200', succeeded: true);
    tracker.queue(const FavoriteParseQueueStatus());
    tracker.endForeground('200');
    expect(tracker.notifier.value.phase, FavoriteSyncProgressPhase.completed);
    tracker.reset();
    expect(tracker.notifier.value, FavoriteSyncProgress.idle);
  });

  test('unfinished reconciliation is retained without claiming that parsing is active', () {
    final tracker = FavoriteSyncProgressTracker();
    addTearDown(tracker.notifier.dispose);
    tracker.beginRound();
    tracker.reconciliation(true);
    tracker.endRound();
    expect(tracker.notifier.value.phase, FavoriteSyncProgressPhase.failed);
    expect(tracker.notifier.value.needsReconciliation, isTrue);
    tracker.beginRound();
    tracker.reconciliation(false);
    tracker.endRound();
    expect(tracker.notifier.value.phase, FavoriteSyncProgressPhase.completed);
  });
}
