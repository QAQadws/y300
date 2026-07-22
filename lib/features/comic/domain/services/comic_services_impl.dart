import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/comic/data/services/comic_parser_service.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_parsing_debug_models.dart';
import 'package:y300/features/comic/domain/services/comic_catalog_miss_policy.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_incremental_episode_discovery.dart';
import 'package:y300/features/comic/domain/services/comic_episode_link_merger.dart';
import 'package:y300/features/comic/domain/services/comic_episode_refresh_service.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/comic/domain/services/comic_detector.dart';
import 'package:y300/features/comic/domain/services/comic_episode_images_fetch_result.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_keyword_resolver.dart';
import 'package:y300/features/comic/domain/services/comic_search_candidate_ranker.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/comic/domain/services/comic_thread_detail_cache.dart';
import 'package:y300/features/comic/domain/services/title/comic_title_analyzer.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/data/services/discuz_search_service.dart';
import 'package:y300/features/thread/data/repositories/thread_repository.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_image_source_pipeline.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';
import 'package:y300/features/thread/domain/services/forum_post_image_source_collector.dart';

export 'comic_episode_refresh_service.dart';

final comicDetectorProvider = Provider<ComicDetector>((ref) {
  return RuleBasedComicDetector();
});

final comicParserServiceProvider = Provider<ComicParserService>((ref) {
  return HtmlComicParserService();
});

final comicTitleAnalyzerProvider = Provider<ComicTitleAnalyzer>((ref) {
  return const PetitComicTitleAnalyzer();
});

final comicSubjectParserProvider = Provider<ComicSubjectParser>((ref) {
  return RuleBasedComicSubjectParser(
    analyzer: ref.watch(comicTitleAnalyzerProvider),
  );
});

