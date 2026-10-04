import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/comic/data/providers/comic_parsing_providers.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/repositories/forum_tag_comic_catalog_directory_reader.dart';
import 'package:y300/features/comic/data/services/network_comic_episode_refresh_service.dart';
import 'package:y300/features/comic/domain/repositories/comic_catalog_directory_reader.dart';
import 'package:y300/features/comic/domain/services/comic_catalog_miss_policy.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_episode_link_merger.dart';
import 'package:y300/features/comic/domain/services/comic_episode_refresh_service.dart';
import 'package:y300/features/comic/domain/services/comic_incremental_episode_discovery.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/comic/domain/services/comic_recursive_thread_eligibility_policy.dart';
import 'package:y300/features/comic/domain/services/comic_recursive_thread_request_governor.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_keyword_resolver.dart';
import 'package:y300/features/comic/domain/services/comic_search_candidate_ranker.dart';
import 'package:y300/features/search/data/services/forum_search_coordinator.dart';

final comicRecursiveThreadEligibilityPolicyProvider =
    Provider<ComicRecursiveThreadEligibilityPolicy>((ref) {
      return const DefaultComicRecursiveThreadEligibilityPolicy();
    });

final comicRecursiveThreadRequestGovernorProvider =
    Provider<ComicRecursiveThreadRequestGovernor>((ref) {
      return DefaultComicRecursiveThreadRequestGovernor();
    });

final comicCatalogDirectoryReaderProvider =
    Provider<ComicCatalogDirectoryReader>((ref) {
      return ForumTagComicCatalogDirectoryReader(
        repository: ref.watch(yamiboForumClientProvider).forumTagDirectory!,
        references: const ForumReferenceResolver(
          siteOrigin: AppConfig.siteBaseUrl,
        ),
      );
    });

final comicEpisodeDiscoveryServiceProvider =
    Provider<ComicEpisodeDiscoveryService>((ref) {
      final engine = ComicPostParsingEngine();
      final opPostParser = ComicConsecutiveOpPostParser(engine: engine);
      return ComicEpisodeDiscoveryService(
        repository: ref.watch(comicThreadDiscoveryRepositoryProvider),
        opPostParser: opPostParser,
        catalogDirectoryReader: ref.watch(comicCatalogDirectoryReaderProvider),
        eligibilityPolicy: ref.watch(
          comicRecursiveThreadEligibilityPolicyProvider,
        ),
        recursiveRequestGovernor: ref.watch(
          comicRecursiveThreadRequestGovernorProvider,
        ),
      );
    });

final comicIncrementalEpisodeDiscoveryProvider =
    Provider<ComicIncrementalEpisodeDiscovery>((ref) {
      return ComicIncrementalEpisodeDiscovery(
        repository: ref.watch(comicThreadDiscoveryRepositoryProvider),
        opPostParser: ComicConsecutiveOpPostParser(
          engine: ComicPostParsingEngine(),
        ),
        eligibilityPolicy: ref.watch(
          comicRecursiveThreadEligibilityPolicyProvider,
        ),
        recursiveRequestGovernor: ref.watch(
          comicRecursiveThreadRequestGovernorProvider,
        ),
      );
    });

final comicRefreshKeywordResolverProvider =
    Provider<ComicRefreshKeywordResolver>((ref) {
      return DefaultComicRefreshKeywordResolver(
        subjectParser: ref.read(comicSubjectParserProvider),
        featureFlags: ref.watch(comicReaderFeatureFlagsProvider),
      );
    });

final comicSearchCandidateRankerProvider = Provider<ComicSearchCandidateRanker>(
  (ref) {
    return const DefaultComicSearchCandidateRanker();
  },
);

final comicEpisodeLinkMergerProvider = Provider<ComicEpisodeLinkMerger>((ref) {
  return DefaultComicEpisodeLinkMerger(
    subjectParser: ref.read(comicSubjectParserProvider),
  );
});

final comicCatalogMissPolicyProvider = Provider<ComicCatalogMissPolicy>((ref) {
  return const DefaultComicCatalogMissPolicy();
});

final comicEpisodeRefreshServiceProvider = Provider<ComicEpisodeRefreshService>(
  (ref) {
    return NetworkComicEpisodeRefreshService(
      discoveryService: ref.read(comicEpisodeDiscoveryServiceProvider),
      searchService: ref.read(forumSearchCoordinatorProvider),
      keywordResolver: ref.watch(comicRefreshKeywordResolverProvider),
      candidateRanker: ref.watch(comicSearchCandidateRankerProvider),
      episodeLinkMerger: ref.watch(comicEpisodeLinkMergerProvider),
      threadSeedFetcher: (tid) async {
        final result = await ref
            .read(comicThreadDiscoveryRepositoryProvider)
            .load(ComicThreadDiscoveryRequest(sourceTid: tid));
        return result.when(
          success: (data, _, _) => ThreadSeed(subject: data.subject),
          failure: (_) => null,
        );
      },
    );
  },
);

final comicThreadDiscoveryRepositoryProvider =
    Provider<ComicThreadDiscoveryRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).comicThreadDiscovery!;
    });
