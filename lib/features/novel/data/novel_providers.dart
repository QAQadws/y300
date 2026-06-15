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
import 'package:y300/features/novel/domain/services/novel_intro_section_extractor.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/domain/services/novel_reader_search_service.dart';
import 'package:y300/features/novel/domain/services/novel_title_sanitizer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_bootstrap_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_document_build_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_layout_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_progress_committer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_supplemental_hydration_service.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';

final novelEpisodeDiscoveryServiceProvider =
    Provider<NovelEpisodeDiscoveryService>((ref) {
      return NovelEpisodeDiscoveryService(
        imageSourcePipeline: ref.watch(forumImageSourcePipelineProvider),
      );
    });

final novelTitleSanitizerProvider = Provider<NovelTitleSanitizer>((ref) {
  return const DefaultNovelTitleSanitizer();
});

final novelIntroSectionExtractorProvider =
    Provider<NovelIntroSectionExtractor>((ref) {
      return const DefaultNovelIntroSectionExtractor();
    });

final novelReaderDocumentParserProvider = Provider<NovelReaderDocumentParser>((ref) {
  return const DiscuzNovelReaderDocumentParser();
});

final novelReaderSearchServiceProvider = Provider<NovelReaderSearchService>((ref) {
  return const NovelReaderSearchService();
});

final novelReaderDocumentBuildServiceProvider =
    Provider<NovelReaderDocumentBuildService>((ref) {
      return AdaptiveNovelReaderDocumentBuildService(
        parser: ref.watch(novelReaderDocumentParserProvider),
      );
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

final novelReaderSupplementalHydrationServiceProvider =
    Provider<NovelReaderSupplementalHydrationService>((ref) {
      return DefaultNovelReaderSupplementalHydrationService(
        repository: ref.watch(novelRepositoryProvider),
        cacheService: ref.watch(novelReaderCacheServiceProvider),
      );
    });

final novelReaderBootstrapServiceProvider = Provider<NovelReaderBootstrapService>((
  ref,
) {
  return DefaultNovelReaderBootstrapService(
    repository: ref.watch(novelRepositoryProvider),
    downloadService: ref.watch(novelDownloadServiceProvider),
    documentBuildService: ref.watch(novelReaderDocumentBuildServiceProvider),
  );
});

final novelReaderLayoutServiceProvider = Provider<NovelReaderLayoutService>((ref) {
  return CachedNovelReaderLayoutService();
});

final novelReaderProgressCommitterProvider =
    Provider<NovelReaderProgressCommitter>((ref) {
      return DefaultNovelReaderProgressCommitter(
        repository: ref.watch(novelRepositoryProvider),
      );
    });

final novelRepositoryProvider = Provider<NovelRepository>((ref) {
  return LocalNovelRepository(
    ComicLocalDb.open(),
    threadGateway: ref.watch(novelThreadGatewayProvider),
    discoveryService: ref.watch(novelEpisodeDiscoveryServiceProvider),
    imageCacheService: ref.watch(imageCacheServiceProvider),
    titleSanitizer: ref.watch(novelTitleSanitizerProvider),
    introExtractor: ref.watch(novelIntroSectionExtractorProvider),
    stateRepository: ref.watch(libraryStateRepositoryProvider),
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
