import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_favorite_auto_refresh_coordinator.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

void main() {
  group('ComicFavoriteAutoRefreshCoordinator', () {
    test('catalog hit merges episodes, promotes cover, and notifies shelves', () async {
      const links = <ComicEpisodeLink>[
        ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
      ];
      final repository = _RecordingComicRepository();
      final refreshService = _FakeRefreshService(
        catalogOutcome: const ComicEpisodeRefreshOutcome(
          source: ComicEpisodeRefreshSource.catalog,
          links: links,
          catalogMatched: true,
        ),
      );
      final searchQueue = _RecordingSearchQueue();
      final promoter = _RecordingCoverPromoter();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final coordinator = ComicFavoriteAutoRefreshCoordinator(
        repository: repository,
        refreshService: refreshService,
        searchQueue: searchQueue,
        firstEpisodeCoverPromoter: promoter,
        shelfRefreshBus: bus,
        subjectParser: const RuleBasedComicSubjectParser(),
      );

      final result = await coordinator.refreshAfterFavoriteIngest(
        comicId: 'comic:1',
        detail: _detail(subject: '[Scan] Catalog Comic EP 01'),
        favoriteTitle: 'Favorite List Catalog Title',
      );

      expect(result.status, ComicFavoriteAutoRefreshStatus.catalogMerged);
      expect(result.linkCount, 1);
      expect(refreshService.catalogRequests.single.displayTitle, 'Catalog Comic');
      expect(repository.mergedComicId, 'comic:1');
      expect(repository.mergedFallbackSourceTid, '100');
      expect(repository.mergedLinks, links);
      expect(promoter.promotedComicIds, <String>['comic:1']);
      expect(searchQueue.enqueuedTitles, isEmpty);
      expect(bus.signal.value?.modules, contains(LibraryModuleKey.comic));
      expect(bus.signal.value?.modules, contains(LibraryModuleKey.favorite));
    });

    test('catalog miss enqueues search queue with parsed subject title', () async {
      final repository = _RecordingComicRepository();
      final refreshService = _FakeRefreshService(
        catalogOutcome: const ComicEpisodeRefreshOutcome(
          source: ComicEpisodeRefreshSource.empty,
          links: <ComicEpisodeLink>[],
        ),
      );
      final searchQueue = _RecordingSearchQueue();
      final promoter = _RecordingCoverPromoter();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final coordinator = ComicFavoriteAutoRefreshCoordinator(
        repository: repository,
        refreshService: refreshService,
        searchQueue: searchQueue,
        firstEpisodeCoverPromoter: promoter,
        shelfRefreshBus: bus,
        subjectParser: const RuleBasedComicSubjectParser(),
      );

      final result = await coordinator.refreshAfterFavoriteIngest(
        comicId: 'comic:2',
        detail: _detail(subject: '[Scan] Parsed Search Comic EP 02'),
        favoriteTitle: 'Favorite List Raw Title',
        sourceTagName: ComicFavoriteAutoRefreshCoordinator.longRunningTagName,
      );

      expect(result.status, ComicFavoriteAutoRefreshStatus.queuedForSearch);
      expect(result.queuePosition, 2);
      expect(result.estimatedDuration, const Duration(seconds: 21));
      expect(repository.mergedComicId, isNull);
      expect(promoter.promotedComicIds, isEmpty);
      expect(searchQueue.enqueuedTitles, <String>['Favorite List Raw Title']);
      expect(searchQueue.enqueuedOrigins, <ComicSearchRefreshOrigin>[
        ComicSearchRefreshOrigin.favoriteSync,
      ]);
      expect(searchQueue.enqueuedRequests.single.comicId, 'comic:2');
      expect(searchQueue.enqueuedRequests.single.displayTitle, 'Parsed Search Comic');
      expect(searchQueue.enqueuedRequests.single.sourceTitle, 'Parsed Search Comic');
      expect(bus.signal.value?.modules, contains(LibraryModuleKey.comic));
      expect(bus.signal.value?.modules, contains(LibraryModuleKey.favorite));
      expect(bus.signal.value?.reason, 'favorite_comic_search_refresh_queued');
    });

    test('catalog miss skips search queue when tag is not long-running', () async {
      final repository = _RecordingComicRepository();
      final refreshService = _FakeRefreshService(
        catalogOutcome: const ComicEpisodeRefreshOutcome(
          source: ComicEpisodeRefreshSource.empty,
          links: <ComicEpisodeLink>[],
        ),
      );
      final searchQueue = _RecordingSearchQueue();
      final promoter = _RecordingCoverPromoter();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final coordinator = ComicFavoriteAutoRefreshCoordinator(
        repository: repository,
        refreshService: refreshService,
        searchQueue: searchQueue,
        firstEpisodeCoverPromoter: promoter,
        shelfRefreshBus: bus,
        subjectParser: const RuleBasedComicSubjectParser(),
      );

      final result = await coordinator.refreshAfterFavoriteIngest(
        comicId: 'comic:3',
        detail: _detail(subject: '[Scan] Short Comic EP 01'),
        favoriteTitle: 'Short Favorite Title',
        sourceTagName: '韓國漫畫',
      );

      expect(result.status, ComicFavoriteAutoRefreshStatus.skipped);
      expect(repository.mergedComicId, isNull);
      expect(promoter.promotedComicIds, isEmpty);
      expect(searchQueue.enqueuedTitles, isEmpty);
      expect(bus.signal.value?.modules, contains(LibraryModuleKey.comic));
      expect(bus.signal.value?.modules, contains(LibraryModuleKey.favorite));
      expect(bus.signal.value?.reason, 'favorite_comic_catalog_miss_search_skipped');
    });
  });
}

ThreadDetailData _detail({
  String tid = '100',
  String subject = '详情页标题',
}) {
  return ThreadDetailData(
    tid: tid,
    fid: '30',
    typeid: '398',
    subject: subject,
    author: '作者',
    replies: 0,
    views: 1,
    currentPage: 1,
    perPage: 20,
    posts: <ThreadPost>[
      ThreadPost(
        pid: 'p1',
        author: '作者',
        authorId: '1',
        message: '<p>正文</p>',
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
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    return const ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.empty,
      links: <ComicEpisodeLink>[],
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

class _RecordingCoverPromoter implements ComicFirstEpisodeCoverPromoter {
  final List<String> promotedComicIds = <String>[];

  @override
  Future<bool> promoteIfPossible({required String comicId}) async {
    promotedComicIds.add(comicId);
    return true;
  }
}

class _RecordingComicRepository implements ComicRepository {
  String? mergedComicId;
  String? mergedFallbackSourceTid;
  List<ComicEpisodeLink> mergedLinks = const <ComicEpisodeLink>[];

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    mergedComicId = comicId;
    mergedFallbackSourceTid = fallbackSourceTid;
    mergedLinks = episodeLinks;
    return ComicEpisodeRefreshResult(
      insertedCount: episodeLinks.length,
      updatedCount: 0,
      totalCount: episodeLinks.length,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}
