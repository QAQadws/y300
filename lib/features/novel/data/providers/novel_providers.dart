import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/services/shelf_category_assign_use_case.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/novel/data/repositories/local_novel_repository.dart';
import 'package:y300/features/novel/data/preferences/novel_interaction_preferences_legacy_source.dart';
import 'package:y300/features/novel/data/preferences/novel_reader_preferences_legacy_source.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_interaction_preferences_repository.dart';
import 'package:y300/features/novel/data/preferences/shared_preferences_novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_chapter_sync_repository.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_source_metadata_repository.dart';
import 'package:y300/features/novel/data/repositories/sqflite_novel_source_state_repository.dart';
import 'package:y300/features/novel/data/services/default_novel_chapter_sync_service.dart';
import 'package:y300/features/novel/data/services/default_novel_chapter_update_service.dart';
import 'package:y300/features/novel/data/services/default_novel_sync_request_governor.dart';
import 'package:y300/features/novel/data/services/default_novel_source_metadata_recovery_service.dart';
import 'package:y300/features/novel/data/services/novel_source_metadata_ingest_service.dart';
import 'package:y300/features/novel/data/services/novel_source_metadata_recovery_gateway.dart';
import 'package:y300/features/novel/data/repositories/novel_repository.dart';
import 'package:y300/features/novel/data/use_cases/novel_shelf_category_assign_use_case_impl.dart';
import 'package:y300/features/novel/data/services/novel_thread_gateway.dart';
import 'package:y300/features/novel/data/services/thread_post_locator_novel_chapter_source_route_resolver.dart';
import 'package:y300/features/novel/domain/services/novel_author_post_episode_builder.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_sync_service.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_update_service.dart';
import 'package:y300/features/novel/domain/services/novel_first_post_catalog_extractor.dart';
import 'package:y300/features/novel/domain/services/novel_intro_section_extractor.dart';
import 'package:y300/features/novel/domain/services/novel_reader_document_parser.dart';
import 'package:y300/features/novel/domain/services/novel_reader_search_service.dart';
import 'package:y300/features/novel/domain/services/novel_title_sanitizer.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_state_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_interaction_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_reader_preferences_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_source_metadata_repository.dart';
import 'package:y300/features/novel/domain/repositories/novel_chapter_sync_repository.dart';
import 'package:y300/features/novel/domain/services/novel_post_attach_html_resolver.dart';
import 'package:y300/features/novel/domain/services/novel_chapter_source_route_resolver.dart';
import 'package:y300/features/novel/domain/services/novel_source_metadata_parser.dart';
import 'package:y300/features/novel/domain/services/novel_source_metadata_recovery_service.dart';
import 'package:y300/features/novel/domain/services/novel_sync_request_governor.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_bootstrap_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_document_build_service.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_progress_committer.dart';
import 'package:y300/features/novel/presentation/services/novel_reader_supplemental_hydration_service.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';
import 'package:y300/features/thread/domain/services/forum_post_image_source_collector.dart';
import 'package:y300/features/thread/data/providers/thread_repository_providers.dart';

final novelTitleSanitizerProvider = Provider<NovelTitleSanitizer>((ref) {
  return const DefaultNovelTitleSanitizer();
});

final novelFirstPostCatalogExtractorProvider =
    Provider<NovelFirstPostCatalogExtractor>((ref) {
      return const NovelFirstPostCatalogExtractor();
    });

final novelSourceMetadataParserProvider = Provider<NovelSourceMetadataParser>((
  ref,
) {
  return DefaultNovelSourceMetadataParser(
    catalogExtractor: ref.watch(novelFirstPostCatalogExtractorProvider),
    introExtractor: ref.watch(novelIntroSectionExtractorProvider),
    imageSourceCollector: ForumPostImageSourceCollector(
      imageSourcePipeline: ref.watch(forumImageSourcePipelineProvider),
    ),
  );
});

final novelSourceMetadataRepositoryProvider =
    Provider<NovelSourceMetadataRepository>((ref) {
      return SqfliteNovelSourceMetadataRepository(
        ComicLocalDb.open(),
        titleSanitizer: ref.watch(novelTitleSanitizerProvider),
      );
    });

final novelSourceMetadataIngestServiceProvider =
    Provider<NovelSourceMetadataIngestService>((ref) {
      return DefaultNovelSourceMetadataIngestService(
        parser: ref.watch(novelSourceMetadataParserProvider),
        repository: ref.watch(novelSourceMetadataRepositoryProvider),
      );
    });

final novelSourceStateRepositoryProvider = Provider<NovelSourceStateRepository>(
  (ref) {
    return SqfliteNovelSourceStateRepository(ComicLocalDb.open());
  },
);

final novelSyncRequestGovernorProvider = Provider<NovelSyncRequestGovernor>((
  ref,
) {
  return DefaultNovelSyncRequestGovernor();
});

final novelReaderPreferencesLegacySourceProvider =
    Provider<NovelReaderPreferencesLegacySource>((ref) {
      return SqliteNovelReaderPreferencesLegacySource(
        () => ComicLocalDb.open(),
      );
    });

