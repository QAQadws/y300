import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/favorites/data/services/favorite_detail_context_loader.dart';
import 'package:y300/features/favorites/data/providers/favorite_ingest_providers.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/favorites/data/use_cases/favorite_shelf_category_assign_use_case_impl.dart';
import 'package:y300/features/favorites/data/services/favorite_link_service_impl.dart';
import 'package:y300/features/favorites/data/repositories/favorite_directory_repositories.dart';
import 'package:y300/features/favorites/data/services/favorite_shelf_bootstrapper.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/use_cases/unfavorite_use_case_providers.dart';
import 'package:y300/features/favorites/domain/services/favorite_link_service.dart';
import 'package:y300/features/favorites/domain/services/favorite_shelf_bootstrapper.dart';
import 'package:y300/features/favorites/presentation/adapters/favorite_shelf_adapter.dart';
import 'package:y300/features/library_shared/data/providers/library_task_workflow_providers.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/shelf_category_assign_use_case.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/features/tags/data/providers/tag_providers.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

export 'package:y300/features/favorites/data/use_cases/unfavorite_use_case_providers.dart';

final localFavoriteRepositoryProvider = Provider<LocalFavoriteRepository>((
  ref,
) {
  return SqfliteLocalFavoriteRepository(ComicLocalDb.open());
});

final favoriteDetailContextLoaderProvider =
    Provider<FavoriteDetailContextLoader>((ref) {
      return DefaultFavoriteDetailContextLoader(
        threadRepository: ref.read(threadJsonRepositoryProvider),
        loadTagLookup: () => ref.read(forumTagLookupProvider.future),
        classifier: ref.watch(threadContentClassifierProvider),
      );
    });

final favoriteSyncServiceProvider = Provider<FavoriteSyncService>((ref) {
  return NetworkFavoriteSyncService(
    remoteRepository: ref.watch(favoriteThreadDirectoryRepositoryProvider),
    localRepository: ref.watch(localFavoriteRepositoryProvider),
    detailContextLoader: ref.watch(favoriteDetailContextLoaderProvider),
    contentIngestRegistry: ref.watch(favoriteContentIngestRegistryProvider),
    postIngestTaskRunner: ref.watch(libraryPostIngestTaskRunnerProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
    downloadStorageService: ref.watch(downloadStorageServiceProvider),
    governorFactory: DefaultFavoriteFirstSyncRequestGovernor.new,
  );
});

final favoriteLinkServiceProvider = Provider<FavoriteLinkService>((ref) {
  return DefaultFavoriteLinkService(
    repository: ref.watch(localFavoriteRepositoryProvider),
  );
});

final favoriteShelfBootstrapperProvider = Provider<FavoriteShelfBootstrapper>((
  ref,
) {
  return DefaultFavoriteShelfBootstrapper(
    repository: ref.watch(localFavoriteRepositoryProvider),
    syncService: ref.watch(favoriteSyncServiceProvider),
  );
});

final favoriteShelfCategoryAssignUseCaseProvider =
    Provider<ShelfCategoryAssignUseCase>((ref) {
      return DefaultFavoriteShelfCategoryAssignUseCase(
        repository: ref.watch(localFavoriteRepositoryProvider),
      );
    });

final favoriteShelfAdapterProvider = Provider<FavoriteShelfAdapter>((ref) {
  return FavoriteShelfAdapter(
    ref.watch(localFavoriteRepositoryProvider),
    syncService: ref.watch(favoriteSyncServiceProvider),
    taskProgressHub: ref.watch(libraryTaskProgressHubWorkflowProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
    categoryAssignUseCaseResolver: () =>
        ref.read(favoriteShelfCategoryAssignUseCaseProvider),
    unfavoriteThreadUseCaseResolver: () =>
        ref.read(unfavoriteThreadUseCaseProvider),
  );
});
