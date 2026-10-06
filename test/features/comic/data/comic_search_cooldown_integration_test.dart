import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/persistence/app_database.dart';
import 'package:y300/features/comic/data/repositories/local_comic_repository.dart';
import 'package:y300/features/comic/data/repositories/local_comic_search_refresh_queue_repository.dart';
import 'package:y300/features/comic/data/services/comic_favorite_ingest_service.dart';
import 'package:y300/features/comic/data/services/network_comic_episode_refresh_service.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/repositories/comic_catalog_directory_reader.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_episode_link_merger.dart';
import 'package:y300/features/comic/domain/services/comic_episode_refresh_service.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';
import 'package:y300/features/comic/domain/services/comic_post_aggregation_service.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_keyword_resolver.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_search_candidate_ranker.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/comic/domain/services/html_comic_parser_service.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/search/data/services/forum_search_coordinator.dart';
import 'package:y300/features/search/data/services/search_rate_limiter.dart';

import '../../../test_support/unavailable_library_cover_store.dart';
import '../domain/services/deathpair_discovery_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'queued comic waits through shared cooldown before adding final act',
    () async {
      var now = DateTime(2026, 10, 6, 12);
      final cooldownStarted = Completer<void>();
      final releaseCooldown = Completer<void>();
      Duration? requestedDelay;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final searchRepository = _SearchRepository(nowProvider: () => now);
      final scheduler = ForumSearchReadScheduler(
        repository: searchRepository,
        rateLimiter: SearchRateLimiter(
          sharedPreferences: preferences,
          nowProvider: () => now,
        ),
        nowProvider: () => now,
        delay: (duration) async {
          requestedDelay = duration;
          cooldownStarted.complete();
          await releaseCooldown.future;
          now = now.add(duration);
        },
      );
      final database = AppDatabase.open(databaseName: inMemoryDatabasePath);
      final comics = LocalComicRepository(
        database,
        libraryCoverStore: const UnavailableLibraryCoverStore(),
      );
      final queueRepository = LocalComicSearchRefreshQueueRepository(database);
      final remote = _DiscoveryRepository();
      final bus = LibraryShelfRefreshBus();
      const subjectParser = RuleBasedComicSubjectParser();
      final refresh = NetworkComicEpisodeRefreshService(
        discoveryService: ComicEpisodeDiscoveryService(
          repository: remote,
          opPostParser: ComicConsecutiveOpPostParser(
            engine: ComicPostParsingEngine(),
          ),
          catalogDirectoryReader: _EmptyCatalogReader(),
        ),
        searchService: scheduler,
        keywordResolver: const DefaultComicRefreshKeywordResolver(
          subjectParser: subjectParser,
        ),
        candidateRanker: const DefaultComicSearchCandidateRanker(),
        episodeLinkMerger: const DefaultComicEpisodeLinkMerger(
          subjectParser: subjectParser,
        ),
      );
      final queue = ComicSearchRefreshQueueService(
        queueRepository: queueRepository,
        refreshService: refresh,
        refreshOutcomeApplier: DefaultComicRefreshOutcomeApplier(
          repository: comics,
          firstEpisodeCoverPromoter: ComicFirstEpisodeCoverService(
            repository: comics,
          ),
          shelfRefreshBus: bus,
        ),
        nowProvider: () => now,
      );
      addTearDown(() async {
        if (!releaseCooldown.isCompleted) releaseCooldown.complete();
        await queue.drainForTest();
        queue.dispose();
        scheduler.dispose();
        bus.dispose();
        await (await database).close();
      });
      final source = _sourceDetail();
      final comicId =
          await RepositoryComicFavoriteIngestService(
            repository: comics,
            parserService: HtmlComicParserService(
              engine: ComicPostParsingEngine(),
            ),
            subjectParser: subjectParser,
            aggregationService: const ComicPostAggregationService(),
          ).upsertFromThreadDetail(
            detail: source,
            favoriteAddedAt: now,
            sourceTagName: '長篇連載',
          );
      expect(
        await comics.getComicEpisodes(comicId: comicId, descending: false),
        hasLength(30),
      );

      // A preceding search triggers the same persisted cooldown as in the log.
      await scheduler.search(
        const ForumSearchQuery(keyword: 'preceding comic'),
      );
      await queue.start();
      await queue.enqueue(
        request: ComicEpisodeRefreshRequest(
          comicId: comicId,
          sourceTid: deathpairSourceTid,
          displayTitle: '圣少女默示录 DEATHPAIR',
          sourceTitle: deathpairSourceSubject,
        ),
        title: '圣少女默示录 DEATHPAIR',
        origin: ComicSearchRefreshOrigin.favoriteSync,
        preloadedRootDetail: const ComicThreadDiscoveryProjector().project(
          source,
        ),
      );
      final drained = queue.drainForTest();
      // The old bug completes the task here without ever reaching the delay.
      await Future.any<void>([cooldownStarted.future, drained]);
      expect(requestedDelay, SearchRateLimiter.defaultCooldown);
      expect(scheduler.snapshot.value.active, isTrue);
      final active = await queueRepository.loadActiveEntries();
      expect(active, hasLength(1));
      expect(active.single.status, ComicSearchRefreshQueueStatus.running);
      expect(active.single.attempts, 0);
      expect(searchRepository.startedAt, hasLength(1));
      expect(
        await comics.getComicEpisodes(comicId: comicId, descending: false),
        hasLength(30),
      );

      releaseCooldown.complete();
      await drained;
      expect(searchRepository.startedAt, hasLength(2));
      expect(
        searchRepository.startedAt.last.difference(
          searchRepository.startedAt.first,
        ),
        SearchRateLimiter.defaultCooldown,
      );
      final episodes = await comics.getComicEpisodes(
        comicId: comicId,
        descending: false,
      );
      expect(episodes, hasLength(31));
      expect(episodes.last.sourceTid, deathpairFinalTid);
      expect(remote.requestedTids, [deathpairFinalTid]);
      expect(await queueRepository.loadActiveEntries(), isEmpty);
      expect(scheduler.snapshot.value.active, isFalse);
    },
  );
}

