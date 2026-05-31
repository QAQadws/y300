import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/comic_task_progress.dart';
import 'package:y300/features/comic/data/comic_refresh_workflow_providers.dart';
import 'package:y300/features/favorites/data/favorite_task_progress.dart';
import 'package:y300/features/favorites/data/favorite_providers.dart';
import 'package:y300/features/library_shared/data/library_task_progress_providers.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_task_progress_hub.dart';

export 'package:y300/features/library_shared/data/library_task_progress_providers.dart'
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
  final registration = hub.registerSource(
    modules: const <LibraryModuleKey>{LibraryModuleKey.favorite},
    progress: FavoriteSyncShelfTaskProgressListenable(service.progress),
    priority: LibraryTaskProgressPriority.high,
  );
  ref.onDispose(registration.dispose);
  return registration;
});

final comicSearchQueueTaskProgressRegistrationWorkflowProvider =
    Provider<LibraryTaskProgressRegistration>((ref) {
  final snapshot = ref.watch(comicSearchRefreshQueueSnapshotProvider);
  final hub = ref.watch(libraryTaskProgressHubProvider);
  final registration = hub.registerSource(
    modules: const <LibraryModuleKey>{
      LibraryModuleKey.comic,
      LibraryModuleKey.favorite,
    },
    progress: ComicSearchQueueShelfTaskProgressListenable(snapshot),
    priority: LibraryTaskProgressPriority.normal,
  );
  ref.onDispose(registration.dispose);
  return registration;
});