final novelReaderPreferencesRepositoryProvider =
    Provider<NovelReaderPreferencesRepository>((ref) {
      return SharedPreferencesNovelReaderPreferencesRepository(
        preferencesStore: ref.watch(preferencesStoreProvider),
        legacySource: ref.watch(novelReaderPreferencesLegacySourceProvider),
      );
    });

final novelInteractionPreferencesLegacySourceProvider =
    Provider<NovelInteractionPreferencesLegacySource>((ref) {
      return SqliteNovelInteractionPreferencesLegacySource(
        () => ComicLocalDb.open(),
      );
    });

final novelInteractionPreferencesRepositoryProvider =
    Provider<NovelInteractionPreferencesRepository>((ref) {
      return SharedPreferencesNovelInteractionPreferencesRepository(
        preferencesStore: ref.watch(preferencesStoreProvider),
        legacySource: ref.watch(
          novelInteractionPreferencesLegacySourceProvider,
        ),
      );
    });

final novelChapterSourceRouteResolverProvider =
    Provider<NovelChapterSourceRouteResolver>((ref) {
      return ThreadPostLocatorNovelChapterSourceRouteResolver(
        locator: ref.watch(threadPostLocatorProvider),
      );
    });

final novelAuthorPostEpisodeBuilderProvider =
    Provider<NovelAuthorPostEpisodeBuilder>((ref) {
      final imageSourcePipeline = ref.watch(forumImageSourcePipelineProvider);
      return DefaultNovelAuthorPostEpisodeBuilder(
        imageSourcePipeline: imageSourcePipeline,
        attachResolver: NovelPostAttachHtmlResolver(
          imageSourcePipeline: imageSourcePipeline,
        ),
      );
    });

final novelChapterSyncRepositoryProvider = Provider<NovelChapterSyncRepository>(
  (ref) {
    return SqfliteNovelChapterSyncRepository(ComicLocalDb.open());
  },
);

final novelSourceMetadataRecoveryServiceProvider =
    Provider<NovelSourceMetadataRecoveryService>((ref) {
      return DefaultNovelSourceMetadataRecoveryService(
        database: ComicLocalDb.open(),
        gateway: ref.watch(novelSourceMetadataRecoveryGatewayProvider),
        parser: ref.watch(novelSourceMetadataParserProvider),
        repository: ref.watch(novelSourceMetadataRepositoryProvider),
      );
    });

final novelChapterSyncServiceProvider = Provider<NovelChapterSyncService>((
  ref,
) {
  final service = DefaultNovelChapterSyncService(
    threadGateway: ref.watch(novelThreadGatewayProvider),
    governor: ref.watch(novelSyncRequestGovernorProvider),
    episodeBuilder: ref.watch(novelAuthorPostEpisodeBuilderProvider),
    titleSanitizer: ref.watch(novelTitleSanitizerProvider),
    repository: ref.watch(novelChapterSyncRepositoryProvider),
    sourceStateRepository: ref.watch(novelSourceStateRepositoryProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final novelIntroSectionExtractorProvider = Provider<NovelIntroSectionExtractor>(
  (ref) {
    return const DefaultNovelIntroSectionExtractor();
  },
);

final novelReaderDocumentParserProvider = Provider<NovelReaderDocumentParser>((
  ref,
) {
  return const DiscuzNovelReaderDocumentParser();
});

final novelReaderSearchServiceProvider = Provider<NovelReaderSearchService>((
  ref,
) {
  return const NovelReaderSearchService();
});

final novelReaderDocumentBuildServiceProvider =
    Provider<NovelReaderDocumentBuildService>((ref) {
      return AdaptiveNovelReaderDocumentBuildService(
        parser: ref.watch(novelReaderDocumentParserProvider),
      );
    });

final novelReaderSupplementalHydrationServiceProvider =
    Provider<NovelReaderSupplementalHydrationService>((ref) {
      return DefaultNovelReaderSupplementalHydrationService(
        repository: ref.watch(novelRepositoryProvider),
      );
    });

final novelReaderBootstrapServiceProvider =
    Provider<NovelReaderBootstrapService>((ref) {
      return DefaultNovelReaderBootstrapService(
        repository: ref.watch(novelRepositoryProvider),
        preferencesRepository: ref.watch(
          novelReaderPreferencesRepositoryProvider,
        ),
        documentBuildService: ref.watch(
          novelReaderDocumentBuildServiceProvider,
        ),
      );
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
    stateRepository: ref.watch(libraryStateRepositoryProvider),
  );
});

final novelChapterUpdateServiceProvider = Provider<NovelChapterUpdateService>((
  ref,
) {
  return DefaultNovelChapterUpdateService(
    repository: ref.watch(novelRepositoryProvider),
    sourceStateRepository: ref.watch(novelSourceStateRepositoryProvider),
    syncService: ref.watch(novelChapterSyncServiceProvider),
    metadataRecoveryService: ref.watch(
      novelSourceMetadataRecoveryServiceProvider,
    ),
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
