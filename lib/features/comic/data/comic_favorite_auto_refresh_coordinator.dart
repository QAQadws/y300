import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

enum ComicFavoriteAutoRefreshStatus {
  catalogMerged,
  queuedForSearch,
  skipped,
}

class ComicFavoriteAutoRefreshResult {
  const ComicFavoriteAutoRefreshResult({
    required this.status,
    this.linkCount = 0,
    this.queuePosition,
    this.estimatedDuration,
  });

  final ComicFavoriteAutoRefreshStatus status;
  final int linkCount;
  final int? queuePosition;
  final Duration? estimatedDuration;
}

/// Runs the first automatic comic refresh after a favorite has been ingested.
///
/// This coordinator keeps favorite sync orchestration small: catalog-only
/// refresh stays immediate, while search/current-only work is delegated to the
/// durable queue introduced in stage 3.
class ComicFavoriteAutoRefreshCoordinator {
  static const String longRunningTagName = '長篇連載';

  const ComicFavoriteAutoRefreshCoordinator({
    required ComicEpisodeRefreshService refreshService,
    required ComicSearchRefreshQueueEnqueuer searchQueue,
    required ComicRefreshOutcomeApplier refreshOutcomeApplier,
    required LibraryShelfRefreshBus shelfRefreshBus,
    required ComicSubjectParser subjectParser,
  })  : _refreshService = refreshService,
        _searchQueue = searchQueue,
        _refreshOutcomeApplier = refreshOutcomeApplier,
        _shelfRefreshBus = shelfRefreshBus,
        _subjectParser = subjectParser;

  final ComicEpisodeRefreshService _refreshService;
  final ComicSearchRefreshQueueEnqueuer _searchQueue;
  final ComicRefreshOutcomeApplier _refreshOutcomeApplier;
  final LibraryShelfRefreshBus _shelfRefreshBus;
  final ComicSubjectParser _subjectParser;

  Future<ComicFavoriteAutoRefreshResult> refreshAfterFavoriteIngest({
    required String comicId,
    required ThreadDetailData detail,
    required String favoriteTitle,
    String? sourceTagName,
    bool forceSearchOnCatalogMiss = false,
  }) async {
    return refreshFavoriteComic(
      comicId: comicId,
      sourceTid: detail.tid,
      favoriteTitle: favoriteTitle,
      sourceTitle: detail.subject,
      sourceTagName: sourceTagName,
      forceSearchOnCatalogMiss: forceSearchOnCatalogMiss,
    );
  }

  Future<ComicFavoriteAutoRefreshResult> refreshFavoriteComic({
    required String comicId,
    required String sourceTid,
    required String favoriteTitle,
    String? sourceTitle,
    String? sourceTagName,
    bool forceSearchOnCatalogMiss = false,
  }) async {
    final titles = _resolveTitles(
      favoriteTitle: favoriteTitle,
      sourceTitle: sourceTitle,
      sourceTid: sourceTid,
    );
    final request = ComicEpisodeRefreshRequest(
      comicId: comicId,
      sourceTid: sourceTid,
      displayTitle: titles.searchTitle,
      sourceTitle: titles.sourceTitle,
    );

    final catalog = await _refreshService.fetchCatalogOnly(request);
    if (catalog.catalogMatched && catalog.hasLinks) {
      await _refreshOutcomeApplier.apply(
        ComicRefreshApplyRequest(
          comicId: comicId,
          sourceTid: sourceTid,
          links: catalog.links,
          source: catalog.source,
          reason: 'favorite_comic_catalog_refresh_completed',
        ),
      );
      return ComicFavoriteAutoRefreshResult(
        status: ComicFavoriteAutoRefreshStatus.catalogMerged,
        linkCount: catalog.links.length,
      );
    }

    if (!forceSearchOnCatalogMiss && !_shouldQueueSearchOnCatalogMiss(sourceTagName)) {
      // Historical/full sync keeps the conservative tag gate to avoid flooding
      // search. Directly added favorites can set forceSearchOnCatalogMiss so
      // the one comic the user just collected gets the same update treatment as
      // a detail-page manual refresh.
      _shelfRefreshBus.notify(
        modules: const <LibraryModuleKey>{
          LibraryModuleKey.comic,
          LibraryModuleKey.favorite,
        },
        reason: 'favorite_comic_catalog_miss_search_skipped',
      );
      return const ComicFavoriteAutoRefreshResult(
        status: ComicFavoriteAutoRefreshStatus.skipped,
      );
    }

    final queued = await _searchQueue.enqueue(
      request: request,
      title: titles.queueTitle,
      origin: ComicSearchRefreshOrigin.favoriteSync,
    );
    // The comic has already been ingested into the shelf.  Notify immediately
    // so the user can see the new favorite while the search queue completes
    // chapters and cover promotion in the background.
    _shelfRefreshBus.notify(
      modules: const <LibraryModuleKey>{
        LibraryModuleKey.comic,
        LibraryModuleKey.favorite,
      },
      reason: 'favorite_comic_search_refresh_queued',
    );
    return ComicFavoriteAutoRefreshResult(
      status: ComicFavoriteAutoRefreshStatus.queuedForSearch,
      queuePosition: queued.position,
      estimatedDuration: queued.estimatedDuration,
    );
  }

  String? _nonEmptyOrNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  _ResolvedFavoriteComicTitles _resolveTitles({
    required String favoriteTitle,
    required String sourceTid,
    String? sourceTitle,
  }) {
    final rawFavoriteTitle = _nonEmptyOrNull(favoriteTitle);
    final rawSourceTitle = _nonEmptyOrNull(sourceTitle);
    final parsedSourceTitle = _parseSearchTitle(rawSourceTitle);
    final parsedFavoriteTitle = _parseSearchTitle(rawFavoriteTitle);
    final searchTitle = parsedSourceTitle ??
        parsedFavoriteTitle ??
        rawFavoriteTitle ??
        rawSourceTitle ??
        sourceTid;

    return _ResolvedFavoriteComicTitles(
      // Queue title is user-facing progress text, so keep the favorite list
      // title when available. Search keywords are normalized separately above.
      queueTitle: rawFavoriteTitle ?? rawSourceTitle ?? searchTitle,
      searchTitle: searchTitle,
      sourceTitle: parsedSourceTitle ?? searchTitle,
    );
  }

  String? _parseSearchTitle(String? title) {
    final raw = _nonEmptyOrNull(title);
    if (raw == null) {
      return null;
    }
    return _nonEmptyOrNull(_subjectParser.parse(raw).normalizedTitle) ?? raw;
  }

  bool _shouldQueueSearchOnCatalogMiss(String? sourceTagName) {
    return _nonEmptyOrNull(sourceTagName) == longRunningTagName;
  }
}

class _ResolvedFavoriteComicTitles {
  const _ResolvedFavoriteComicTitles({
    required this.queueTitle,
    required this.searchTitle,
    required this.sourceTitle,
  });

  final String queueTitle;
  final String searchTitle;
  final String sourceTitle;
}
