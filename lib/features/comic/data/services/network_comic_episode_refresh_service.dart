import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_episode_link_merger.dart';
import 'package:y300/features/comic/domain/services/comic_episode_refresh_service.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_keyword_resolver.dart';
import 'package:y300/features/comic/domain/services/comic_search_candidate_ranker.dart';
import 'package:y300/features/comic/domain/services/comic_thread_discovery_cache.dart';
import 'package:y300/features/favorites/domain/services/favorite_sync_request_governor.dart';
import 'package:y300/features/search/data/services/forum_search_coordinator.dart';

class NetworkComicEpisodeRefreshService implements ComicEpisodeRefreshService {
  NetworkComicEpisodeRefreshService({
    required ComicEpisodeDiscoveryService discoveryService,
    required ForumSearchCoordinator searchService,
    required ComicRefreshKeywordResolver keywordResolver,
    required ComicSearchCandidateRanker candidateRanker,
    required ComicEpisodeLinkMerger episodeLinkMerger,
    ThreadSeedFetcher? threadSeedFetcher,
  }) : _discoveryService = discoveryService,
       _searchService = searchService,
       _keywordResolver = keywordResolver,
       _candidateRanker = candidateRanker,
       _episodeLinkMerger = episodeLinkMerger,
       _threadSeedFetcher = threadSeedFetcher;

