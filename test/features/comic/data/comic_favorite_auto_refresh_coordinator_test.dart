import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_favorite_auto_refresh_coordinator.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_catalog_miss_policy.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/domain/services/title/comic_title_analyzer.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

void main() {
  const longRunningTagName = 'long-running-tag';

  group('ComicFavoriteAutoRefreshCoordinator title resolution', () {
    test('catalog hit delegates refresh application with catalog source', () async {
      const links = <ComicEpisodeLink>[
        ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: 'Episode 1'),
      ];
      final refreshService = _FakeRefreshService(
        catalogOutcome: const ComicEpisodeRefreshOutcome(
          source: ComicEpisodeRefreshSource.catalog,
          links: links,
          catalogMatched: true,
        ),
      );
      final searchQueue = _RecordingSearchQueue();
      final applier = _RecordingRefreshOutcomeApplier();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final coordinator = ComicFavoriteAutoRefreshCoordinator(
        refreshService: refreshService,
        searchQueue: searchQueue,
        refreshOutcomeApplier: applier,
        shelfRefreshBus: bus,
        catalogMissPolicy: const DefaultComicCatalogMissPolicy(
          longRunningTagName: longRunningTagName,
        ),
        titleAnalyzer: const PetitComicTitleAnalyzer(),
      );

      final result = await coordinator.refreshAfterFavoriteIngest(
        comicId: 'comic:1',
        detail: _detail(subject: '[Scan] Catalog Comic EP 01'),
        favoriteTitle: 'Favorite List Catalog Title',
      );

      expect(result.status, ComicFavoriteAutoRefreshStatus.catalogMerged);
      expect(result.linkCount, 1);
      expect(refreshService.catalogRequests.single.displayTitle, 'Catalog Comic');
      expect(applier.requests, hasLength(1));
      expect(applier.requests.single.comicId, 'comic:1');
      expect(applier.requests.single.sourceTid, '100');
      expect(applier.requests.single.links, links);
      expect(applier.requests.single.source, ComicEpisodeRefreshSource.catalog);
      expect(
        applier.requests.single.mutationSource,
        LibraryMutationSource.favoriteSync,
      );
      expect(
        applier.requests.single.reason,
        'favorite_comic_catalog_refresh_completed',
      );
      expect(searchQueue.enqueuedTitles, isEmpty);
    });

    test('catalog miss uses cleaned favorite title for queue and parsed source title for search', () async {
      final refreshService = _FakeRefreshService(
        catalogOutcome: const ComicEpisodeRefreshOutcome(
          source: ComicEpisodeRefreshSource.empty,
          links: <ComicEpisodeLink>[],
        ),
      );
      final searchQueue = _RecordingSearchQueue();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final coordinator = ComicFavoriteAutoRefreshCoordinator(
        refreshService: refreshService,
        searchQueue: searchQueue,
        refreshOutcomeApplier: _RecordingRefreshOutcomeApplier(),
        shelfRefreshBus: bus,
        catalogMissPolicy: const DefaultComicCatalogMissPolicy(
          longRunningTagName: longRunningTagName,
        ),
        titleAnalyzer: const PetitComicTitleAnalyzer(),
      );

      final result = await coordinator.refreshAfterFavoriteIngest(
        comicId: 'comic:2',
        detail: _detail(subject: '[Scan] Parsed Search Comic EP 02'),
        favoriteTitle: 'Favorite List Raw Title EP 99',
        sourceTagName: longRunningTagName,
      );

      expect(result.status, ComicFavoriteAutoRefreshStatus.queuedForSearch);
      expect(result.queuePosition, 2);
      expect(result.estimatedDuration, const Duration(seconds: 21));
      expect(
        searchQueue.enqueuedTitles,
        <String>['Favorite List Raw Title'],
      );
      expect(searchQueue.enqueuedOrigins, <ComicSearchRefreshOrigin>[
        ComicSearchRefreshOrigin.favoriteSync,
      ]);
      expect(searchQueue.enqueuedRequests.single.comicId, 'comic:2');
      expect(
        searchQueue.enqueuedRequests.single.displayTitle,
        'Parsed Search Comic',
      );
      expect(
        searchQueue.enqueuedRequests.single.sourceTitle,
        'Parsed Search Comic',
      );
      expect(bus.signal.value?.modules, contains(LibraryModuleKey.comic));
      expect(bus.signal.value?.modules, contains(LibraryModuleKey.favorite));
      expect(bus.signal.value?.reason, 'favorite_comic_search_refresh_queued');
      expect(bus.signal.value?.source, LibraryMutationSource.favoriteSync);
      expect(bus.signal.value?.workId, 'comic:2');
      expect(bus.signal.value?.tid, '100');
      expect(bus.signal.value?.payload['queuePosition'], 2);
      expect(bus.signal.value?.payload['estimatedDurationMs'], 21000);
    });

    test('catalog miss skips search queue when tag is not long-running', () async {
      final refreshService = _FakeRefreshService(
        catalogOutcome: const ComicEpisodeRefreshOutcome(
          source: ComicEpisodeRefreshSource.empty,
          links: <ComicEpisodeLink>[],
        ),
      );
      final searchQueue = _RecordingSearchQueue();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final coordinator = ComicFavoriteAutoRefreshCoordinator(
        refreshService: refreshService,
        searchQueue: searchQueue,
        refreshOutcomeApplier: _RecordingRefreshOutcomeApplier(),
        shelfRefreshBus: bus,
        catalogMissPolicy: const DefaultComicCatalogMissPolicy(
          longRunningTagName: longRunningTagName,
        ),
        titleAnalyzer: const PetitComicTitleAnalyzer(),
      );

      final result = await coordinator.refreshAfterFavoriteIngest(
        comicId: 'comic:3',
        detail: _detail(subject: '[Scan] Short Comic EP 01'),
        favoriteTitle: 'Short Favorite Title',
        sourceTagName: 'other-tag',
      );

      expect(result.status, ComicFavoriteAutoRefreshStatus.skipped);
      expect(searchQueue.enqueuedTitles, isEmpty);
      expect(bus.signal.value?.modules, contains(LibraryModuleKey.comic));
      expect(bus.signal.value?.modules, contains(LibraryModuleKey.favorite));
      expect(
        bus.signal.value?.reason,
        'favorite_comic_catalog_miss_search_skipped',
      );
      expect(bus.signal.value?.source, LibraryMutationSource.favoriteSync);
      expect(bus.signal.value?.workId, 'comic:3');
      expect(bus.signal.value?.tid, '100');
    });

    test('forced catalog miss cleans favorite title for queue and parses fallback search request', () async {
      final refreshService = _FakeRefreshService(
        catalogOutcome: const ComicEpisodeRefreshOutcome(
          source: ComicEpisodeRefreshSource.empty,
          links: <ComicEpisodeLink>[],
        ),
      );
      final searchQueue = _RecordingSearchQueue();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final coordinator = ComicFavoriteAutoRefreshCoordinator(
        refreshService: refreshService,
        searchQueue: searchQueue,
        refreshOutcomeApplier: _RecordingRefreshOutcomeApplier(),
        shelfRefreshBus: bus,
        catalogMissPolicy: const DefaultComicCatalogMissPolicy(
          longRunningTagName: longRunningTagName,
        ),
        titleAnalyzer: const PetitComicTitleAnalyzer(),
      );

      final result = await coordinator.refreshFavoriteComic(
        comicId: 'comic:4',
        sourceTid: '100',
        favoriteTitle: '[Favorite] Raw Queue Title EP 09',
        sourceTagName: 'other-tag',
        forceSearchOnCatalogMiss: true,
      );

      expect(result.status, ComicFavoriteAutoRefreshStatus.queuedForSearch);
      expect(
        searchQueue.enqueuedTitles,
        <String>['Raw Queue Title'],
      );
      expect(searchQueue.enqueuedRequests.single.comicId, 'comic:4');
      expect(
        searchQueue.enqueuedRequests.single.displayTitle,
        'Raw Queue Title',
      );
      expect(
        searchQueue.enqueuedRequests.single.sourceTitle,
        'Raw Queue Title',
      );
      expect(bus.signal.value?.reason, 'favorite_comic_search_refresh_queued');
      expect(bus.signal.value?.source, LibraryMutationSource.favoriteSync);
      expect(bus.signal.value?.workId, 'comic:4');
      expect(bus.signal.value?.tid, '100');
    });
  });
}

