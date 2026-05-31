import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/favorite_task_progress.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

void main() {
  group('FavoriteSyncShelfTaskProgressListenable current baseline', () {
    test('maps active favorite sync progress and preserves raw title in message', () {
      final source = ValueNotifier<FavoriteSyncProgress>(
        const FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.loadingDetails,
          message: 'parsing: Raw Favorite Title EP 09',
          current: 3,
          total: 10,
        ),
      );
      addTearDown(source.dispose);

      final listenable = FavoriteSyncShelfTaskProgressListenable(source);
      final progress = listenable.value;

      expect(progress, isNotNull);
      expect(progress?.message, 'parsing: Raw Favorite Title EP 09');
      expect(progress?.current, 3);
      expect(progress?.total, 10);
      expect(progress?.source, LibraryMutationSource.favoriteSync);
      expect(progress?.reloadOnCompletion, isTrue);
    });

    test('returns null when favorite sync progress is not active', () {
      for (final progress in <FavoriteSyncProgress>[
        FavoriteSyncProgress.idle,
        const FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.completed,
          message: 'done',
        ),
        const FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.failed,
          message: 'failed',
        ),
      ]) {
        final source = ValueNotifier<FavoriteSyncProgress>(progress);
        addTearDown(source.dispose);

        final listenable = FavoriteSyncShelfTaskProgressListenable(source);
        expect(listenable.value, isNull);
      }
    });
  });
}