ThreadDetailData _sourceDetail() => ThreadDetailData(
  tid: deathpairSourceTid,
  fid: '30',
  typeid: '69',
  subject: deathpairSourceSubject,
  author: 'fixture',
  replies: 0,
  views: 1,
  currentPage: 1,
  perPage: 20,
  posts: [
    ThreadPost(
      pid: '1',
      author: 'fixture',
      authorId: '1',
      number: 1,
      isFirst: true,
      dateline: '2026-10-06',
      message:
          '$deathpairPreviousChaptersHtml<img src="https://img.test/source-30.jpg">',
    ),
  ],
);

class _DiscoveryRepository implements ComicThreadDiscoveryRepository {
  final requestedTids = <String>[];
  @override
  ComicThreadDiscoverySourceCapabilities get capabilities =>
      ComicThreadDiscoverySourceCapabilities(
        DataCapabilitySet.supported(ComicThreadDiscoveryCapability.values),
      );

  @override
  Future<
    DataReadResult<
      ComicThreadDiscoveryDocument,
      ComicThreadDiscoveryCapabilities
    >
  >
  load(ComicThreadDiscoveryRequest request) async {
    requestedTids.add(request.sourceTid);
    final detail = request.sourceTid == deathpairSourceTid
        ? _sourceDetail()
        : ThreadDetailData(
            tid: request.sourceTid,
            fid: '30',
            typeid: '69',
            subject: deathpairFinalSubject,
            author: 'fixture',
            replies: 0,
            views: 1,
            currentPage: 1,
            perPage: 20,
            posts: const [],
          );
    return DataReadSuccess(
      data: const ComicThreadDiscoveryProjector().project(detail),
      capabilities: ComicThreadDiscoveryCapabilities(capabilities.values),
      metadata: const DataReadMetadata.network(),
    );
  }
}

class _EmptyCatalogReader implements ComicCatalogDirectoryReader {
  @override
  Future<
    DataReadResult<ComicCatalogDirectory, ComicCatalogDirectoryCapabilities>
  >
  load(ComicCatalogDirectoryRequest request) async => DataReadSuccess(
    data: const ComicCatalogDirectory(links: <ComicEpisodeLink>[]),
    capabilities: ComicCatalogDirectoryCapabilities(
      values: DataCapabilitySet.supported(
        ComicCatalogDirectoryCapability.values,
      ),
    ),
    metadata: const DataReadMetadata.network(),
  );
}

class _SearchRepository implements ForumSearchRepository {
  _SearchRepository({required this.nowProvider});
  final DateTime Function() nowProvider;
  final startedAt = <DateTime>[];

  @override
  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>> load(
    ForumSearchQuery query, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) async {
    startedAt.add(nowProvider());
    return DataReadSuccess(
      data: ForumSearchData(
        query: query.normalized(),
        topics: [
          const ForumSearchTopicSummary(
            tid: deathpairFinalTid,
            title: deathpairFinalSubject,
            forumId: '30',
          ),
          for (var chapter = 30; chapter >= 12; chapter--)
            ForumSearchTopicSummary(
              tid: deathpairChapterTids[chapter - 1],
              title: '圣少女默示录 DEATHPAIR 第$chapter幕',
              forumId: '30',
            ),
        ],
        pagination: const ForumSearchPagination(currentPage: 1),
      ),
      capabilities: ForumSearchReadCapabilities(
        values: DataCapabilitySet.supported(ForumSearchCapability.values),
        paginationPrecision: PaginationPrecision.unknown,
      ),
      metadata: const DataReadMetadata.network(),
    );
  }

  @override
  Future<DataReadResult<ForumSearchData, ForumSearchReadCapabilities>>
  loadNextPage(
    ForumSearchQuery query,
    ForumSearchPageIdentity page, {
    CacheLoadPolicy cachePolicy = CacheLoadPolicy.cacheFirst,
  }) => throw UnimplementedError();
}