ThreadDetailData _detail({
  String tid = '100',
  String subject = 'Detail Title',
}) {
  return ThreadDetailData(
    tid: tid,
    fid: '30',
    typeid: '398',
    subject: subject,
    author: 'Author',
    replies: 0,
    views: 1,
    currentPage: 1,
    perPage: 20,
    posts: <ThreadPost>[
      ThreadPost(
        pid: 'p1',
        author: 'Author',
        authorId: '1',
        message: '<p>Body</p>',
        number: 1,
        isFirst: true,
        dateline: '2026-01-01',
      ),
    ],
  );
}

class _FakeRefreshService implements ComicEpisodeRefreshService {
  _FakeRefreshService({required ComicEpisodeRefreshOutcome catalogOutcome})
      : _catalogOutcome = catalogOutcome;

  final ComicEpisodeRefreshOutcome _catalogOutcome;
  final List<ComicEpisodeRefreshRequest> catalogRequests =
      <ComicEpisodeRefreshRequest>[];

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    catalogRequests.add(request);
    return _catalogOutcome;
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogThenFallback(
    ComicEpisodeRefreshRequest request,
  ) async {
    catalogRequests.add(request);
    return _catalogOutcome;
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinks(
    ComicEpisodeRefreshRequest request,
  ) async {
    return _catalogOutcome.links;
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    return _catalogOutcome.links;
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogDirect(String catalogUrl) async {
    return const ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.empty,
      links: <ComicEpisodeLink>[],
    );
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    return const ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.empty,
      links: <ComicEpisodeLink>[],
    );
  }
}