  final ComicEpisodeDiscoveryService _discoveryService;
  final ForumSearchCoordinator _searchService;
  final ComicRefreshKeywordResolver _keywordResolver;
  final ComicSearchCandidateRanker _candidateRanker;
  final ComicEpisodeLinkMerger _episodeLinkMerger;
  final ThreadSeedFetcher? _threadSeedFetcher;
  static const _references = ForumReferenceResolver();

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinks(
    ComicEpisodeRefreshRequest request,
  ) async {
    final outcome = await fetchCatalogThenFallback(request);
    return outcome.links;
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogThenFallback(
    ComicEpisodeRefreshRequest request,
  ) async {
    // 当前帖的连续跳转链接常只覆盖“上一话/历史话”，不能作为完整章节表。
    // 因此仅在目录解析成功时直接信任；否则继续走搜索补全，并按 tid 合并。
    final threadCache = ComicThreadDiscoveryCache();
    final current = await _discoverCatalogFirst(
      request,
      executionContext: null,
      threadCache: threadCache,
    );
    final catalogMatched =
        current.strategy == EpisodeDiscoveryStrategy.catalog &&
        current.episodeLinks.isNotEmpty;
    if (catalogMatched) {
      _logRefresh(
        request,
        'strategy=catalog links=${current.episodeLinks.length}',
      );
      return ComicEpisodeRefreshOutcome(
        source: ComicEpisodeRefreshSource.catalog,
        links: current.episodeLinks,
        catalogMatched: true,
        catalogUrl: current.catalogUrl,
        threadCache: threadCache,
      );
    }

    return _fetchSearchAndCurrentOnly(
      request,
      current: current,
      threadCache: threadCache,
    );
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogOnly(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
    ComicThreadDiscoveryCache? threadCache,
  }) async {
    final cache = threadCache ?? ComicThreadDiscoveryCache();
    final current = await _discoverCatalogFirst(
      request,
      executionContext: executionContext,
      preloadedRootDetail: preloadedRootDetail,
      threadCache: cache,
    );
    final catalogMatched =
        current.strategy == EpisodeDiscoveryStrategy.catalog &&
        current.episodeLinks.isNotEmpty;
    if (!catalogMatched) {
      _logRefresh(
        request,
        'strategy=catalog-only miss current=${current.episodeLinks.length}',
      );
      return ComicEpisodeRefreshOutcome(
        source: ComicEpisodeRefreshSource.empty,
        links: const <ComicEpisodeLink>[],
        catalogUrl: current.catalogUrl,
        threadCache: cache,
      );
    }
    _logRefresh(
      request,
      'strategy=catalog-only links=${current.episodeLinks.length}',
    );
    return ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.catalog,
      links: current.episodeLinks,
      catalogMatched: true,
      catalogUrl: current.catalogUrl,
      threadCache: cache,
    );
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
    ComicThreadDiscoveryCache? threadCache,
  }) async {
    final cache = threadCache ?? ComicThreadDiscoveryCache();
    final current = await _discoverCurrentOnly(
      request,
      executionContext: executionContext,
      preloadedRootDetail: preloadedRootDetail,
      threadCache: cache,
    );
    return _fetchSearchAndCurrentOnly(
      request,
      current: current,
      executionContext: executionContext,
      preloadedRootDetail: preloadedRootDetail,
      threadCache: cache,
    );
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogDirect(
    String catalogUrl, {
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    final links = await _discoveryService.discoverFromCatalogUrl(
      catalogUrl,
      governor: executionContext?.governor,
    );
    if (links.isEmpty) {
      return ComicEpisodeRefreshOutcome(
        source: ComicEpisodeRefreshSource.empty,
        links: const <ComicEpisodeLink>[],
        catalogUrl: catalogUrl,
      );
    }
    return ComicEpisodeRefreshOutcome(
      source: ComicEpisodeRefreshSource.catalog,
      links: links,
      catalogMatched: true,
      catalogUrl: catalogUrl,
    );
  }

  Future<EpisodeDiscoveryResult> _discoverCatalogFirst(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
    ComicThreadDiscoveryCache? threadCache,
  }) {
    return _discoveryService.discoverFromTidWithPreference(
      tid: request.sourceTid,
      preferCatalogFirst: true,
      governor: executionContext?.governor,
      preloadedRootDetail: preloadedRootDetail,
      threadCache: threadCache,
    );
  }

  Future<EpisodeDiscoveryResult> _discoverCurrentOnly(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
    ComicThreadDiscoveryCache? threadCache,
  }) {
    return _discoveryService.discoverFromTidWithPreference(
      tid: request.sourceTid,
      preferCatalogFirst: false,
      allowCatalogFallback: false,
      governor: executionContext?.governor,
      preloadedRootDetail: preloadedRootDetail,
      threadCache: threadCache,
    );
  }

  Future<ComicEpisodeRefreshOutcome> _fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request, {
    required EpisodeDiscoveryResult current,
    FavoriteSyncExecutionContext? executionContext,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
    ComicThreadDiscoveryCache? threadCache,
  }) async {
    final cache = threadCache ?? ComicThreadDiscoveryCache();
    final searchResult = await _searchFallbackFromCurrentTid(
      request,
      executionContext: executionContext,
      preloadedRootDetail: preloadedRootDetail,
      threadCache: cache,
      currentLinks: current.episodeLinks,
    );
    final searchLinks = searchResult.links;
    if (searchLinks.isNotEmpty) {
      final merged = _episodeLinkMerger.merge(
        current.episodeLinks,
        searchLinks,
        preferSupplement: true,
      );
      _logRefresh(
        request,
        'strategy=search current=${current.episodeLinks.length} '
        'search=${searchLinks.length} merged=${merged.length}',
      );
      return ComicEpisodeRefreshOutcome(
        source: ComicEpisodeRefreshSource.search,
        links: merged,
        usedSearch: true,
        catalogUrl: searchResult.catalogUrl ?? current.catalogUrl,
        threadCache: cache,
      );
    }

    _logRefresh(
      request,
      'strategy=current-only links=${current.episodeLinks.length} '
      'searched=${searchResult.usedSearch}',
    );
    return ComicEpisodeRefreshOutcome(
      source: current.episodeLinks.isEmpty
          ? ComicEpisodeRefreshSource.empty
          : ComicEpisodeRefreshSource.currentOnly,
      links: current.episodeLinks,
      usedSearch: searchResult.usedSearch,
      catalogUrl: current.catalogUrl,
      threadCache: cache,
    );
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) {
    return fetchEpisodeLinks(ComicEpisodeRefreshRequest(sourceTid: tid));
  }

  Future<_SearchFallbackResult> _searchFallbackFromCurrentTid(
    ComicEpisodeRefreshRequest request, {
    FavoriteSyncExecutionContext? executionContext,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
    ComicThreadDiscoveryCache? threadCache,
    required List<ComicEpisodeLink> currentLinks,
  }) async {
    final thread = await _fetchThreadDetail(
      request.sourceTid,
      executionContext: executionContext,
      preloadedRootDetail: preloadedRootDetail,
      threadCache: threadCache,
    );
    if (thread == null) {
      return const _SearchFallbackResult.empty();
    }
    final keywords = _keywordResolver.resolve(request, thread.subject);
    _logRefresh(request, 'refreshKeywords=${keywords.length}');
    var usedSearch = false;
    for (final keyword in keywords) {
      _logRefresh(
        request,
        'keyword=${keyword.value} source=${keyword.source.name}',
      );

      // 搜索本身由 ForumSearchReadScheduler 持有 ~10.5s 节流 + 等待队列；这里
      // 不再叠加 favorite governor 槽，让搜索请求只受调度器约束，并通过队列
      // 进度向通知栏汇报。
      final search = await _searchForComic(keyword.value);
      usedSearch = true;
      if (search.rateLimited || search.topics.isEmpty) {
        _logRefresh(
          request,
          'keyword=${keyword.value} candidates=0 rateLimited=${search.rateLimited}',
        );
        if (search.rateLimited) {
          return const _SearchFallbackResult(
            links: <ComicEpisodeLink>[],
            usedSearch: true,
          );
        }
        continue;
      }

      final topicCandidates = _candidateRanker.rank(items: search.topics);
      _logRefresh(
        request,
        'keyword=${keyword.value} candidates=${topicCandidates.length} '
        'top=${topicCandidates.take(3).map((item) => item.tid).join(',')}',
      );
      if (topicCandidates.isEmpty) {
        continue;
      }

      var collectedLinks = const <ComicEpisodeLink>[];
      String? collectedCatalogUrl;
      final searchCandidateLinks = _mergeSearchTopics(topicCandidates);
      final candidateBatch = _selectDiscoveryCandidates(
        topicCandidates,
        sourceTid: request.sourceTid.trim(),
      );
      // Search titles alone do not prove body coverage. Only links discovered
      // from the source or earlier candidate bodies can retire a body request.
      final coveredTids = _episodeTids(currentLinks).toSet();
      _logRefresh(
        request,
        'discovery=${candidateBatch.map((item) => item.tid).join(',')}',
      );
      for (final candidate in candidateBatch) {
        if (coveredTids.contains(candidate.tid)) {
          continue;
        }
        final result = await _discoveryService.discoverFromTidWithPreference(
          tid: candidate.tid,
          preferCatalogFirst: true,
          governor: executionContext?.governor,
          threadCache: threadCache,
        );
        coveredTids.addAll(_episodeTids(result.episodeLinks));
        if (result.episodeLinks.isNotEmpty) {
          collectedCatalogUrl ??= result.catalogUrl;
          collectedLinks = _episodeLinkMerger.merge(
            collectedLinks,
            result.episodeLinks,
          );
        }
      }
      final mergedSearchLinks = _episodeLinkMerger.merge(
        collectedLinks,
        searchCandidateLinks,
        preferSupplement: true,
      );
      if (mergedSearchLinks.isEmpty) {
        continue;
      }
      return _SearchFallbackResult(
        links: _episodeLinkMerger.sort(mergedSearchLinks),
        usedSearch: true,
        catalogUrl: collectedCatalogUrl,
      );
    }
    return _SearchFallbackResult(
      links: const <ComicEpisodeLink>[],
      usedSearch: usedSearch,
    );
  }

  Future<_ComicSearchExecution> _searchForComic(String keyword) async {
    final execution = await _searchService.search(
      ForumSearchQuery(
        keyword: keyword,
        scope: ForumSearchScope.currentForum,
        forumId: '30',
      ),
      enforceRateLimit: true,
    );
    if (execution.isRateLimited) {
      return const _ComicSearchExecution.rateLimited();
    }
    final result = execution.readResult!;
    return result.when(
      success: (data, _, _) => _ComicSearchExecution(topics: data.topics),
      failure: (failure) => throw StateError(
        'Forum search failed: ${failure.code ?? failure.kind.name}',
      ),
    );
  }

  String _buildThreadUrl(String tid) {
    return Uri.parse('${AppConfig.siteBaseUrl}/forum.php')
        .replace(
          queryParameters: <String, String>{'mod': 'viewthread', 'tid': tid},
        )
        .toString();
  }

  List<ComicEpisodeLink> _mergeSearchTopics(
    List<ComicSearchCandidate> candidates,
  ) {
    return _episodeLinkMerger.fromSearchCandidates(
      candidates,
      threadUrlBuilder: _buildThreadUrl,
    );
  }

  List<ComicSearchCandidate> _selectDiscoveryCandidates(
    List<ComicSearchCandidate> candidates, {
    required String sourceTid,
  }) {
    final selectedTids = <String>{sourceTid};
    return candidates
        .where(
          (candidate) =>
              (int.tryParse(candidate.tid) ?? 0) > 0 &&
              selectedTids.add(candidate.tid),
        )
        .take(_candidateRanker.discoveryTopK)
        .toList(growable: false);
  }

  Iterable<String> _episodeTids(List<ComicEpisodeLink> links) =>
      links.map((link) => _references.extractTid(link.url)).whereType<String>();

  Future<ThreadSeed?> _fetchThreadDetail(
    String tid, {
    FavoriteSyncExecutionContext? executionContext,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
    ComicThreadDiscoveryCache? threadCache,
  }) async {
    if (preloadedRootDetail != null && preloadedRootDetail.tid == tid) {
      return ThreadSeed(subject: preloadedRootDetail.subject);
    }
    // 搜索回退里只用到 subject，discovery cache 已覆盖该需求，
    // 也能完整覆盖需求——避免跟 _discoverCurrentOnly 在 100ms 内重复
    // 拉同一个 tid。
    final cached = threadCache?.get(tid);
    if (cached != null) {
      return ThreadSeed(subject: cached.subject);
    }
    final fetcher = _threadSeedFetcher;
    if (fetcher != null) {
      return _runSeedFetch(
        executionContext: executionContext,
        action: () => fetcher(tid),
      );
    }
    return null;
  }

  Future<T> _runSeedFetch<T>({
    required FavoriteSyncExecutionContext? executionContext,
    required Future<T> Function() action,
  }) {
    final governor = executionContext?.governor;
    if (governor == null) {
      return action();
    }
    return governor.run(
      kind: FavoriteSyncRequestKind.comicThreadDetail,
      action: action,
    );
  }

  void _logRefresh(ComicEpisodeRefreshRequest request, String message) {
    if (kReleaseMode) {
      return;
    }
    debugPrint(
      '[ComicRefresh][${request.comicId ?? request.sourceTid}] $message',
    );
  }
}

class _SearchFallbackResult {
  const _SearchFallbackResult({
    required this.links,
    required this.usedSearch,
    this.catalogUrl,
  });

  const _SearchFallbackResult.empty()
    : links = const <ComicEpisodeLink>[],
      usedSearch = false,
      catalogUrl = null;

  final List<ComicEpisodeLink> links;
  final bool usedSearch;
  final String? catalogUrl;
}

final class _ComicSearchExecution {
  const _ComicSearchExecution({this.topics = const <ForumSearchTopicSummary>[]})
    : rateLimited = false;

  const _ComicSearchExecution.rateLimited()
    : topics = const <ForumSearchTopicSummary>[],
      rateLimited = true;

  final List<ForumSearchTopicSummary> topics;
  final bool rateLimited;
}
