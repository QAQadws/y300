import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/domain/models/comic_detail_models.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
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
      expect(bus.signal.value?.reason, 'comic_detail_catalog_refresh_completed');
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
            reason: 'comic_detail_search_refresh_completed',
          ),
        ),
        throwsStateError,
      );

      expect(repository.mergeCallCount, 1);
      expect(bus.signal.value, isNull);
    });
  });
}

class _RecordingComicRepository implements ComicRepository {
  int mergeCallCount = 0;
  String? lastComicId;
  String? lastFallbackSourceTid;
  List<ComicEpisodeLink> lastLinks = const <ComicEpisodeLink>[];

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

  @override
  Future<bool> promoteIfPossible({required String comicId}) async {
    promotedComicIds.add(comicId);
    return promoteResult;
  }
}

class _ThrowingCoverPromoter implements ComicFirstEpisodeCoverPromoter {
  @override
  Future<bool> promoteIfPossible({required String comicId}) {
    throw StateError('promote failed');
  }
}
