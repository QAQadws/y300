import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_thread_detail_cache.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

abstract class ComicEpisodeRefreshService {
  Future<List<ComicEpisodeLink>> fetchEpisodeLinks(
    ComicEpisodeRefreshRequest request,
  );

  /// Runs the full refresh decision tree: catalog first, then search/current
  /// fallback when catalog misses.
  Future<ComicEpisodeRefreshOutcome> fetchCatalogThenFallback(
    ComicEpisodeRefreshRequest request,
  );

  /// Runs only strategy 1. A miss intentionally returns an empty outcome so
  /// callers can enqueue search without spending a search request here.
  Future<ComicEpisodeRefreshOutcome> fetchCatalogOnly(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
    ThreadDetailData? preloadedRootDetail,
    ComicThreadDetailCache? threadCache,
  });

  /// Runs strategy 2 and strategy 3 for callers that already decided catalog
  /// refresh should not run immediately, such as the future search queue.
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
    ThreadDetailData? preloadedRootDetail,
    ComicThreadDetailCache? threadCache,
  });

  /// Catalog 快速路径：直接解析持久化的 catalogUrl HTML。
  ///
  /// 不请求帖子详情，适用于已持久化 catalogUrl 的场景。
  /// 失败时返回空结果，调用方应回退到 [fetchCatalogOnly]。
  Future<ComicEpisodeRefreshOutcome> fetchCatalogDirect(
    String catalogUrl, {
    FavoriteSyncExecutionContext? executionContext,
  });

  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid);
}

enum ComicEpisodeRefreshSource { catalog, search, currentOnly, empty }

class ComicEpisodeRefreshOutcome {
  const ComicEpisodeRefreshOutcome({
    required this.source,
    required this.links,
    this.usedSearch = false,
    this.catalogMatched = false,
    this.catalogUrl,
    this.threadCache,
  });

  final ComicEpisodeRefreshSource source;
  final List<ComicEpisodeLink> links;
  final bool usedSearch;
  final bool catalogMatched;

  /// 本次刷新过程中发现或使用的 catalogUrl。
  /// 调用方可据此持久化，以便下次走 catalog 快速路径。
  final String? catalogUrl;

  /// 本次刷新内 discovery 过程已抓取并解析过的 thread detail 缓存。
  /// 调用方（如封面提升）可优先复用，避免对已访问 tid 再发起 viewthread。
  final ComicThreadDetailCache? threadCache;

  bool get hasLinks => links.isNotEmpty;
}

class ComicEpisodeRefreshRequest {
  const ComicEpisodeRefreshRequest({
    required this.sourceTid,
    this.comicId,
    this.displayTitle,
    this.sourceTitle,
    this.customTitle,
    this.customSearchTitle,
    this.catalogUrl,
  });

  final String? comicId;
  final String sourceTid;
  final String? displayTitle;
  final String? sourceTitle;
  final String? customTitle;
  final String? customSearchTitle;

  /// 已持久化的 catalogUrl，调用方从 ComicDetail 获取并传入。
  final String? catalogUrl;
}

class ThreadSeed {
  const ThreadSeed({required this.subject});

  final String subject;
}

typedef ThreadSeedFetcher = Future<ThreadSeed?> Function(String tid);
