import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local_comic_search_refresh_queue_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ComicSearchRefreshQueueService', () {
    test('worker merges search/current result, promotes cover, and completes task', () async {
      const dbName = 'comic_search_refresh_queue_worker_success_test.db';
      await deleteDatabase(dbName);
      final dbFuture = ComicLocalDb.open(databaseName: dbName);
      final queueRepository = LocalComicSearchRefreshQueueRepository(dbFuture);
      final comicRepository = _RecordingComicRepository();
      final promoter = _RecordingCoverPromoter();
      final refreshService = _FakeRefreshService(
        outcome: const ComicEpisodeRefreshOutcome(
          source: ComicEpisodeRefreshSource.search,
          usedSearch: true,
          links: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
          ],
        ),
      );
      final bus = LibraryShelfRefreshBus();
      final service = ComicSearchRefreshQueueService(
        queueRepository: queueRepository,
        comicRepository: comicRepository,
        refreshService: refreshService,
        firstEpisodeCoverPromoter: promoter,
        shelfRefreshBus: bus,
      );

      await service.start();
      await service.enqueue(
        request: _request(),
        title: '测试漫画',
        origin: ComicSearchRefreshOrigin.favoriteSync,
      );
      await service.drainForTest();

      expect(comicRepository.mergedComicId, 'comic:1');
      expect(comicRepository.mergedLinks, hasLength(1));
      expect(promoter.promotedComicIds, <String>['comic:1']);
      expect(await queueRepository.loadActiveEntries(), isEmpty);
      expect(bus.signal.value?.modules, contains(LibraryModuleKey.comic));
      expect(bus.signal.value?.modules, contains(LibraryModuleKey.favorite));

      service.dispose();
      final db = await dbFuture;
      await db.close();
      await deleteDatabase(dbName);
    });

    test('worker stores last_error and delays retry after failure', () async {
      const dbName = 'comic_search_refresh_queue_worker_retry_test.db';
      await deleteDatabase(dbName);
      final dbFuture = ComicLocalDb.open(databaseName: dbName);
      final queueRepository = LocalComicSearchRefreshQueueRepository(dbFuture);
      final now = DateTime(2026, 5, 16, 12, 0, 0);
      final service = ComicSearchRefreshQueueService(
        queueRepository: queueRepository,
        comicRepository: _RecordingComicRepository(),
        refreshService: _ThrowingRefreshService(),
        firstEpisodeCoverPromoter: _RecordingCoverPromoter(),
        shelfRefreshBus: LibraryShelfRefreshBus(),
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

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinks(
    ComicEpisodeRefreshRequest request,
  ) async {
    return _outcome.links;
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    return const ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.empty,
      links: <ComicEpisodeLink>[],
    );
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    return _outcome;
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    return _outcome.links;
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
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    throw StateError('boom');
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
  List<ComicEpisodeLink> mergedLinks = const <ComicEpisodeLink>[];

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    mergedComicId = comicId;
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
