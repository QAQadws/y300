import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/services/shelf_category_assign_use_case.dart';
import 'package:y300/features/novel/data/local_novel_repository.dart';
import 'package:y300/features/novel/data/novel_download_service.dart';
import 'package:y300/features/novel/data/novel_reader_cache_service.dart';
import 'package:y300/features/novel/data/novel_repository.dart';
import 'package:y300/features/novel/data/novel_shelf_category_assign_use_case_impl.dart';
import 'package:y300/features/novel/data/novel_thread_gateway.dart';
import 'package:y300/features/novel/domain/services/novel_episode_discovery_service.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/domain/services/novel_reader_search_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_bootstrap_service.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';

final novelEpisodeDiscoveryServiceProvider =
    Provider<NovelEpisodeDiscoveryService>((ref) {
      return NovelEpisodeDiscoveryService(
        imageSourcePipeline: ref.watch(forumImageSourcePipelineProvider),
      );
    });

final novelReaderDocumentParserProvider = Provider<NovelReaderDocumentParser>((ref) {
  return const DiscuzNovelReaderDocumentParser();
});

final novelReaderSearchServiceProvider = Provider<NovelReaderSearchService>((ref) {
  return const NovelReaderSearchService();
});

final novelDownloadServiceProvider = Provider<NovelDownloadService>((ref) {
  return DefaultNovelDownloadService(
    repository: ref.watch(novelRepositoryProvider),
    storageService: ref.watch(downloadStorageServiceProvider),
    imageCacheService: ref.watch(imageCacheServiceProvider),
  );
});

final novelReaderCacheServiceProvider = Provider<NovelReaderCacheService>((ref) {
  return DefaultNovelReaderCacheService(
    downloadService: ref.watch(novelDownloadServiceProvider),
    repository: ref.watch(novelRepositoryProvider),
    stateRepository: ref.watch(libraryStateRepositoryProvider),
  );
});

final novelReaderBootstrapServiceProvider = Provider<NovelReaderBootstrapService>((
  ref,
) {
  return DefaultNovelReaderBootstrapService(
    repository: ref.watch(novelRepositoryProvider),
    downloadService: ref.watch(novelDownloadServiceProvider),
    documentParser: ref.watch(novelReaderDocumentParserProvider),
    cacheService: ref.watch(novelReaderCacheServiceProvider),
  );
});

final novelRepositoryProvider = Provider<NovelRepository>((ref) {
  return LocalNovelRepository(
    ComicLocalDb.open(),
    threadGateway: ref.watch(novelThreadGatewayProvider),
    discoveryService: ref.watch(novelEpisodeDiscoveryServiceProvider),
    imageCacheService: ref.watch(imageCacheServiceProvider),
  );
});

final novelShelfCategoryAssignUseCaseProvider =
    Provider<ShelfCategoryAssignUseCase>((ref) {
      return DefaultNovelShelfCategoryAssignUseCase(
        repository: ref.watch(novelRepositoryProvider),
      );
    });

final novelCoverCacheWriterProvider = Provider<NovelCoverCacheWriter?>((ref) {
  final repository = ref.watch(novelRepositoryProvider);
  return repository is NovelCoverCacheWriter
      ? repository as NovelCoverCacheWriter
      : null;
});
