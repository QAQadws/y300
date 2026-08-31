import 'package:flutter_test/flutter_test.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/local_comic_search_refresh_queue_repository.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/domain/services/comic_thread_discovery_cache.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_request_governor.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ComicSearchRefreshQueueService', () {
    test('worker applies search/current result and completes task', () async {
      const dbName = 'comic_search_refresh_queue_worker_success_test.db';
      await deleteDatabase(dbName);
      final dbFuture = ComicLocalDb.open(databaseName: dbName);
      final queueRepository = LocalComicSearchRefreshQueueRepository(dbFuture);
      final refreshService = _FakeRefreshService(
        outcome: const ComicEpisodeRefreshOutcome(
          source: ComicEpisodeRefreshSource.search,
          usedSearch: true,
          links: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
          ],
        ),
      );
      final applier = _RecordingRefreshOutcomeApplier();
      final service = ComicSearchRefreshQueueService(
        queueRepository: queueRepository,
        refreshService: refreshService,
        refreshOutcomeApplier: applier,
      );

      await service.start();
      await service.enqueue(
        request: _request(),
        title: '测试漫画',
        origin: ComicSearchRefreshOrigin.favoriteSync,
      );
      await service.drainForTest();

      expect(applier.requests, hasLength(1));
      expect(applier.requests.single.comicId, 'comic:1');
      expect(applier.requests.single.sourceTid, '100');
      expect(applier.requests.single.reason, 'comic_search_refresh_completed');
      expect(applier.requests.single.source, ComicEpisodeRefreshSource.search);
      expect(
        applier.requests.single.mutationSource,
        LibraryMutationSource.comicSearchQueue,
      );
      expect(applier.requests.single.links, hasLength(1));
      expect(await queueRepository.loadActiveEntries(), isEmpty);

      service.dispose();
      final db = await dbFuture;
      await db.close();
      await deleteDatabase(dbName);
    });

    test('worker forwards discovered catalogUrl to refresh applier', () async {
      const dbName = 'comic_search_refresh_queue_catalog_url_test.db';
      await deleteDatabase(dbName);
      final dbFuture = ComicLocalDb.open(databaseName: dbName);
      final queueRepository = LocalComicSearchRefreshQueueRepository(dbFuture);
      final refreshService = _FakeRefreshService(
        outcome: const ComicEpisodeRefreshOutcome(
          source: ComicEpisodeRefreshSource.search,
          usedSearch: true,
          links: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
          ],
          catalogUrl: 'https://bbs.yamibo.com/misc.php?mod=tag&id=18235',
        ),
      );
      final applier = _RecordingRefreshOutcomeApplier();
      final service = ComicSearchRefreshQueueService(
        queueRepository: queueRepository,
        refreshService: refreshService,
        refreshOutcomeApplier: applier,
      );

      await service.start();
      await service.enqueue(
        request: _request(),
        title: '测试漫画',
        origin: ComicSearchRefreshOrigin.favoriteSync,
      );
      await service.drainForTest();

      expect(applier.requests, hasLength(1));
      expect(
        applier.requests.single.catalogUrl,
        'https://bbs.yamibo.com/misc.php?mod=tag&id=18235',
      );

      service.dispose();
      final db = await dbFuture;
      await db.close();
      await deleteDatabase(dbName);
    });

    test('worker skips applier when no links are found', () async {
      const dbName = 'comic_search_refresh_queue_worker_empty_test.db';
      await deleteDatabase(dbName);
      final dbFuture = ComicLocalDb.open(databaseName: dbName);
      final queueRepository = LocalComicSearchRefreshQueueRepository(dbFuture);
      final refreshService = _FakeRefreshService(
        outcome: const ComicEpisodeRefreshOutcome(
          source: ComicEpisodeRefreshSource.empty,
          links: <ComicEpisodeLink>[],
        ),
      );
      final applier = _RecordingRefreshOutcomeApplier();
      final service = ComicSearchRefreshQueueService(
        queueRepository: queueRepository,
        refreshService: refreshService,
        refreshOutcomeApplier: applier,
      );

      await service.start();
      await service.enqueue(
        request: _request(),
        title: '测试漫画',
        origin: ComicSearchRefreshOrigin.favoriteSync,
      );
      await service.drainForTest();

      expect(applier.requests, isEmpty);
      expect(await queueRepository.loadActiveEntries(), isEmpty);

      service.dispose();
      final db = await dbFuture;
      await db.close();
      await deleteDatabase(dbName);
    });

    test(
      'worker forwards preloadedRootDetail captured at enqueue time',
      () async {
        const dbName = 'comic_search_refresh_queue_preloaded_test.db';
        await deleteDatabase(dbName);
        final dbFuture = ComicLocalDb.open(databaseName: dbName);
        final queueRepository = LocalComicSearchRefreshQueueRepository(
          dbFuture,
        );
        final refreshService = _FakeRefreshService(
          outcome: const ComicEpisodeRefreshOutcome(
            source: ComicEpisodeRefreshSource.empty,
            links: <ComicEpisodeLink>[],
          ),
        );
        final service = ComicSearchRefreshQueueService(
          queueRepository: queueRepository,
          refreshService: refreshService,
          refreshOutcomeApplier: _RecordingRefreshOutcomeApplier(),
        );

        final detail = ThreadDetailData(
          tid: '100',
          fid: '5',
          subject: '预加载主题',
          author: 'tester',
          replies: 0,
          views: 0,
          currentPage: 1,
          perPage: 20,
          posts: const <ThreadPost>[],
        );

        await service.start();
        await service.enqueue(
          request: _request(),
          title: '测试漫画',
          origin: ComicSearchRefreshOrigin.favoriteSync,
          preloadedRootDetail: const ComicThreadDiscoveryProjector().project(
            detail,
          ),
        );
        await service.drainForTest();

        expect(refreshService.receivedPreloadedRootDetails, hasLength(1));
        expect(refreshService.receivedPreloadedRootDetails.single?.tid, '100');
        expect(
          refreshService.receivedPreloadedRootDetails.single?.subject,
          '预加载主题',
        );

        service.dispose();
        final db = await dbFuture;
        await db.close();
        await deleteDatabase(dbName);
      },
    );

    test(
      'preloadedRootDetail is dropped when tid does not match request',
      () async {
        const dbName = 'comic_search_refresh_queue_preloaded_mismatch_test.db';
        await deleteDatabase(dbName);
        final dbFuture = ComicLocalDb.open(databaseName: dbName);
        final queueRepository = LocalComicSearchRefreshQueueRepository(
          dbFuture,
        );
        final refreshService = _FakeRefreshService(
          outcome: const ComicEpisodeRefreshOutcome(
            source: ComicEpisodeRefreshSource.empty,
            links: <ComicEpisodeLink>[],
          ),
        );
        final service = ComicSearchRefreshQueueService(
          queueRepository: queueRepository,
          refreshService: refreshService,
          refreshOutcomeApplier: _RecordingRefreshOutcomeApplier(),
        );

        final detail = ThreadDetailData(
          tid: '999',
          fid: '5',
          subject: '不匹配主题',
          author: 'tester',
          replies: 0,
          views: 0,
          currentPage: 1,
          perPage: 20,
          posts: const <ThreadPost>[],
        );

        await service.start();
        await service.enqueue(
          request: _request(),
          title: '测试漫画',
          origin: ComicSearchRefreshOrigin.favoriteSync,
          preloadedRootDetail: const ComicThreadDiscoveryProjector().project(
            detail,
          ),
        );
        await service.drainForTest();

        expect(refreshService.receivedPreloadedRootDetails, hasLength(1));
        expect(refreshService.receivedPreloadedRootDetails.single, isNull);

        service.dispose();
        final db = await dbFuture;
        await db.close();
        await deleteDatabase(dbName);
      },
    );

    test('worker stores last_error and delays retry after failure', () async {
      const dbName = 'comic_search_refresh_queue_worker_retry_test.db';
      await deleteDatabase(dbName);
      final dbFuture = ComicLocalDb.open(databaseName: dbName);
      final queueRepository = LocalComicSearchRefreshQueueRepository(dbFuture);
      final now = DateTime(2026, 5, 16, 12, 0, 0);
      final service = ComicSearchRefreshQueueService(
        queueRepository: queueRepository,
        refreshService: _ThrowingRefreshService(),
        refreshOutcomeApplier: _RecordingRefreshOutcomeApplier(),
        retryPolicy: const ComicSearchRefreshRetryPolicy(
          maxAttempts: 3,
          initialDelay: Duration(seconds: 5),
        ),
        nowProvider: () => now,
      );

      await service.start();
      await service.enqueue(
        request: _request(),
        title: '测试漫画',
        origin: ComicSearchRefreshOrigin.favoriteSync,
      );
      await service.drainForTest();
      final active = await queueRepository.loadActiveEntries();

      expect(active, hasLength(1));
      expect(active.single.status, ComicSearchRefreshQueueStatus.pending);
      expect(active.single.attempts, 1);
      expect(active.single.lastError, contains('boom'));
      expect(active.single.availableAt, now.add(const Duration(seconds: 5)));

      service.dispose();
      final db = await dbFuture;
      await db.close();
      await deleteDatabase(dbName);
    });
  });
}

