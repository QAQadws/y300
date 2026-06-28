import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/models/comic_task_progress.dart';
import 'package:y300/features/comic/data/providers/comic_refresh_workflow_providers.dart';
import 'package:y300/features/favorites/data/models/favorite_task_progress.dart';
import 'package:y300/features/favorites/data/providers/favorite_providers.dart';
import 'package:y300/features/library_shared/data/services/library_task_notification_bridge_impl.dart';
import 'package:y300/features/library_shared/data/providers/library_task_notification_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_task_progress_providers.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_task_notification_bridge.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';

export 'package:y300/features/library_shared/data/providers/library_task_progress_providers.dart'
    show libraryTaskProgressHubProvider;

final libraryTaskProgressHubWorkflowProvider =
    Provider<LibraryTaskProgressHub>((ref) {
  return ref.watch(libraryTaskProgressHubProvider);
});

final favoriteSyncTaskProgressRegistrationProvider =
    Provider<LibraryTaskProgressRegistration>((ref) {
  return ref.watch(favoriteSyncTaskProgressRegistrationWorkflowProvider);
});

final comicSearchQueueTaskProgressRegistrationProvider =
    Provider<LibraryTaskProgressRegistration>((ref) {
  return ref.watch(comicSearchQueueTaskProgressRegistrationWorkflowProvider);
});

final favoriteSyncTaskProgressRegistrationWorkflowProvider =
    Provider<LibraryTaskProgressRegistration>((ref) {
  final service = ref.watch(favoriteSyncServiceProvider);
  final hub = ref.watch(libraryTaskProgressHubProvider);
  final notificationService = ref.watch(libraryTaskNotificationServiceProvider);
  final progress = FavoriteSyncShelfTaskProgressListenable(
    service.progress,
    notificationService.permissionState,
  );
  final registration = hub.registerSource(
    modules: const <LibraryModuleKey>{LibraryModuleKey.favorite},
    progress: progress,
    priority: LibraryTaskProgressPriority.high,
  );
  ref.onDispose(() {
    registration.dispose();
    progress.dispose();
  });
  return registration;
});

final comicSearchQueueTaskProgressRegistrationWorkflowProvider =
    Provider<LibraryTaskProgressRegistration>((ref) {
  final snapshot = ref.watch(comicSearchRefreshQueueSnapshotProvider);
  final hub = ref.watch(libraryTaskProgressHubProvider);
  final notificationService = ref.watch(libraryTaskNotificationServiceProvider);
  final progress = ComicSearchQueueShelfTaskProgressListenable(
    snapshot,
    notificationService.permissionState,
  );
  final registration = hub.registerSource(
    modules: const <LibraryModuleKey>{
      LibraryModuleKey.comic,
      LibraryModuleKey.favorite,
    },
    progress: progress,
    priority: LibraryTaskProgressPriority.normal,
  );
  ref.onDispose(() {
    registration.dispose();
    progress.dispose();
  });
  return registration;
});

/// Bridges hub task progress to the system notification shade (stage 4).
///
/// Watching this provider once (see `MainShellPage`) starts the bridge so
/// favorite-sync and comic-search-queue progress surface as OS notifications.
/// The bridge depends only on the hub and the notification service, keeping it
/// a thin presentation adapter.
final libraryTaskNotificationBridgeProvider =
    Provider<LibraryTaskNotificationBridge>((ref) {
  final bridge = DefaultLibraryTaskNotificationBridge(
    hub: ref.watch(libraryTaskProgressHubWorkflowProvider),
    notificationService: ref.watch(libraryTaskNotificationServiceProvider),
  );
  bridge.start();
  ref.onDispose(bridge.dispose);
  return bridge;
});
