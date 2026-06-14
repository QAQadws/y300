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

/// 抽象 catalogUrl 持久化接口。
///
/// [ComicRepository] 已有 `updateCatalogUrl` 方法，
/// `LocalComicRepository` 自动满足。
abstract class CatalogUrlUpdater {
  Future<void> updateCatalogUrl({
    required String comicId,
    required String catalogUrl,
  });
}

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
    CatalogUrlUpdater? catalogUrlUpdater,
  })  : _refreshService = refreshService,
        _searchQueue = searchQueue,
        _refreshOutcomeApplier = refreshOutcomeApplier,
        _shelfRefreshBus = shelfRefreshBus,
        _catalogMissPolicy = catalogMissPolicy,
        _titleAnalyzer = titleAnalyzer,
        _catalogUrlUpdater = catalogUrlUpdater;

  final ComicEpisodeRefreshService _refreshService;
  final ComicSearchRefreshQueueEnqueuer _searchQueue;
  final ComicRefreshOutcomeApplier _refreshOutcomeApplier;
  final LibraryShelfRefreshBus _shelfRefreshBus;
  final ComicCatalogMissPolicy _catalogMissPolicy;
  final ComicTitleAnalyzer _titleAnalyzer;
  final CatalogUrlUpdater? _catalogUrlUpdater;

  Future<ComicFavoriteAutoRefreshResult> refreshAfterFavoriteIngest({
    required String comicId,
    required ThreadDetailData detail,
    required String favoriteTitle,
    String? sourceTagName,
    bool forceSearchOnCatalogMiss = false,
    String? catalogUrl,
  }) async {
    return refreshFavoriteComic(
      comicId: comicId,
      sourceTid: detail.tid,
      favoriteTitle: favoriteTitle,
      sourceTitle: detail.subject,
      sourceTagName: sourceTagName,
      forceSearchOnCatalogMiss: forceSearchOnCatalogMiss,
      catalogUrl: catalogUrl,
    );
  }

  Future<ComicFavoriteAutoRefreshResult> refreshFavoriteComic({
    required String comicId,
    required String sourceTid,
    required String favoriteTitle,
    String? sourceTitle,
    String? sourceTagName,
    bool forceSearchOnCatalogMiss = false,
    String? catalogUrl,
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
      catalogUrl: catalogUrl,
    );

    // 优先 catalog 快速路径
    if (catalogUrl != null && catalogUrl.isNotEmpty) {
      final catalogDirect = await _refreshService.fetchCatalogDirect(catalogUrl);
      if (catalogDirect.catalogMatched && catalogDirect.hasLinks) {
        await _refreshOutcomeApplier.apply(
          ComicRefreshApplyRequest(
            comicId: comicId,
            sourceTid: sourceTid,
            links: catalogDirect.links,
            source: catalogDirect.source,
            mutationSource: LibraryMutationSource.favoriteSync,
            reason: 'favorite_comic_catalog_direct_refresh',
            catalogUrl: catalogDirect.catalogUrl,
          ),
        );
        return ComicFavoriteAutoRefreshResult(
          status: ComicFavoriteAutoRefreshStatus.catalogMerged,
          linkCount: catalogDirect.links.length,
        );
      }
    }

    // catalog 快速路径失败 -> 回退到 fetchCatalogOnly
    final catalog = await _refreshService.fetchCatalogOnly(request);
    if (catalog.catalogMatched && catalog.hasLinks) {
      // 如果本次发现了新的 catalogUrl（之前为 null 或不同），持久化
      if (catalog.catalogUrl != null &&
          catalog.catalogUrl != catalogUrl &&
          catalog.catalogUrl!.isNotEmpty) {
        final updater = _catalogUrlUpdater;
        if (updater != null) {
          await updater.updateCatalogUrl(
            comicId: comicId,
            catalogUrl: catalog.catalogUrl!,
          );
        }
      }
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