ComicEpisodeRefreshRequest _request() {
  return const ComicEpisodeRefreshRequest(
    comicId: 'comic:1',
    sourceTid: '100',
    displayTitle: '测试漫画',
    sourceTitle: '测试漫画 来源',
  );
}

class _FakeRefreshService implements ComicEpisodeRefreshService {
  _FakeRefreshService({required ComicEpisodeRefreshOutcome outcome})
    : _outcome = outcome;

  final ComicEpisodeRefreshOutcome _outcome;
  final List<ComicThreadDiscoveryDocument?> receivedPreloadedRootDetails =
      <ComicThreadDiscoveryDocument?>[];

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogOnly(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
    ComicThreadDiscoveryCache? threadCache,
  }) async {
    return const ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.empty,
      links: <ComicEpisodeLink>[],
    );
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogThenFallback(
    ComicEpisodeRefreshRequest request,
  ) async {
    return _outcome;
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinks(
    ComicEpisodeRefreshRequest request,
  ) async {
    return _outcome.links;
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    return _outcome.links;
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogDirect(
    String catalogUrl, {
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    return const ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.empty,
      links: <ComicEpisodeLink>[],
    );
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
    ComicThreadDiscoveryCache? threadCache,
  }) async {
    receivedPreloadedRootDetails.add(preloadedRootDetail);
    return _outcome;
  }
}

class _ThrowingRefreshService extends _FakeRefreshService {
  _ThrowingRefreshService()
    : super(
        outcome: const ComicEpisodeRefreshOutcome(
          source: ComicEpisodeRefreshSource.empty,
          links: <ComicEpisodeLink>[],
        ),
      );

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogThenFallback(
    ComicEpisodeRefreshRequest request,
  ) async {
    throw StateError('boom');
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
    ComicThreadDiscoveryCache? threadCache,
  }) async {
    throw StateError('boom');
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
