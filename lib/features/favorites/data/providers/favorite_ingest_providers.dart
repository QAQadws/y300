import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/services/comic_favorite_ingest_service.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/providers/comic_refresh_workflow_providers.dart';
import 'package:y300/features/comic/domain/services/comic_post_aggregation_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/favorites/data/services/favorite_content_ingest_registry.dart';
import 'package:y300/features/favorites/data/services/library_post_ingest_task_runner.dart';
import 'package:y300/features/favorites/domain/models/favorite_content_ingest.dart';
import 'package:y300/features/favorites/domain/services/library_post_ingest_task_runner.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/novel/data/services/novel_favorite_ingest_service.dart';
import 'package:y300/features/novel/data/providers/novel_providers.dart';

final comicFavoriteIngestServiceProvider = Provider<ComicFavoriteIngestService>(
  (ref) {
    return RepositoryComicFavoriteIngestService(
      repository: ref.watch(comicRepositoryProvider),
      parserService: ref.watch(comicParserServiceProvider),
      subjectParser: ref.watch(comicSubjectParserProvider),
      aggregationService: ref.watch(comicPostAggregationServiceProvider),
    );
  },
);

final novelFavoriteIngestServiceProvider = Provider<NovelFavoriteIngestService>(
  (ref) {
    return RepositoryNovelFavoriteIngestService(
      metadataIngestService: ref.watch(
        novelSourceMetadataIngestServiceProvider,
      ),
      removeFromShelf: ({required workId}) {
        return ref
            .read(novelRepositoryProvider)
            .removeFromShelf(novelId: workId);
      },
    );
  },
);

final comicFavoriteContentIngestHandlerProvider =
    Provider<FavoriteContentIngestHandler>((ref) {
      return ComicFavoriteContentIngestHandler(
        ingestService: ref.watch(comicFavoriteIngestServiceProvider),
      );
    });

final novelFavoriteContentIngestHandlerProvider =
    Provider<FavoriteContentIngestHandler>((ref) {
      return NovelFavoriteContentIngestHandler(
        ingestService: ref.watch(novelFavoriteIngestServiceProvider),
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

final libraryPostIngestTaskRunnerProvider =
    Provider<LibraryPostIngestTaskRunner>((ref) {
      return DefaultLibraryPostIngestTaskRunner(
        comicAutoRefreshCoordinator: ref.watch(
          comicFavoriteAutoRefreshCoordinatorProvider,
        ),
        comicDuplicateMergeService: ref.watch(
          comicDuplicateMergeServiceProvider,
        ),
        shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
      );
    });
