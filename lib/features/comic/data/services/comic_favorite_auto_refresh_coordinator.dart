import 'package:y300/features/comic/domain/services/comic_catalog_miss_policy.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/comic/domain/services/comic_thread_detail_cache.dart';
import 'package:y300/features/comic/domain/services/title/comic_title_analysis.dart';
import 'package:y300/features/comic/domain/services/title/comic_title_analyzer.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/library_shared/domain/services/sync_diagnostic_recorder.dart';
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
  searchMerged,
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
    SyncDiagnosticRecorder? diagnosticRecorder,
    CatalogUrlUpdater? catalogUrlUpdater,
  }) : _refreshService = refreshService,
       _searchQueue = searchQueue,
       _refreshOutcomeApplier = refreshOutcomeApplier,
       _shelfRefreshBus = shelfRefreshBus,
       _catalogMissPolicy = catalogMissPolicy,
       _titleAnalyzer = titleAnalyzer,
       _diagnosticRecorder =
           diagnosticRecorder ?? const NoopSyncDiagnosticRecorder(),
       _catalogUrlUpdater = catalogUrlUpdater;

  final ComicEpisodeRefreshService _refreshService;
  final ComicSearchRefreshQueueEnqueuer _searchQueue;
  final ComicRefreshOutcomeApplier _refreshOutcomeApplier;
  final LibraryShelfRefreshBus _shelfRefreshBus;
  final ComicCatalogMissPolicy _catalogMissPolicy;
  final ComicTitleAnalyzer _titleAnalyzer;
  final SyncDiagnosticRecorder _diagnosticRecorder;
  final CatalogUrlUpdater? _catalogUrlUpdater;

  Future<ComicFavoriteAutoRefreshResult> refreshAfterFavoriteIngest({
    required String comicId,
    required ThreadDetailData detail,
    required String favoriteTitle,
    String? sourceFid,
    String? sourceTypeId,
    String? sourceTagName,
    bool forceSearchOnCatalogMiss = false,
    String? catalogUrl,
    FavoriteSyncExecutionContext? executionContext,
    ThreadDetailData? preloadedRootDetail,
  }) async {
    return refreshFavoriteComic(
      comicId: comicId,
      sourceTid: detail.tid,
      favoriteTitle: favoriteTitle,
      sourceTitle: detail.subject,
      sourceFid: sourceFid ?? detail.fid,
      sourceTypeId: sourceTypeId ?? detail.typeid,
      sourceTagName: sourceTagName,
      forceSearchOnCatalogMiss: forceSearchOnCatalogMiss,
      catalogUrl: catalogUrl,
      executionContext: executionContext,
      preloadedRootDetail: preloadedRootDetail ?? detail,
    );
  }

  Future<ComicFavoriteAutoRefreshResult> refreshFavoriteComic({
    required String comicId,
    required String sourceTid,
    required String favoriteTitle,
    String? sourceTitle,
    String? sourceFid,
    String? sourceTypeId,
    String? sourceTagName,
    bool forceSearchOnCatalogMiss = false,
    String? catalogUrl,
    FavoriteSyncExecutionContext? executionContext,
    ThreadDetailData? preloadedRootDetail,
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
    _diagnosticRecorder.record(
      scope: 'favorite_comic_refresh',
      event: 'start',
      fields: <String, Object?>{
        'comicId': comicId,
        'sourceTid': sourceTid,
        'sourceFid': sourceFid,
        'sourceTypeId': sourceTypeId,
        'sourceTagName': sourceTagName,
        'hasCatalogUrl': catalogUrl != null && catalogUrl.isNotEmpty,
        'forceSearchOnCatalogMiss': forceSearchOnCatalogMiss,
        'bootstrapInitial': executionContext?.isBootstrapInitial == true,
      },
    );

    // 优先 catalog 快速路径
    if (catalogUrl != null && catalogUrl.isNotEmpty) {
      final catalogDirect = await _refreshService.fetchCatalogDirect(
        catalogUrl,
        executionContext: executionContext,
      );
      if (catalogDirect.catalogMatched && catalogDirect.hasLinks) {
        _diagnosticRecorder.record(
          scope: 'favorite_comic_refresh',
          event: 'catalog_direct_hit',
          fields: <String, Object?>{
            'comicId': comicId,
            'sourceTid': sourceTid,
            'links': catalogDirect.links.length,
          },
        );
        await _refreshOutcomeApplier.apply(
          ComicRefreshApplyRequest(
            comicId: comicId,
            sourceTid: sourceTid,
            links: catalogDirect.links,
            source: catalogDirect.source,
            mutationSource: LibraryMutationSource.favoriteSync,
            reason: 'favorite_comic_catalog_direct_refresh',
            catalogUrl: catalogDirect.catalogUrl,
            // catalog-direct 没有发起任何 viewthread，threadCache 必为空，
            // 这条路径下封面提升仍然会经 governor 拉一次，是预期行为。
            threadCache: catalogDirect.threadCache,
            governor: executionContext?.governor,
          ),
        );
        return ComicFavoriteAutoRefreshResult(
          status: ComicFavoriteAutoRefreshStatus.catalogMerged,
          linkCount: catalogDirect.links.length,
        );
      }
    }

    // catalog 快速路径失败 -> 回退到 fetchCatalogOnly
    // 共享一个 ComicThreadDetailCache，让封面提升能复用 discovery 已抓取
    // 的第一话 thread 详情，省掉一次 viewthread。
    final sharedCache = ComicThreadDetailCache();
    final catalog = await _refreshService.fetchCatalogOnly(
      request,
      executionContext: executionContext,
      preloadedRootDetail: preloadedRootDetail,
      threadCache: sharedCache,
    );
    if (catalog.catalogMatched && catalog.hasLinks) {
      _diagnosticRecorder.record(
        scope: 'favorite_comic_refresh',
        event: 'catalog_hit',
        fields: <String, Object?>{
          'comicId': comicId,
          'sourceTid': sourceTid,
          'links': catalog.links.length,
          'catalogUrlChanged':
              catalog.catalogUrl != null && catalog.catalogUrl != catalogUrl,
        },
      );
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
          threadCache: catalog.threadCache ?? sharedCache,
          governor: executionContext?.governor,
        ),
      );
      return ComicFavoriteAutoRefreshResult(
        status: ComicFavoriteAutoRefreshStatus.catalogMerged,
        linkCount: catalog.links.length,
      );
    }

    if (!_catalogMissPolicy.shouldQueueSearchOnCatalogMiss(
      sourceFid: sourceFid,
      sourceTypeId: sourceTypeId,
      sourceTagName: sourceTagName,
      forceSearchOnCatalogMiss: forceSearchOnCatalogMiss,
    )) {
      _diagnosticRecorder.record(
        scope: 'favorite_comic_refresh',
        event: 'catalog_miss_skipped',
        fields: <String, Object?>{
          'comicId': comicId,
          'sourceTid': sourceTid,
          'sourceFid': sourceFid,
          'sourceTypeId': sourceTypeId,
          'sourceTagName': sourceTagName,
        },
      );
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

    // catalog 未命中：始终走持久化的搜索等待队列。
    // 队列内部由 ForumSearchScheduler 控制 ~10.5s 节奏，并通过队列快照向
    // 通知栏汇报"《xxx》正在等待漫画搜索"——这是一直存在的能力，曾被
    // bootstrapInitial 内联搜索路径绕过，这里恢复成始终入队。
    final queued = await _searchQueue.enqueue(
      request: request,
      title: titles.queueTitle,
      origin: ComicSearchRefreshOrigin.favoriteSync,
      // 把已抓到的 root detail 透传给队列任务，跨入队边界保留缓存——
      // 避免队列任务再为同一 sourceTid 发起 viewthread。
      preloadedRootDetail: preloadedRootDetail,
    );
    _diagnosticRecorder.record(
      scope: 'favorite_comic_refresh',
      event: 'queued_search',
      fields: <String, Object?>{
        'comicId': comicId,
        'sourceTid': sourceTid,
        'queuePosition': queued.position,
        'estimatedDurationMs': queued.estimatedDuration.inMilliseconds,
      },
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
    final searchTitle =
        _nonEmptyOrNull(sourceAnalysis?.cleanBookName) ??
        _nonEmptyOrNull(favoriteAnalysis?.cleanBookName) ??
        rawFavoriteTitle ??
        rawSourceTitle ??
        sourceTid;

    // Queue title is user-facing progress text. It must no longer leak the raw
    // forum thread title, so it uses the cleaned book name (favorite first,
    // matching the historical preference for the favorite list title).
    final queueTitle =
        _nonEmptyOrNull(favoriteAnalysis?.cleanBookName) ??
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
