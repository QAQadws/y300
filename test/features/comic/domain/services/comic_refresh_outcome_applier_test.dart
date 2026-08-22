import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/repositories/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/domain/services/comic_thread_discovery_cache.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

void main() {
  group('DefaultComicRefreshOutcomeApplier', () {
    test('returns skipped when links are empty', () async {
      final repository = _RecordingComicRepository();
      final promoter = _RecordingCoverPromoter();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final applier = DefaultComicRefreshOutcomeApplier(
        repository: repository,
        firstEpisodeCoverPromoter: promoter,
        shelfRefreshBus: bus,
      );

      final result = await applier.apply(
        const ComicRefreshApplyRequest(
          comicId: 'comic:1',
          sourceTid: '100',
          links: <ComicEpisodeLink>[],
          source: ComicEpisodeRefreshSource.empty,
          mutationSource: LibraryMutationSource.comicRefresh,
          reason: 'comic_search_refresh_completed',
        ),
      );

      expect(result.status, ComicRefreshApplyStatus.skipped);
      expect(repository.mergeCallCount, 0);
      expect(promoter.promotedComicIds, isEmpty);
      expect(bus.signal.value, isNull);
    });

    test('merges links, promotes cover, and notifies shelves', () async {
      final repository = _RecordingComicRepository();
      final promoter = _RecordingCoverPromoter(promoteResult: true);
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final applier = DefaultComicRefreshOutcomeApplier(
        repository: repository,
        firstEpisodeCoverPromoter: promoter,
        shelfRefreshBus: bus,
      );

      final result = await applier.apply(
        const ComicRefreshApplyRequest(
          comicId: 'comic:1',
          sourceTid: '100',
          links: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
          ],
          source: ComicEpisodeRefreshSource.catalog,
          mutationSource: LibraryMutationSource.comicRefresh,
          reason: 'comic_detail_catalog_refresh_completed',
        ),
      );

      expect(result.status, ComicRefreshApplyStatus.applied);
      expect(result.insertedCount, 1);
      expect(result.updatedCount, 0);
      expect(result.totalCount, 1);
      expect(result.coverPromoted, isTrue);
      expect(repository.lastComicId, 'comic:1');
      expect(repository.lastFallbackSourceTid, '100');
      expect(repository.lastLinks, hasLength(1));
      expect(promoter.promotedComicIds, <String>['comic:1']);
      expect(
        bus.signal.value?.reason,
        'comic_detail_catalog_refresh_completed',
      );
      expect(bus.signal.value?.source, LibraryMutationSource.comicRefresh);
      expect(bus.signal.value?.workId, 'comic:1');
      expect(bus.signal.value?.tid, '100');
      expect(bus.signal.value?.payload['episodeSource'], 'catalog');
      expect(bus.signal.value?.payload['insertedCount'], 1);
      expect(bus.signal.value?.payload['updatedCount'], 0);
      expect(bus.signal.value?.payload['totalCount'], 1);
      expect(bus.signal.value?.payload['coverPromoted'], true);
    });

    test('merge failure is rethrown and does not notify', () async {
      final repository = _ThrowingComicRepository();
      final promoter = _RecordingCoverPromoter();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final applier = DefaultComicRefreshOutcomeApplier(
        repository: repository,
        firstEpisodeCoverPromoter: promoter,
        shelfRefreshBus: bus,
      );

      await expectLater(
        applier.apply(
          const ComicRefreshApplyRequest(
            comicId: 'comic:1',
            sourceTid: '100',
            links: <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
            ],
            source: ComicEpisodeRefreshSource.search,
            mutationSource: LibraryMutationSource.comicSearchQueue,
            reason: 'comic_search_refresh_completed',
          ),
        ),
        throwsStateError,
      );

      expect(promoter.promotedComicIds, isEmpty);
      expect(bus.signal.value, isNull);
    });

    test('promote failure is rethrown and does not notify', () async {
      final repository = _RecordingComicRepository();
      final promoter = _ThrowingCoverPromoter();
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final applier = DefaultComicRefreshOutcomeApplier(
        repository: repository,
        firstEpisodeCoverPromoter: promoter,
        shelfRefreshBus: bus,
      );

      await expectLater(
        applier.apply(
          const ComicRefreshApplyRequest(
            comicId: 'comic:1',
            sourceTid: '100',
            links: <ComicEpisodeLink>[
              ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
            ],
            source: ComicEpisodeRefreshSource.currentOnly,
            mutationSource: LibraryMutationSource.comicRefresh,
            reason: 'comic_detail_search_refresh_completed',
          ),
        ),
        throwsStateError,
      );

      expect(repository.mergeCallCount, 1);
      expect(bus.signal.value, isNull);
    });
    test('persists catalogUrl when provided', () async {
      final repository = _RecordingComicRepository();
      final promoter = _RecordingCoverPromoter(promoteResult: true);
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final applier = DefaultComicRefreshOutcomeApplier(
        repository: repository,
        firstEpisodeCoverPromoter: promoter,
        shelfRefreshBus: bus,
      );

      await applier.apply(
        const ComicRefreshApplyRequest(
          comicId: 'comic:1',
          sourceTid: '100',
          links: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
          ],
          source: ComicEpisodeRefreshSource.catalog,
          mutationSource: LibraryMutationSource.comicRefresh,
          reason: 'comic_detail_catalog_refresh_completed',
          catalogUrl: 'https://bbs.yamibo.com/misc.php?mod=tag&id=123',
        ),
      );

      expect(repository.lastCatalogUrlComicId, 'comic:1');
      expect(
        repository.lastUpdatedCatalogUrl,
        'https://bbs.yamibo.com/misc.php?mod=tag&id=123',
      );
    });

    test('does not persist catalogUrl when null', () async {
      final repository = _RecordingComicRepository();
      final promoter = _RecordingCoverPromoter(promoteResult: true);
      final bus = LibraryShelfRefreshBus();
      addTearDown(bus.dispose);
      final applier = DefaultComicRefreshOutcomeApplier(
        repository: repository,
        firstEpisodeCoverPromoter: promoter,
        shelfRefreshBus: bus,
      );

      await applier.apply(
        const ComicRefreshApplyRequest(
          comicId: 'comic:1',
          sourceTid: '100',
          links: <ComicEpisodeLink>[
            ComicEpisodeLink(url: 'thread-101-1-1.html', rawText: '第1话'),
          ],
          source: ComicEpisodeRefreshSource.search,
          mutationSource: LibraryMutationSource.comicRefresh,
          reason: 'comic_detail_search_refresh_completed',
        ),
      );

      expect(repository.lastUpdatedCatalogUrl, isNull);
    });
  });
}

