import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/models/favorite_task_progress.dart';
import 'package:y300/features/library_shared/domain/contracts/shelf_module_adapter.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';

void main() {
  test('queue totals reach the shelf and failures stay visible after active work ends', () {
    final source = ValueNotifier<FavoriteSyncProgress>(
      const FavoriteSyncProgress(
        phase: FavoriteSyncProgressPhase.queued,
        hasQueueSummary: true,
        foregroundQueued: 25,
        automaticRemaining: 10,
        failedCount: 2,
      ),
    );
    final permission = ValueNotifier<LibraryTaskNotificationPermissionState?>(
      LibraryTaskNotificationPermissionState.granted,
    );
    final progress = FavoriteSyncShelfTaskProgressListenable(
      source,
      permission,
    );
    addTearDown(source.dispose);
    addTearDown(permission.dispose);
    addTearDown(progress.dispose);
    expect(progress.value?.active, isTrue);
    expect(progress.value?.foregroundQueued, 25);
    expect(progress.value?.automaticRemaining, 10);
    expect(progress.value?.visible, isFalse);
    source.value = const FavoriteSyncProgress(
      phase: FavoriteSyncProgressPhase.failed,
      hasQueueSummary: true,
      failedCount: 2,
    );
    expect(progress.value?.active, isFalse);
    expect(progress.value?.needsAttention, isTrue);
    expect(progress.value?.visible, isTrue);
    expect(
      progress.value?.code,
      LibraryShelfTaskProgressCode.favoriteParseNeedsAttention,
    );
  });

  group('FavoriteSyncShelfTaskProgressListenable', () {
    test(
      'maps active favorite sync progress and keeps banner visible before permission is granted',
      () {
        final source = ValueNotifier<FavoriteSyncProgress>(
          const FavoriteSyncProgress(
            phase: FavoriteSyncProgressPhase.loadingDetails,
            subject: 'Raw Favorite Title EP 09',
            current: 3,
            total: 10,
          ),
        );
        final permissionState =
            ValueNotifier<LibraryTaskNotificationPermissionState?>(null);
        addTearDown(source.dispose);
        addTearDown(permissionState.dispose);

        final listenable = FavoriteSyncShelfTaskProgressListenable(
          source,
          permissionState,
        );
        addTearDown(listenable.dispose);
        final progress = listenable.value;

        expect(progress, isNotNull);
        expect(
          progress?.code,
          LibraryShelfTaskProgressCode.favoriteSyncLoadingDetails,
        );
        expect(progress?.subject, 'Raw Favorite Title EP 09');
        expect(progress?.current, 3);
        expect(progress?.total, 10);
        expect(progress?.source, LibraryMutationSource.favoriteSync);
        expect(progress?.visible, isTrue);
        expect(progress?.reloadOnCompletion, isTrue);
      },
    );

    test(
      'granted permission hides in-app banner but keeps progress payload',
      () {
        final source = ValueNotifier<FavoriteSyncProgress>(
          const FavoriteSyncProgress(
            phase: FavoriteSyncProgressPhase.loadingDetails,
            subject: 'Raw Favorite Title EP 09',
            current: 3,
            total: 10,
          ),
        );
        final permissionState =
            ValueNotifier<LibraryTaskNotificationPermissionState?>(
              LibraryTaskNotificationPermissionState.granted,
            );
        addTearDown(source.dispose);
        addTearDown(permissionState.dispose);

        final listenable = FavoriteSyncShelfTaskProgressListenable(
          source,
          permissionState,
        );
        addTearDown(listenable.dispose);
        final progress = listenable.value;

        expect(progress, isNotNull);
        expect(progress?.subject, 'Raw Favorite Title EP 09');
        expect(progress?.visible, isFalse);
        expect(progress?.source, LibraryMutationSource.favoriteSync);
      },
    );

    test('permission changes notify listeners and update visible state', () {
      final source = ValueNotifier<FavoriteSyncProgress>(
        const FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.loadingDetails,
          subject: 'Raw Favorite Title EP 09',
          current: 1,
          total: 2,
        ),
      );
      final permissionState =
          ValueNotifier<LibraryTaskNotificationPermissionState?>(
            LibraryTaskNotificationPermissionState.denied,
          );
      addTearDown(source.dispose);
      addTearDown(permissionState.dispose);

      final listenable = FavoriteSyncShelfTaskProgressListenable(
        source,
        permissionState,
      );
      addTearDown(listenable.dispose);
      var notificationCount = 0;
      listenable.addListener(() {
        notificationCount++;
      });

      expect(listenable.value?.visible, isTrue);

      permissionState.value = LibraryTaskNotificationPermissionState.granted;

      expect(notificationCount, 1);
      expect(listenable.value?.visible, isFalse);
      expect(listenable.value?.subject, 'Raw Favorite Title EP 09');
    });

    test(
      'unsupported and permanently denied permission keep banner visible',
      () {
        for (final permission in <LibraryTaskNotificationPermissionState>[
          LibraryTaskNotificationPermissionState.unsupported,
          LibraryTaskNotificationPermissionState.permanentlyDenied,
        ]) {
          final source = ValueNotifier<FavoriteSyncProgress>(
            const FavoriteSyncProgress(
              phase: FavoriteSyncProgressPhase.loadingDetails,
              subject: 'Raw Favorite Title EP 09',
              current: 1,
              total: 2,
            ),
          );
          final permissionState =
              ValueNotifier<LibraryTaskNotificationPermissionState?>(
                permission,
              );
          addTearDown(source.dispose);
          addTearDown(permissionState.dispose);

          final listenable = FavoriteSyncShelfTaskProgressListenable(
            source,
            permissionState,
          );
          addTearDown(listenable.dispose);

          expect(listenable.value?.visible, isTrue);
        }
      },
    );

    test('returns null when favorite sync progress is not active', () {
      final permissionState =
          ValueNotifier<LibraryTaskNotificationPermissionState?>(
            LibraryTaskNotificationPermissionState.granted,
          );
      addTearDown(permissionState.dispose);

      for (final progress in <FavoriteSyncProgress>[
        FavoriteSyncProgress.idle,
        const FavoriteSyncProgress(phase: FavoriteSyncProgressPhase.completed),
        const FavoriteSyncProgress(phase: FavoriteSyncProgressPhase.failed),
      ]) {
        final source = ValueNotifier<FavoriteSyncProgress>(progress);
        addTearDown(source.dispose);

        final listenable = FavoriteSyncShelfTaskProgressListenable(
          source,
          permissionState,
        );
        addTearDown(listenable.dispose);
        expect(listenable.value, isNull);
      }
    });
  });
}
