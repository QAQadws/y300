import 'package:y300/features/comic/domain/services/comic_catalog_miss_policy.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/domain/services/title/comic_title_analysis.dart';
import 'package:y300/features/comic/domain/services/title/comic_title_analyzer.dart';
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
  const ComicFavoriteAutoRefreshCoordinator({
    required ComicEpisodeRefreshService refreshService,
    required ComicSearchRefreshQueueEnqueuer searchQueue,
    required ComicRefreshOutcomeApplier refreshOutcomeApplier,
    required LibraryShelfRefreshBus shelfRefreshBus,
    required ComicCatalogMissPolicy catalogMissPolicy,
    required ComicTitleAnalyzer titleAnalyzer,
  })  : _refreshService = refreshService,
        _searchQueue = searchQueue,
        _refreshOutcomeApplier = refreshOutcomeApplier,
        _shelfRefreshBus = shelfRefreshBus,
        _catalogMissPolicy = catalogMissPolicy,
        _titleAnalyzer = titleAnalyzer;

  final ComicEpisodeRefreshService _refreshService;
  final ComicSearchRefreshQueueEnqueuer _searchQueue;
  final ComicRefreshOutcomeApplier _refreshOutcomeApplier;
  final LibraryShelfRefreshBus _shelfRefreshBus;
  final ComicCatalogMissPolicy _catalogMissPolicy;
  final ComicTitleAnalyzer _titleAnalyzer;

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
          mutationSource: LibraryMutationSource.favoriteSync,
          reason: 'favorite_comic_catalog_refresh_completed',
          catalogUrl: catalog.catalogUrl,
        ),
      );
      return ComicFavoriteAutoRefreshResult(
        status: ComicFavoriteAutoRefreshStatus.catalogMerged,
        linkCount: catalog.links.length,
      );
    }

    if (!_catalogMissPolicy.shouldQueueSearchOnCatalogMiss(
      sourceTagName: sourceTagName,
      forceSearchOnCatalogMiss: forceSearchOnCatalogMiss,
    )) {
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
        source: LibraryMutationSource.favoriteSync,
        workId: comicId,
        tid: sourceTid,
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
      source: LibraryMutationSource.favoriteSync,
      workId: comicId,
      tid: sourceTid,
      payload: <String, Object?>{
        'queuePosition': queued.position,
        'estimatedDurationMs': queued.estimatedDuration.inMilliseconds,
      },
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
    final sourceAnalysis = _analyze(rawSourceTitle);
    final favoriteAnalysis = _analyze(rawFavoriteTitle);

    // Search title feeds ComicEpisodeRefreshRequest, which the keyword resolver
    // re-cleans (without length clipping) into the final search keyword. So we
    // pass the analyzer clean book name here instead of the clipped
    // searchKeyword to avoid truncating a title mid-word before the search.
    // Source title keeps precedence, mirroring the previous behavior.
    final searchTitle = _nonEmptyOrNull(sourceAnalysis?.cleanBookName) ??
        _nonEmptyOrNull(favoriteAnalysis?.cleanBookName) ??
        rawFavoriteTitle ??
        rawSourceTitle ??
        sourceTid;

    // Queue title is user-facing progress text. It must no longer leak the raw
    // forum thread title, so it uses the cleaned book name (favorite first,
    // matching the historical preference for the favorite list title).
    final queueTitle = _nonEmptyOrNull(favoriteAnalysis?.cleanBookName) ??
        _nonEmptyOrNull(sourceAnalysis?.cleanBookName) ??
        searchTitle;

    return _ResolvedFavoriteComicTitles(
      queueTitle: queueTitle,
      searchTitle: searchTitle,
      sourceTitle:
          _nonEmptyOrNull(sourceAnalysis?.cleanBookName) ?? searchTitle,
    );
  }

  ComicTitleAnalysis? _analyze(String? title) {
    final raw = _nonEmptyOrNull(title);
    if (raw == null) {
      return null;
    }
    return _titleAnalyzer.analyze(raw);
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
