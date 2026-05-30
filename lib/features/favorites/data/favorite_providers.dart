import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/comic/data/comic_favorite_auto_refresh_coordinator.dart';
import 'package:y300/features/comic/data/comic_favorite_ingest_service.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_search_refresh_queue_providers.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/domain/services/comic_post_aggregation_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/favorites/data/favorite_content_ingest_registry.dart';
import 'package:y300/features/favorites/data/favorite_detail_context_loader.dart';
import 'package:y300/features/favorites/data/favorite_repository.dart';
import 'package:y300/features/favorites/data/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/favorite_content_ingest.dart';
import 'package:y300/features/favorites/presentation/adapters/favorite_shelf_adapter.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/novel/data/novel_favorite_ingest_service.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/features/tags/data/tag_providers.dart';
import 'package:y300/features/thread/data/thread_repository.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

final localFavoriteRepositoryProvider = Provider<LocalFavoriteRepository>((ref) {
  return SqfliteLocalFavoriteRepository(ComicLocalDb.open());
});

final comicFavoriteIngestServiceProvider = Provider<ComicFavoriteIngestService>((ref) {
  return RepositoryComicFavoriteIngestService(
    repository: ref.watch(comicRepositoryProvider),
    parserService: ref.watch(comicParserServiceProvider),
    subjectParser: ref.watch(comicSubjectParserProvider),
    aggregationService: ref.watch(comicPostAggregationServiceProvider),
  );
});

final novelFavoriteIngestServiceProvider = Provider<NovelFavoriteIngestService>((ref) {
  return RepositoryNovelFavoriteIngestService(ref.watch(novelRepositoryProvider));
});

final comicFavoriteAutoRefreshCoordinatorProvider =
    Provider<ComicFavoriteAutoRefreshCoordinator>((ref) {
  return ComicFavoriteAutoRefreshCoordinator(
    repository: ref.watch(comicRepositoryProvider),
    refreshService: ref.watch(comicEpisodeRefreshServiceProvider),
    searchQueue: ref.watch(comicSearchRefreshQueueServiceProvider),
    firstEpisodeCoverPromoter: ref.watch(comicFirstEpisodeCoverServiceProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
    subjectParser: ref.watch(comicSubjectParserProvider),
  );
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

final comicFavoriteContentIngestHandlerProvider =
    Provider<FavoriteContentIngestHandler>((ref) {
  return ComicFavoriteContentIngestHandler(
    ingestService: ref.watch(comicFavoriteIngestServiceProvider),
    comicAutoRefreshCoordinator: ref.watch(
      comicFavoriteAutoRefreshCoordinatorProvider,
    ),
    comicDuplicateMergeService: ref.watch(comicDuplicateMergeServiceProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
  );
});

final novelFavoriteContentIngestHandlerProvider =
    Provider<FavoriteContentIngestHandler>((ref) {
  return NovelFavoriteContentIngestHandler(
    ingestService: ref.watch(novelFavoriteIngestServiceProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
  );
});

final forumFavoriteContentIngestHandlerProvider =
    Provider<FavoriteContentIngestHandler>((ref) {
  return const ForumFavoriteContentIngestHandler();
});

final favoriteContentIngestRegistryProvider =
    Provider<FavoriteContentIngestRegistry>((ref) {
  return DefaultFavoriteContentIngestRegistry(
    comicHandler: ref.watch(comicFavoriteContentIngestHandlerProvider),
    novelHandler: ref.watch(novelFavoriteContentIngestHandlerProvider),
    forumHandler: ref.watch(forumFavoriteContentIngestHandlerProvider),
  );
});

final favoriteSyncServiceProvider = Provider<FavoriteSyncService>((ref) {
  return NetworkFavoriteSyncService(
    remoteRepository: ref.watch(favoriteRepositoryProvider),
    localRepository: ref.watch(localFavoriteRepositoryProvider),
    detailContextLoader: ref.watch(favoriteDetailContextLoaderProvider),
    contentIngestRegistry: ref.watch(favoriteContentIngestRegistryProvider),
    comicAutoRefreshCoordinator: ref.watch(comicFavoriteAutoRefreshCoordinatorProvider),
    comicDuplicateMergeService: ref.watch(comicDuplicateMergeServiceProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
    downloadStorageService: ref.watch(downloadStorageServiceProvider),
  );
});

final favoriteShelfAdapterProvider = Provider<FavoriteShelfAdapter>((ref) {
  return FavoriteShelfAdapter(
    ref.watch(localFavoriteRepositoryProvider),
    syncService: ref.watch(favoriteSyncServiceProvider),
    stateRepository: ref.watch(libraryStateRepositoryProvider),
    imageCacheServiceResolver: () => ref.read(imageCacheServiceProvider),
    // 封面写回只在收藏条目确实需要缓存封面时才读取，避免收藏页初始化
    // 被漫画/小说模块的真实 provider 依赖拖住，也便于 widget 测试只覆盖收藏链路。
    comicCoverCacheWriterResolver: () => ref.read(comicCoverCacheWriterProvider),
    novelCoverCacheWriterResolver: () => ref.read(novelCoverCacheWriterProvider),
    searchQueueSnapshot: ref.watch(comicSearchRefreshQueueSnapshotProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
  );
});