class _RecordingComicRepository implements ComicRepository {
  int mergeCallCount = 0;
  String? lastComicId;
  String? lastFallbackSourceTid;
  List<ComicEpisodeLink> lastLinks = const <ComicEpisodeLink>[];
  String? lastUpdatedCatalogUrl;
  String? lastCatalogUrlComicId;

  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) async {
    mergeCallCount++;
    lastComicId = comicId;
    lastFallbackSourceTid = fallbackSourceTid;
    lastLinks = episodeLinks;
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

  @override
  Future<void> purgeWork({required String comicId}) async {}

  @override
  Future<void> updateCatalogUrl({
    required String comicId,
    required String catalogUrl,
  }) async {
    lastCatalogUrlComicId = comicId;
    lastUpdatedCatalogUrl = catalogUrl;
  }
}

class _ThrowingComicRepository extends _RecordingComicRepository {
  @override
  Future<ComicEpisodeRefreshResult> mergeEpisodesFromLinks({
    required String comicId,
    required List<ComicEpisodeLink> episodeLinks,
    required String fallbackSourceTid,
  }) {
    throw StateError('merge failed');
  }
}

class _RecordingCoverPromoter implements ComicFirstEpisodeCoverPromoter {
  _RecordingCoverPromoter({this.promoteResult = false});

  final bool promoteResult;
  final List<String> promotedComicIds = <String>[];
  final List<ComicThreadDiscoveryCache?> capturedThreadCaches =
      <ComicThreadDiscoveryCache?>[];
  final List<FavoriteFirstSyncRequestGovernor?> capturedGovernors =
      <FavoriteFirstSyncRequestGovernor?>[];

  @override
  Future<bool> promoteIfPossible({
    required String comicId,
    ComicThreadDiscoveryCache? threadCache,
    FavoriteFirstSyncRequestGovernor? governor,
  }) async {
    promotedComicIds.add(comicId);
    capturedThreadCaches.add(threadCache);
    capturedGovernors.add(governor);
    return promoteResult;
  }
}

class _ThrowingCoverPromoter implements ComicFirstEpisodeCoverPromoter {
  @override
  Future<bool> promoteIfPossible({
    required String comicId,
    ComicThreadDiscoveryCache? threadCache,
    FavoriteFirstSyncRequestGovernor? governor,
  }) {
    throw StateError('promote failed');
  }
}
