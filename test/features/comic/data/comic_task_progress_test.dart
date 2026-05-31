import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_task_progress.dart';
import 'package:y300/features/comic/domain/services/comic_episode_refresh_service.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_service.dart';

void main() {
  group('ComicSearchQueueShelfTaskProgressListenable', () {
    test('maps active queue snapshot message and keeps banner visible before permission is granted', () {
      final source = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot(
          entries: <ComicSearchRefreshQueueEntry>[
            _entry(id: 1, title: 'Queued Comic'),
          ],
          cadence: const Duration(milliseconds: 10500),
        ),
      );
      final permissionState =
          ValueNotifier<LibraryTaskNotificationPermissionState?>(null);
      addTearDown(source.dispose);
      addTearDown(permissionState.dispose);

      final listenable = ComicSearchQueueShelfTaskProgressListenable(
        source,
        permissionState,
      );
      addTearDown(listenable.dispose);
      final progress = listenable.value;

      expect(progress, isNotNull);
      expect(progress?.message, source.value.waitingMessage);
      expect(progress?.source, LibraryMutationSource.comicSearchQueue);
      expect(progress?.visible, isTrue);
      expect(progress?.reloadOnCompletion, isTrue);
    });

    test('granted permission hides comic queue banner', () {
      final source = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot(
          entries: <ComicSearchRefreshQueueEntry>[
            _entry(id: 1, title: 'Queued Comic'),
          ],
          cadence: const Duration(milliseconds: 10500),
        ),
      );
      final permissionState = ValueNotifier<LibraryTaskNotificationPermissionState?>(
        LibraryTaskNotificationPermissionState.granted,
      );
      addTearDown(source.dispose);
      addTearDown(permissionState.dispose);

      final listenable = ComicSearchQueueShelfTaskProgressListenable(
        source,
        permissionState,
      );
      addTearDown(listenable.dispose);

      expect(listenable.value, isNotNull);
      expect(listenable.value?.visible, isFalse);
      expect(listenable.value?.message, source.value.waitingMessage);
    });

    test('permission changes notify listeners and update visible state', () {
      final source = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot(
          entries: <ComicSearchRefreshQueueEntry>[
            _entry(id: 1, title: 'Queued Comic'),
          ],
          cadence: const Duration(milliseconds: 10500),
        ),
      );
      final permissionState = ValueNotifier<LibraryTaskNotificationPermissionState?>(
        LibraryTaskNotificationPermissionState.denied,
      );
      addTearDown(source.dispose);
      addTearDown(permissionState.dispose);

      final listenable = ComicSearchQueueShelfTaskProgressListenable(
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
      expect(listenable.value?.message, source.value.waitingMessage);
    });

    test('unsupported and permanently denied permission keep queue banner visible', () {
      for (final permission in <LibraryTaskNotificationPermissionState>[
        LibraryTaskNotificationPermissionState.unsupported,
        LibraryTaskNotificationPermissionState.permanentlyDenied,
      ]) {
        final source = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
          ComicSearchRefreshQueueSnapshot(
            entries: <ComicSearchRefreshQueueEntry>[
              _entry(id: 1, title: 'Queued Comic'),
            ],
            cadence: const Duration(milliseconds: 10500),
          ),
        );
        final permissionState =
            ValueNotifier<LibraryTaskNotificationPermissionState?>(
              permission,
            );
        addTearDown(source.dispose);
        addTearDown(permissionState.dispose);

        final listenable = ComicSearchQueueShelfTaskProgressListenable(
          source,
          permissionState,
        );
        addTearDown(listenable.dispose);

        expect(listenable.value?.visible, isTrue);
      }
    });

    test('returns null when queue snapshot is empty', () {
      final source = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
        ComicSearchRefreshQueueSnapshot.empty,
      );
      final permissionState = ValueNotifier<LibraryTaskNotificationPermissionState?>(
        LibraryTaskNotificationPermissionState.granted,
      );
      addTearDown(source.dispose);
      addTearDown(permissionState.dispose);

      final listenable = ComicSearchQueueShelfTaskProgressListenable(
        source,
        permissionState,
      );
      addTearDown(listenable.dispose);
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