class _RecordingRefreshOutcomeApplier implements ComicRefreshOutcomeApplier {
  final List<ComicRefreshApplyRequest> requests = <ComicRefreshApplyRequest>[];

  @override
  Future<ComicRefreshApplyResult> apply(
    ComicRefreshApplyRequest request,
  ) async {
    requests.add(request);
    return ComicRefreshApplyResult(
      status: ComicRefreshApplyStatus.applied,
      insertedCount: request.links.length,
      updatedCount: 0,
      totalCount: request.links.length,
      coverPromoted: false,
    );
  }
}

class _RecordingSearchQueue implements ComicSearchRefreshQueueEnqueuer {
  final List<ComicEpisodeRefreshRequest> enqueuedRequests =
      <ComicEpisodeRefreshRequest>[];
  final List<String> enqueuedTitles = <String>[];
  final List<ComicSearchRefreshOrigin> enqueuedOrigins =
      <ComicSearchRefreshOrigin>[];

  @override
  Future<ComicSearchRefreshEnqueueResult> enqueue({
    required ComicEpisodeRefreshRequest request,
    required String title,
    required ComicSearchRefreshOrigin origin,
  }) async {
    enqueuedRequests.add(request);
    enqueuedTitles.add(title);
    enqueuedOrigins.add(origin);
    return ComicSearchRefreshEnqueueResult(
      entry: ComicSearchRefreshQueueEntry(
        id: enqueuedRequests.length,
        comicId: request.comicId ?? '',
        title: title,
        request: request,
        origin: origin,
        status: ComicSearchRefreshQueueStatus.pending,
        attempts: 0,
        availableAt: DateTime(2026, 5, 16),
        createdAt: DateTime(2026, 5, 16),
        updatedAt: DateTime(2026, 5, 16),
      ),
      position: 2,
      estimatedDuration: const Duration(seconds: 21),
      deduplicated: false,
    );
  }
}