class NetworkComicEpisodeRefreshService implements ComicEpisodeRefreshService {
  NetworkComicEpisodeRefreshService({
    required ComicEpisodeDiscoveryService discoveryService,
    required ForumSearchService searchService,
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
  final ForumSearchService _searchService;
  final ComicRefreshKeywordResolver _keywordResolver;
  final ComicSearchCandidateRanker _candidateRanker;
  final ComicEpisodeLinkMerger _episodeLinkMerger;
  final ThreadSeedFetcher? _threadSeedFetcher;

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
    final threadCache = ComicThreadDetailCache();
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
    ThreadDetailData? preloadedRootDetail,
    ComicThreadDetailCache? threadCache,
  }) async {
    final cache = threadCache ?? ComicThreadDetailCache();
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
    ThreadDetailData? preloadedRootDetail,
    ComicThreadDetailCache? threadCache,
  }) async {
    final cache = threadCache ?? ComicThreadDetailCache();
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
    ThreadDetailData? preloadedRootDetail,
    ComicThreadDetailCache? threadCache,
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
    ThreadDetailData? preloadedRootDetail,
    ComicThreadDetailCache? threadCache,
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
    ThreadDetailData? preloadedRootDetail,
    ComicThreadDetailCache? threadCache,
  }) async {
    final cache = threadCache ?? ComicThreadDetailCache();
    final searchResult = await _searchFallbackFromCurrentTid(
      request,
      executionContext: executionContext,
      preloadedRootDetail: preloadedRootDetail,
      threadCache: cache,
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
    ThreadDetailData? preloadedRootDetail,
    ComicThreadDetailCache? threadCache,
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

      // 搜索本身由 ForumSearchScheduler 持有 ~10.5s 节流 + 等待队列；这里
      // 不再叠加 favorite governor 槽，让搜索请求只受调度器约束，并通过队列
      // 进度向通知栏汇报。
      final search = await _searchService.searchForum(
        keyword: keyword.value,
        context: const DiscuzSearchContext.curForum(srhfid: '30'),
        enforceRateLimit: true,
      );
      usedSearch = true;
      if (search.rateLimited || search.items.isEmpty) {
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

      final candidates = _candidateRanker.rank(
        threadSubject: thread.subject,
        keyword: keyword,
        items: search.items,
      );
      _logRefresh(
        request,
        'keyword=${keyword.value} candidates=${candidates.length} '
        'top=${candidates.take(3).map((item) => '${item.item.tid}:${item.score.toStringAsFixed(2)}').join(',')}',
      );
      if (candidates.isEmpty) {
        continue;
      }

      var collectedLinks = const <ComicEpisodeLink>[];
      String? collectedCatalogUrl;
      final sourceTid = request.sourceTid.trim();
      final candidateBatch = candidates
          .where((item) => item.item.tid.trim() != sourceTid)
          .take(_candidateRanker.discoveryTopK)
          .toList(growable: false);
      for (final candidate in candidateBatch) {
        final result = await _discoveryService.discoverFromTidWithPreference(
          tid: candidate.item.tid,
          preferCatalogFirst: true,
          governor: executionContext?.governor,
          threadCache: threadCache,
        );
        if (result.episodeLinks.isNotEmpty) {
          collectedCatalogUrl ??= result.catalogUrl;
          collectedLinks = _episodeLinkMerger.merge(
            collectedLinks,
            result.episodeLinks,
          );
        }
      }
      final searchCandidateLinks = _episodeLinkMerger.fromSearchCandidates(
        candidates,
        excludeTid: sourceTid,
      );
      if (collectedLinks.isEmpty && searchCandidateLinks.isEmpty) {
        continue;
      }
      if (collectedLinks.isEmpty) {
        return _SearchFallbackResult(
          links: searchCandidateLinks,
          usedSearch: true,
        );
      }
      if (searchCandidateLinks.length > collectedLinks.length) {
        // Discuz search results are themselves same-series thread entries. When
        // catalog/recursive parsing only finds a partial set, preserve those
        // matched entries instead of losing newer chapters from the search page.
        return _SearchFallbackResult(
          links: _episodeLinkMerger.sort(
            _episodeLinkMerger.merge(
              collectedLinks,
              searchCandidateLinks,
              preferSupplement: true,
            ),
          ),
          usedSearch: true,
          catalogUrl: collectedCatalogUrl,
        );
      }
      return _SearchFallbackResult(
        links: _episodeLinkMerger.sort(collectedLinks),
        usedSearch: true,
        catalogUrl: collectedCatalogUrl,
      );
    }
    return _SearchFallbackResult(
      links: const <ComicEpisodeLink>[],
      usedSearch: usedSearch,
    );
  }

  Future<ThreadSeed?> _fetchThreadDetail(
    String tid, {
    FavoriteSyncExecutionContext? executionContext,
    ThreadDetailData? preloadedRootDetail,
    ComicThreadDetailCache? threadCache,
  }) async {
    if (preloadedRootDetail != null && preloadedRootDetail.tid == tid) {
      return ThreadSeed(subject: preloadedRootDetail.subject);
    }
    // 搜索回退里只用到 subject，所以即使缓存里只有 ThreadDetailData，
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
      kind: FavoriteFirstSyncRequestKind.comicThreadDetail,
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

final comicEpisodeDiscoveryServiceProvider =
    Provider<ComicEpisodeDiscoveryService>((ref) {
      final engine = ComicPostParsingEngine();
      final opPostParser = ComicConsecutiveOpPostParser(
        engine: engine,
        imageSourcePipeline: ref.watch(forumImageSourcePipelineProvider),
      );
      return ComicEpisodeDiscoveryService(
        fetchThreadDetail: (tid) => ref
            .read(threadJsonRepositoryProvider)
            .getThreadDetail(tid: tid, page: 1),
        opPostParser: opPostParser,
        catalogHtmlFetcher: YamiboCatalogHtmlFetcher(
          htmlClient: ref.watch(yamiboHtmlClientProvider),
        ),
      );
    });

final comicIncrementalEpisodeDiscoveryProvider =
    Provider<ComicIncrementalEpisodeDiscovery>((ref) {
      return ComicIncrementalEpisodeDiscovery(
        fetchThreadDetail: (tid) => ref
            .read(threadJsonRepositoryProvider)
            .getThreadDetail(tid: tid, page: 1),
        opPostParser: ComicConsecutiveOpPostParser(
          engine: ComicPostParsingEngine(),
          imageSourcePipeline: ref.watch(forumImageSourcePipelineProvider),
        ),
      );
    });

final comicRefreshKeywordResolverProvider =
    Provider<ComicRefreshKeywordResolver>((ref) {
      return DefaultComicRefreshKeywordResolver(
        subjectParser: ref.read(comicSubjectParserProvider),
        featureFlags: ref.watch(comicReaderFeatureFlagsProvider),
      );
    });

final comicSearchCandidateRankerProvider = Provider<ComicSearchCandidateRanker>(
  (ref) {
    return const DefaultComicSearchCandidateRanker();
  },
);

final comicEpisodeLinkMergerProvider = Provider<ComicEpisodeLinkMerger>((ref) {
  return DefaultComicEpisodeLinkMerger(
    subjectParser: ref.read(comicSubjectParserProvider),
  );
});

final comicCatalogMissPolicyProvider = Provider<ComicCatalogMissPolicy>((ref) {
  return const DefaultComicCatalogMissPolicy();
});

final comicEpisodeRefreshServiceProvider = Provider<ComicEpisodeRefreshService>(
  (ref) {
    return NetworkComicEpisodeRefreshService(
      discoveryService: ref.read(comicEpisodeDiscoveryServiceProvider),
      searchService: ref.read(discuzSearchServiceProvider),
      keywordResolver: ref.watch(comicRefreshKeywordResolverProvider),
      candidateRanker: ref.watch(comicSearchCandidateRankerProvider),
      episodeLinkMerger: ref.watch(comicEpisodeLinkMergerProvider),
      threadSeedFetcher: (tid) async {
        final result = await ref
            .read(threadJsonRepositoryProvider)
            .getThreadDetail(tid: tid, page: 1);
        return result.when(
          success: (data) => ThreadSeed(subject: data.subject),
          failure: (_) => null,
        );
      },
    );
  },
);

abstract class ComicReaderService {
  /// 拉取单话首楼图片，区分"成功（含真无图）"和各类失败原因。
  /// 这是新接口；旧的 [fetchEpisodeImagesByTid] 改为默认实现转发到这里，
  /// 保持向后兼容直至所有调用方迁移完毕。
  Future<ComicEpisodeImagesFetchResult> fetchEpisodeImages(String tid);

  /// 旧版便捷方法：失败和真空都返回空列表。
  ///
  /// 调用方失去了区分网络抖动与"首楼真无图"的能力，新代码请直接用
  /// [fetchEpisodeImages]。子类不需要重写本方法，默认实现已经基于新接口。
  @Deprecated(
    'Use fetchEpisodeImages to distinguish transient failures from empty content.',
  )
  Future<List<String>> fetchEpisodeImagesByTid(String tid) async {
    return (await fetchEpisodeImages(tid)).imageUrlsOrEmpty;
  }

  Future<ComicImageCacheResult> cacheImage({
    required String imageUrl,
    String? cacheKey,
    ImageCacheOwnerType? ownerType,
    String? ownerId,
    ImageCacheRole role = ImageCacheRole.comicPage,
    String? episodeId,
    int? imageIndex,
    bool protected = false,
  });

  Future<void> prefetchImages({required List<String> imageUrls}) async {
    for (final imageUrl in imageUrls) {
      await cacheImage(imageUrl: imageUrl);
    }
  }
}

class ComicImageCacheResult {
  const ComicImageCacheResult({
    required this.success,
    this.localPath,
    this.cacheKey,
    this.bytes = 0,
    this.fromCache = false,
  });

  final bool success;
  final String? localPath;
  final String? cacheKey;
  final int bytes;
  final bool fromCache;
}

class NetworkComicReaderService implements ComicReaderService {
  NetworkComicReaderService({
    required ThreadRepository threadRepository,
    ImageCacheService? imageCacheService,
    BaseCacheManager? cacheManager,
    ImageRequestHeaderBuilder? headerBuilder,
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
    ForumImageSourcePipeline imageSourcePipeline =
        const DefaultForumImageSourcePipeline(),
  }) : _threadRepository = threadRepository,
       _imageCacheService = imageCacheService,
       _cacheManager = cacheManager ?? DefaultCacheManager(),
       _headerBuilder = headerBuilder,
       _urlResolver = urlResolver,
       _imageSourcePipeline = imageSourcePipeline;

  final ThreadRepository _threadRepository;
  final ImageCacheService? _imageCacheService;
  final BaseCacheManager _cacheManager;
  final ImageRequestHeaderBuilder? _headerBuilder;
  final SiteUrlResolver _urlResolver;
  final ForumImageSourcePipeline _imageSourcePipeline;

  @override
  Future<ComicEpisodeImagesFetchResult> fetchEpisodeImages(String tid) async {
    final result = await _threadRepository.getThreadDetail(tid: tid, page: 1);
    return result.when(
      success: (data) {
        final firstPost = data.posts.where((post) => post.isFirst).firstOrNull;
        if (firstPost == null) {
          // 首楼没识别出来通常是 Discuz 解析口径异常，不是真的没图——
          // 当作 parse 失败上抛，UI 才会给出"页面结构异常"的明确提示。
          return const ComicEpisodeImagesFetchFailed(
            reason: ComicEpisodeImagesFetchFailureReason.parse,
            message: '首楼帖未识别',
          );
        }
        final imageUrls = _imageSourcePipeline
            .collectFromPost(firstPost)
            .map((source) => source.normalizedUrl)
            .toList(growable: false);
        return ComicEpisodeImagesFetched(imageUrls);
      },
      failure: (error) => ComicEpisodeImagesFetchFailed(
        reason: _mapApiErrorTypeToFetchFailureReason(error.type),
        message: error.message,
      ),
    );
  }

  // ignore: deprecated_member_use_from_same_package
  @Deprecated(
    'Use fetchEpisodeImages to distinguish transient failures from empty content.',
  )
  @override
  // ignore: deprecated_member_use_from_same_package
  Future<List<String>> fetchEpisodeImagesByTid(String tid) async {
    return (await fetchEpisodeImages(tid)).imageUrlsOrEmpty;
  }

  /// 把核心网络层的 `ApiErrorType` 翻译到域内 reason，避免 comic domain
  /// 直接依赖 `lib/core/network/api_result.dart`。映射保持稳定的纯函数。
  ComicEpisodeImagesFetchFailureReason _mapApiErrorTypeToFetchFailureReason(
    ApiErrorType type,
  ) {
    return switch (type) {
      ApiErrorType.network ||
      ApiErrorType.timeout => ComicEpisodeImagesFetchFailureReason.network,
      ApiErrorType.unauthorized => ComicEpisodeImagesFetchFailureReason.auth,
      ApiErrorType.server => ComicEpisodeImagesFetchFailureReason.server,
      ApiErrorType.parse => ComicEpisodeImagesFetchFailureReason.parse,
      ApiErrorType.business ||
      ApiErrorType.unknown => ComicEpisodeImagesFetchFailureReason.unknown,
    };
  }

  @override
  Future<ComicImageCacheResult> cacheImage({
    required String imageUrl,
    String? cacheKey,
    ImageCacheOwnerType? ownerType,
    String? ownerId,
    ImageCacheRole role = ImageCacheRole.comicPage,
    String? episodeId,
    int? imageIndex,
    bool protected = false,
  }) async {
    final sourceUrl = _urlResolver.resolve(imageUrl) ?? imageUrl.trim();
    final normalizedKey = cacheKey?.trim();
    final cacheService = _imageCacheService;
    if (cacheService != null &&
        normalizedKey != null &&
        normalizedKey.isNotEmpty &&
        ownerType != null &&
        ownerId != null &&
        ownerId.trim().isNotEmpty) {
      final result = await cacheService.ensureCached(
        ImageCacheRequest(
          cacheKey: normalizedKey,
          sourceUrl: sourceUrl,
          ownerType: ownerType,
          ownerId: ownerId,
          role: role,
          episodeId: episodeId,
          imageIndex: imageIndex,
          protected: protected,
        ),
      );
      return ComicImageCacheResult(
        success: result.success,
        localPath: result.localPath,
        cacheKey: result.cacheKey,
        bytes: result.bytes,
        fromCache: result.fromCache,
      );
    }

    try {
      final headers = await _buildHeaders(sourceUrl);
      final fileInfo = await _cacheManager.downloadFile(
        sourceUrl,
        key: normalizedKey == null || normalizedKey.isEmpty
            ? sourceUrl
            : normalizedKey,
        authHeaders: headers.isEmpty ? null : headers,
      );
      return ComicImageCacheResult(
        success: true,
        localPath: fileInfo.file.path,
        cacheKey: normalizedKey == null || normalizedKey.isEmpty
            ? sourceUrl
            : normalizedKey,
        bytes: await fileInfo.file.length(),
      );
    } catch (_) {
      return const ComicImageCacheResult(success: false);
    }
  }

  Future<Map<String, String>> _buildHeaders(String imageUrl) async {
    final builder = _headerBuilder;
    if (builder == null) {
      return const <String, String>{};
    }
    return builder.buildHeaders(imageUrl);
  }

  @override
  Future<void> prefetchImages({required List<String> imageUrls}) async {
    for (final imageUrl in imageUrls) {
      await cacheImage(imageUrl: imageUrl);
    }
  }
}

final comicReaderServiceProvider = FutureProvider<ComicReaderService>((
  ref,
) async {
  return NetworkComicReaderService(
    threadRepository: ref.read(threadRepositoryProvider),
    imageCacheService: ref.read(imageCacheServiceProvider),
    cacheManager: await ref.read(comicCacheManagerProvider.future),
    headerBuilder: ref.read(imageRequestHeaderBuilderProvider),
    imageSourcePipeline: ref.watch(forumImageSourcePipelineProvider),
  );
});

final comicFirstEpisodeCoverServiceProvider =
    Provider<ComicFirstEpisodeCoverService>((ref) {
      return ComicFirstEpisodeCoverService(
        repository: ref.watch(comicRepositoryProvider),
        imageSourcePipeline: ref.watch(forumImageSourcePipelineProvider),
        fetchEpisodeImagesByTid: (tid) async {
          final readerService = await ref.read(
            comicReaderServiceProvider.future,
          );
          return readerService.fetchEpisodeImagesByTid(tid);
        },
      );
    });

class RuleBasedComicDetector implements ComicDetector {
  RuleBasedComicDetector({this.threshold = 60});

  final int threshold;

  static final RegExp _subjectKeyword = RegExp(
    r'(\u7b2c\s*\d+(\.\d+)?\s*\u8bdd|\u6c49\u5316|\[[^\]]*\u7ec4\]|\u3010[^\u3011]*\u7ec4\u3011)',
    caseSensitive: false,
  );

  static final RegExp _episodeLink = RegExp(
    r'thread-\d+-\d+-\d+\.html',
    caseSensitive: false,
  );

  static final RegExp _weakTextKeyword = RegExp(
    r'(\u76ee\u5f55|\u56fe\u6e90|\u5d4c\u5b57|\u6821\u5bf9)',
    caseSensitive: false,
  );

  @override
  ComicCandidateInfo detect({
    required String fid,
    required String subject,
    required String message,
  }) {
    var score = 0;
    final reasons = <String>[];

    if (fid == '30') {
      score += 40;
      reasons.add('fid=30');
    }

    final imageCount = RegExp(
      r'<img\b',
      caseSensitive: false,
    ).allMatches(message).length;
    if (imageCount >= 2) {
      score += 35;
      reasons.add('\u56fe\u7247\u6570\u91cf>=2');
    }

    if (_subjectKeyword.hasMatch(subject)) {
      score += 20;
      reasons.add('\u6807\u9898\u547d\u4e2d\u6f2b\u753b\u5173\u952e\u8bcd');
    }

    final linkCount = _episodeLink.allMatches(message).length;
    if (linkCount >= 2) {
      score += 15;
      reasons.add('\u7ae0\u8282\u94fe\u63a5\u6570\u91cf>=2');
    }

    if (_weakTextKeyword.hasMatch(message)) {
      score += 10;
      reasons.add('\u6b63\u6587\u547d\u4e2d\u5f31\u5173\u952e\u8bcd');
    }

    return ComicCandidateInfo(
      isCandidate: score >= threshold,
      score: score,
      reasons: reasons,
    );
  }
}

class HtmlComicParserService implements ComicParserService {
  static final RegExp _episodeTextPattern = RegExp(
    r'^(\d+(\.\d+)?\s*[\u8bdd\u8a71].*|\d+(\.\d+)?|\u7b2c\s*.+\s*[\u8bdd\u8a71]|.*\u7279\u5178.*)$',
  );
  final ComicPostParsingEngine _engine;
  final ForumPostDomExtractor _domExtractor;
  final ForumPostImageSourceCollector _imageSourceCollector;

  HtmlComicParserService({
    ComicPostParsingEngine? engine,
    ForumPostDomExtractor? domExtractor,
    ForumPostImageSourceCollector imageSourceCollector =
        const ForumPostImageSourceCollector(),
  }) : this._(
         engine: engine,
         domExtractor: domExtractor ?? const ForumPostDomExtractor(),
         imageSourceCollector: imageSourceCollector,
       );

  HtmlComicParserService._({
    required ComicPostParsingEngine? engine,
    required ForumPostDomExtractor domExtractor,
    required ForumPostImageSourceCollector imageSourceCollector,
  }) : _domExtractor = domExtractor,
       _imageSourceCollector = imageSourceCollector,
       _engine = engine ?? ComicPostParsingEngine(domExtractor: domExtractor);

  @override
  ParsedComicPost parse({required String message}) {
    return parseInput(ComicPostParseInput(messageHtml: message));
  }

  @override
  ParsedComicPost parseInput(ComicPostParseInput input) {
    final signals = <ComicParsingSignal>[];
    final domImageUrls = _domExtractor.extractImageSources(input.messageHtml);
    final imageUrls = _imageSourceCollector.merge(
      domImageUrls: domImageUrls,
      attachmentImageUrls: input.attachmentImageUrls,
    );
    signals
      ..add(
        ComicParsingSignal(
          stage: 'image',
          message: 'dom images=${domImageUrls.length}',
        ),
      )
      ..add(
        ComicParsingSignal(
          stage: 'image',
          message: 'attachment images=${input.attachmentImageUrls.length}',
        ),
      )
      ..add(
        ComicParsingSignal(
          stage: 'image',
          message: 'accepted images=${imageUrls.length}',
        ),
      );

    final parsedByEngine = _engine.parse(messageHtml: input.messageHtml);
    final episodeLinks = parsedByEngine.episodes
        .map(
          (episode) => ComicEpisodeLink(
            url: episode.url,
            rawText: episode.titleRaw,
            episodeTitle: _extractEpisodeTitle(episode.titleRaw),
          ),
        )
        .toList(growable: false);
    final catalogUrl = parsedByEngine.catalogLinks.isEmpty
        ? null
        : parsedByEngine.catalogLinks.first;
    signals.addAll(parsedByEngine.debugSignals);

    final plainText = _domExtractor
        .extractPlainText(input.messageHtml)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final debugInfo = ComicParsingDebugInfo(
      signals: signals,
      totalAnchors: _domExtractor.extractAnchors(input.messageHtml).length,
      totalEpisodeLinks: episodeLinks.length,
      catalogUrl: catalogUrl,
    );

    return ParsedComicPost(
      imageUrls: imageUrls,
      episodeLinks: episodeLinks,
      plainTextSummary: plainText,
      catalogUrl: catalogUrl,
      inferredAuthor: _inferAuthor(plainText),
      parsingDebug: debugInfo,
    );
  }

  String? _extractEpisodeTitle(String text) {
    if (text.isEmpty) {
      return null;
    }
    if (_episodeTextPattern.hasMatch(text)) {
      return text;
    }
    return null;
  }

  String? _inferAuthor(String plainText) {
    final authorMatch = RegExp(
      r'(\u4f5c\u8005|\u6c49\u5316|\u7ffb\u8bd1)[\uff1a:]\s*([^\s\uff0c\u3002\uff1b;]+)',
    ).firstMatch(plainText);
    return authorMatch?.group(2);
  }
}

extension _FirstOrNullExt<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
