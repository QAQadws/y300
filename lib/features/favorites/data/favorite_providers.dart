import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/favorites/data/favorite_detail_context_loader.dart';
import 'package:y300/features/favorites/data/favorite_ingest_providers.dart';
import 'package:y300/features/favorites/data/favorite_repository.dart';
import 'package:y300/features/favorites/data/favorite_shelf_bootstrapper.dart';
import 'package:y300/features/favorites/data/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/favorite_shelf_bootstrapper.dart';
import 'package:y300/features/favorites/presentation/adapters/favorite_shelf_adapter.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/library_shared/data/library_task_workflow_providers.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/features/tags/data/tag_providers.dart';
import 'package:y300/features/thread/data/thread_repository.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

final localFavoriteRepositoryProvider = Provider<LocalFavoriteRepository>((ref) {
  return SqfliteLocalFavoriteRepository(ComicLocalDb.open());
});

final favoriteDetailContextLoaderProvider =
    Provider<FavoriteDetailContextLoader>((ref) {
  return DefaultFavoriteDetailContextLoader(
    loadThreadDetail: (tid) => ref.read(threadRepositoryProvider).getThreadDetail(
          tid: tid,
          page: 1,
        ),
    loadTagLookup: () => ref.read(forumTagLookupProvider.future),
    classifier: ref.watch(threadContentClassifierProvider),
  );
});

final favoriteSyncServiceProvider = Provider<FavoriteSyncService>((ref) {
  return NetworkFavoriteSyncService(
    remoteRepository: ref.watch(favoriteRepositoryProvider),
    localRepository: ref.watch(localFavoriteRepositoryProvider),
    detailContextLoader: ref.watch(favoriteDetailContextLoaderProvider),
    contentIngestRegistry: ref.watch(favoriteContentIngestRegistryProvider),
    postIngestTaskRunner: ref.watch(libraryPostIngestTaskRunnerProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
    downloadStorageService: ref.watch(downloadStorageServiceProvider),
  );
});

final favoriteShelfBootstrapperProvider =
    Provider<FavoriteShelfBootstrapper>((ref) {
  return DefaultFavoriteShelfBootstrapper(
    repository: ref.watch(localFavoriteRepositoryProvider),
    syncService: ref.watch(favoriteSyncServiceProvider),
  );
});

final favoriteShelfAdapterProvider = Provider<FavoriteShelfAdapter>((ref) {
  return FavoriteShelfAdapter(
    ref.watch(localFavoriteRepositoryProvider),
    syncService: ref.watch(favoriteSyncServiceProvider),
    stateRepository: ref.watch(libraryStateRepositoryProvider),
    imageCacheServiceResolver: () => ref.read(imageCacheServiceProvider),
    comicCoverCacheWriterResolver: () => ref.read(comicCoverCacheWriterProvider),
    novelCoverCacheWriterResolver: () => ref.read(novelCoverCacheWriterProvider),
    taskProgressHub: ref.watch(libraryTaskProgressHubWorkflowProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
  );
});
