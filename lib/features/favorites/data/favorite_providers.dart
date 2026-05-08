import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/comic_favorite_ingest_service.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/domain/services/comic_post_aggregation_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/favorites/data/favorite_repository.dart';
import 'package:y300/features/favorites/data/favorite_sync_service.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/presentation/adapters/favorite_shelf_adapter.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/novel/data/novel_favorite_ingest_service.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
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

final favoriteSyncServiceProvider = Provider<FavoriteSyncService>((ref) {
  return NetworkFavoriteSyncService(
    remoteRepository: ref.watch(favoriteRepositoryProvider),
    localRepository: ref.watch(localFavoriteRepositoryProvider),
    loadThreadDetail: (tid) => ref.read(threadRepositoryProvider).getThreadDetail(
          tid: tid,
          page: 1,
        ),
    loadTagLookup: () => ref.read(forumTagLookupProvider.future),
    classifier: ref.watch(threadContentClassifierProvider),
    comicIngestService: ref.watch(comicFavoriteIngestServiceProvider),
    novelIngestService: ref.watch(novelFavoriteIngestServiceProvider),
  );
});

final favoriteShelfAdapterProvider = Provider<FavoriteShelfAdapter>((ref) {
  return FavoriteShelfAdapter(
    ref.watch(localFavoriteRepositoryProvider),
    syncService: ref.watch(favoriteSyncServiceProvider),
    stateRepository: ref.watch(libraryStateRepositoryProvider),
  );
});
