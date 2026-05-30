import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/image_request_headers.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/core/network/site_url_resolver.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/comic_parser_service.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_parsing_debug_models.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/comic/domain/services/comic_detector.dart';
import 'package:y300/features/comic/domain/services/comic_reader_feature_flags.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/data/discuz_search_service.dart';
import 'package:y300/features/thread/data/thread_repository.dart';
import 'package:y300/features/thread/domain/services/forum_attachment_image_extractor.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';
import 'package:y300/features/thread/domain/services/forum_post_image_source_collector.dart';

final comicDetectorProvider = Provider<ComicDetector>((ref) {
  return RuleBasedComicDetector();
});

final comicParserServiceProvider = Provider<ComicParserService>((ref) {
  return HtmlComicParserService();
});

final comicSubjectParserProvider = Provider<ComicSubjectParser>((ref) {
  return const RuleBasedComicSubjectParser();
});

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
    ComicEpisodeRefreshRequest request,
  );

  /// Runs strategy 2 and strategy 3 for callers that already decided catalog
  /// refresh should not run immediately, such as the future search queue.
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request,
  );

  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid);
}

enum ComicEpisodeRefreshSource {
  catalog,
  search,
  currentOnly,
  empty,
}

class ComicEpisodeRefreshOutcome {
  const ComicEpisodeRefreshOutcome({
    required this.source,
    required this.links,
    this.usedSearch = false,
    this.catalogMatched = false,
  });

  final ComicEpisodeRefreshSource source;
  final List<ComicEpisodeLink> links;
  final bool usedSearch;
  final bool catalogMatched;

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
  });

  final String? comicId;
  final String sourceTid;
  final String? displayTitle;
  final String? sourceTitle;
  final String? customTitle;
  final String? customSearchTitle;
}

class NetworkComicEpisodeRefreshService implements ComicEpisodeRefreshService {
  NetworkComicEpisodeRefreshService({
    required ComicEpisodeDiscoveryService discoveryService,
    required ForumSearchService searchService,
    required ComicSubjectParser subjectParser,
    ComicReaderFeatureFlags featureFlags = ComicReaderFeatureFlags.defaults,
    ThreadSeedFetcher? threadSeedFetcher,
  }) : _discoveryService = discoveryService,
       _searchService = searchService,
       _subjectParser = subjectParser,
       _featureFlags = featureFlags,
       _threadSeedFetcher = threadSeedFetcher;

  final ComicEpisodeDiscoveryService _discoveryService;
  final ForumSearchService _searchService;
  final ComicSubjectParser _subjectParser;
  final ComicReaderFeatureFlags _featureFlags;
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
    final current = await _discoverCatalogFirst(request);
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
      );
    }

    return _fetchSearchAndCurrentOnly(
      request,
      current: current,
    );
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchCatalogOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    final current = await _discoverCatalogFirst(request);
    final catalogMatched =
        current.strategy == EpisodeDiscoveryStrategy.catalog &&
        current.episodeLinks.isNotEmpty;
    if (!catalogMatched) {
      _logRefresh(
        request,
        'strategy=catalog-only miss current=${current.episodeLinks.length}',
      );
      return const ComicEpisodeRefreshOutcome(
        source: ComicEpisodeRefreshSource.empty,
        links: <ComicEpisodeLink>[],
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
    );
  }

  @override
  Future<ComicEpisodeRefreshOutcome> fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request,
  ) async {
    final current = await _discoverCurrentOnly(request);
    return _fetchSearchAndCurrentOnly(request, current: current);
  }

  Future<EpisodeDiscoveryResult> _discoverCatalogFirst(
    ComicEpisodeRefreshRequest request,
  ) {
    return _discoveryService.discoverFromTidWithPreference(
      tid: request.sourceTid,
      preferCatalogFirst: true,
    );
  }

  Future<EpisodeDiscoveryResult> _discoverCurrentOnly(
    ComicEpisodeRefreshRequest request,
  ) {
    return _discoveryService.discoverFromTidWithPreference(
      tid: request.sourceTid,
      preferCatalogFirst: false,
      allowCatalogFallback: false,
    );
  }

  Future<ComicEpisodeRefreshOutcome> _fetchSearchAndCurrentOnly(
    ComicEpisodeRefreshRequest request, {
    required EpisodeDiscoveryResult current,
  }) async {
    final searchResult = await _searchFallbackFromCurrentTid(request);
    final searchLinks = searchResult.links;
    if (searchLinks.isNotEmpty) {
      final merged = _mergeEpisodeLinks(
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
    );
  }

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) {
    return fetchEpisodeLinks(ComicEpisodeRefreshRequest(sourceTid: tid));
  }

  Future<_SearchFallbackResult> _searchFallbackFromCurrentTid(
    ComicEpisodeRefreshRequest request,
  ) async {
    final keywordMode =
        _featureFlags.readerRefreshMultiKeywordEnabled ? 'multi' : 'single';
    _logRefresh(request, 'refreshKeywordMode=$keywordMode');
    final thread = await _fetchThreadDetail(request.sourceTid);
    if (thread == null) {
      return const _SearchFallbackResult.empty();
    }
    final keywords = _resolveSearchKeywords(request, thread.subject);
    var usedSearch = false;
    for (final keyword in keywords) {
      _logRefresh(request, 'keyword=${keyword.value} source=${keyword.source}');

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

      final candidates = _scoreSearchCandidates(
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

      const topK = 3;
      var collectedLinks = const <ComicEpisodeLink>[];
      final sourceTid = request.sourceTid.trim();
      final candidateBatch = candidates
          .where((item) => item.item.tid.trim() != sourceTid)
          .take(topK)
          .toList(growable: false);
      for (final candidate in candidateBatch) {
        final result = await _discoveryService.discoverFromTidWithPreference(
          tid: candidate.item.tid,
          preferCatalogFirst: true,
        );
        if (result.episodeLinks.isNotEmpty) {
          collectedLinks = _mergeEpisodeLinks(collectedLinks, result.episodeLinks);
        }
      }
      final searchCandidateLinks = _episodeLinksFromSearchCandidates(
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
          links: _sortEpisodeLinks(
            _mergeEpisodeLinks(
              collectedLinks,
              searchCandidateLinks,
              preferSupplement: true,
            ),
          ),
          usedSearch: true,
        );
      }
      return _SearchFallbackResult(
        links: _sortEpisodeLinks(collectedLinks),
        usedSearch: true,
      );
    }
    return _SearchFallbackResult(
      links: const <ComicEpisodeLink>[],
      usedSearch: usedSearch,
    );
  }

  List<_RefreshKeyword> _resolveSearchKeywords(
    ComicEpisodeRefreshRequest request,
    String subject,
  ) {
    final choices = <_RefreshKeyword>[
      _RefreshKeyword('customSearchTitle', request.customSearchTitle),
      _RefreshKeyword('customTitle', request.customTitle),
      _RefreshKeyword('displayTitle', _parseSearchTitle(request.displayTitle)),
      _RefreshKeyword('sourceTitle', _parseSearchTitle(request.sourceTitle)),
      _RefreshKeyword('subjectNormalized', _parseSearchTitle(subject)),
    ];
    final unique = <String, _RefreshKeyword>{};
    for (final choice in choices) {
      final value = choice.value.trim();
      if (value.isNotEmpty) {
        unique.putIfAbsent(value, () => _RefreshKeyword(choice.source, value));
        if (!_featureFlags.readerRefreshMultiKeywordEnabled) {
          break;
        }
      }
    }
    return unique.values.toList(growable: false);
  }

  String? _parseSearchTitle(String? title) {
    final raw = title?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final normalized = _subjectParser.parse(raw).normalizedTitle.trim();
    return normalized.isEmpty ? raw : normalized;
  }

  List<_ScoredSearchItem> _scoreSearchCandidates({
    required String threadSubject,
    required _RefreshKeyword keyword,
    required List<DiscuzSearchResultItem> items,
  }) {
    final currentScore = _scoreTitleSimilarity(threadSubject, keyword.value);
    final minScore = currentScore <= 0 ? 0.50 : currentScore - 0.25;
    final candidates = <_ScoredSearchItem>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final scored = _ScoredSearchItem(
        item: item,
        score: _scoreTitleSimilarity(item.title, keyword.value),
        searchIndex: index,
      );
      if (scored.score >= minScore) {
        candidates.add(scored);
      }
    }
    candidates.sort((a, b) {
      final scoreOrder = b.score.compareTo(a.score);
      if (scoreOrder != 0) {
        return scoreOrder;
      }
      return a.searchIndex.compareTo(b.searchIndex);
    });
    return candidates;
  }

  List<ComicEpisodeLink> _mergeEpisodeLinks(
    List<ComicEpisodeLink> primary,
    List<ComicEpisodeLink> supplement, {
    bool preferSupplement = false,
  }) {
    final merged = <String, ComicEpisodeLink>{};
    for (final link in primary) {
      merged.putIfAbsent(_linkIdentity(link), () => link);
    }
    for (final link in supplement) {
      final key = _linkIdentity(link);
      if (preferSupplement) {
        // 搜索/目录补全通常带有更完整的章节标题，重复 tid 时保留补全侧信息。
        merged[key] = link;
      } else {
        merged.putIfAbsent(key, () => link);
      }
    }
    return merged.values.toList(growable: false);
  }

  List<ComicEpisodeLink> _episodeLinksFromSearchCandidates(
    List<_ScoredSearchItem> candidates, {
    required String excludeTid,
  }) {
    final sorted = candidates.toList()
      ..sort((a, b) {
        final episodeOrder = _compareSearchEpisodeOrder(a.item.title, b.item.title);
        if (episodeOrder != 0) {
          return episodeOrder;
        }
        final tidOrder = _compareTid(a.item.tid, b.item.tid);
        if (tidOrder != 0) {
          return tidOrder;
        }
        return a.searchIndex.compareTo(b.searchIndex);
      });

    return _mergeEpisodeLinks(
      const <ComicEpisodeLink>[],
      sorted
          .where((candidate) => candidate.item.tid.trim() != excludeTid)
          .map(_episodeLinkFromSearchItem)
          .toList(growable: false),
    );
  }

  ComicEpisodeLink _episodeLinkFromSearchItem(_ScoredSearchItem candidate) {
    final item = candidate.item;
    final metadata = _subjectParser.parse(item.title);
    final episodeLabel = metadata.episodeLabel?.trim();
    return ComicEpisodeLink(
      url: item.url.trim(),
      rawText: item.title,
      episodeTitle: episodeLabel == null || episodeLabel.isEmpty ? item.title : episodeLabel,
    );
  }

  int _compareSearchEpisodeOrder(String a, String b) {
    final aKey = _EpisodeSortKey.tryParse(a);
    final bKey = _EpisodeSortKey.tryParse(b);
    if (aKey != null && bKey != null) {
      return aKey.compareTo(bKey);
    }
    if (aKey != null && bKey == null) {
      return -1;
    }
    if (aKey == null && bKey != null) {
      return 1;
    }
    return 0;
  }

  List<ComicEpisodeLink> _sortEpisodeLinks(List<ComicEpisodeLink> links) {
    final sorted = links.toList()
      ..sort((a, b) {
        final episodeOrder = _compareSearchEpisodeOrder(
          _linkTitleForSort(a),
          _linkTitleForSort(b),
        );
        if (episodeOrder != 0) {
          return episodeOrder;
        }
        final tidOrder = _compareTid(_linkIdentity(a), _linkIdentity(b));
        if (tidOrder != 0) {
          return tidOrder;
        }
        return _linkTitleForSort(a).compareTo(_linkTitleForSort(b));
      });
    return sorted;
  }

  String _linkTitleForSort(ComicEpisodeLink link) {
    final episodeTitle = link.episodeTitle?.trim();
    if (episodeTitle != null && episodeTitle.isNotEmpty) {
      return episodeTitle;
    }
    return link.rawText.trim();
  }

  int _compareTid(String a, String b) {
    final aTid = int.tryParse(a.replaceFirst('tid:', '').trim());
    final bTid = int.tryParse(b.replaceFirst('tid:', '').trim());
    if (aTid != null && bTid != null && aTid != bTid) {
      return aTid.compareTo(bTid);
    }
    if (aTid != null && bTid == null) {
      return -1;
    }
    if (aTid == null && bTid != null) {
      return 1;
    }
    return a.trim().compareTo(b.trim());
  }

  String _linkIdentity(ComicEpisodeLink link) {
    final uri = Uri.tryParse(link.url.trim());
    final tid = uri?.queryParameters['tid']?.trim();
    if (tid != null && tid.isNotEmpty) {
      return 'tid:$tid';
    }
    final threadMatch = RegExp(r'thread-(\d+)-', caseSensitive: false).firstMatch(link.url);
    final threadTid = threadMatch?.group(1)?.trim();
    if (threadTid != null && threadTid.isNotEmpty) {
      return 'tid:$threadTid';
    }
    return link.url.trim();
  }

  Future<ThreadSeed?> _fetchThreadDetail(String tid) async {
    final fetcher = _threadSeedFetcher;
    if (fetcher != null) {
      return fetcher(tid);
    }
    return null;
  }

  double _scoreTitleSimilarity(String title, String keyword) {
    final normalizedTitle = title.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final normalizedKeyword = keyword.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (normalizedTitle.isEmpty || normalizedKeyword.isEmpty) {
      return 0;
    }
    if (normalizedTitle.contains(normalizedKeyword)) {
      return 1;
    }
    final overlap = normalizedKeyword.split('').where(normalizedTitle.contains).length;
    return overlap / normalizedKeyword.length;
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

class _RefreshKeyword {
  const _RefreshKeyword(this.source, String? value) : value = value ?? '';

  final String source;
  final String value;
}

class _SearchFallbackResult {
  const _SearchFallbackResult({
    required this.links,
    required this.usedSearch,
  });

  const _SearchFallbackResult.empty()
      : links = const <ComicEpisodeLink>[],
        usedSearch = false;

  final List<ComicEpisodeLink> links;
  final bool usedSearch;
}

final comicEpisodeDiscoveryServiceProvider = Provider<ComicEpisodeDiscoveryService>((ref) {
  final engine = ComicPostParsingEngine();
  final opPostParser = ComicConsecutiveOpPostParser(engine: engine);
  return ComicEpisodeDiscoveryService(
    fetchThreadDetail: (tid) => ref.read(threadRepositoryProvider).getThreadDetail(tid: tid, page: 1),
    opPostParser: opPostParser,
    catalogHtmlFetcher: DioCatalogHtmlFetcher(),
  );
});

final comicEpisodeRefreshServiceProvider = Provider<ComicEpisodeRefreshService>((ref) {
  return NetworkComicEpisodeRefreshService(
    discoveryService: ref.read(comicEpisodeDiscoveryServiceProvider),
    searchService: ref.read(discuzSearchServiceProvider),
    subjectParser: ref.read(comicSubjectParserProvider),
    featureFlags: ref.watch(comicReaderFeatureFlagsProvider),
    threadSeedFetcher: (tid) async {
      final result = await ref.read(threadRepositoryProvider).getThreadDetail(tid: tid, page: 1);
      return result.when(
        success: (data) => ThreadSeed(subject: data.subject),
        failure: (_) => null,
      );
    },
  );
});

class _ScoredSearchItem {
  const _ScoredSearchItem({
    required this.item,
    required this.score,
    required this.searchIndex,
  });

  final DiscuzSearchResultItem item;
  final double score;
  final int searchIndex;
}

class _EpisodeSortKey implements Comparable<_EpisodeSortKey> {
  const _EpisodeSortKey({
    required this.number,
    required this.suffixRank,
  });

  static final RegExp _episodePattern = RegExp(
    r'第?\s*(\d+(?:\.\d+)?)\s*(?:话|話|卷|集|篇|章)\s*(上篇|下篇|前篇|后篇|後篇|上|中|下|前|后|後)?',
    caseSensitive: false,
  );

  final double number;
  final int suffixRank;

  static _EpisodeSortKey? tryParse(String title) {
    final match = _episodePattern.firstMatch(title);
    if (match == null) {
      return null;
    }
    final number = double.tryParse(match.group(1) ?? '');
    if (number == null) {
      return null;
    }
    return _EpisodeSortKey(
      number: number,
      suffixRank: _suffixRank(match.group(2)),
    );
  }

  static int _suffixRank(String? suffix) {
    return switch (suffix?.trim()) {
      '前' || '前篇' => -30,
      '上' || '上篇' => -20,
      '中' => 0,
      null || '' => 10,
      '下' || '下篇' => 20,
      '后' || '後' || '后篇' || '後篇' => 30,
      _ => 10,
    };
  }

  @override
  int compareTo(_EpisodeSortKey other) {
    final numberOrder = number.compareTo(other.number);
    if (numberOrder != 0) {
      return numberOrder;
    }
    return suffixRank.compareTo(other.suffixRank);
  }
}

class ThreadSeed {
  const ThreadSeed({required this.subject});

  final String subject;
}

typedef ThreadSeedFetcher = Future<ThreadSeed?> Function(String tid);

abstract class ComicReaderService {
  Future<List<String>> fetchEpisodeImagesByTid(String tid);

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
    required ComicParserService parserService,
    ImageCacheService? imageCacheService,
    BaseCacheManager? cacheManager,
    ImageRequestHeaderBuilder? headerBuilder,
    SiteUrlResolver urlResolver = const SiteUrlResolver(),
    ForumAttachmentImageExtractor attachmentImageExtractor = const ForumAttachmentImageExtractor(),
  })  : _threadRepository = threadRepository,
        _parserService = parserService,
        _imageCacheService = imageCacheService,
        _cacheManager = cacheManager ?? DefaultCacheManager(),
        _headerBuilder = headerBuilder,
        _urlResolver = urlResolver,
        _attachmentImageExtractor = attachmentImageExtractor;

  final ThreadRepository _threadRepository;
  final ComicParserService _parserService;
  final ImageCacheService? _imageCacheService;
  final BaseCacheManager _cacheManager;
  final ImageRequestHeaderBuilder? _headerBuilder;
  final SiteUrlResolver _urlResolver;
  final ForumAttachmentImageExtractor _attachmentImageExtractor;

  @override
  Future<List<String>> fetchEpisodeImagesByTid(String tid) async {
    final result = await _threadRepository.getThreadDetail(tid: tid, page: 1);
    return result.when(
      success: (data) {
        final firstPost = data.posts.where((post) => post.isFirst).firstOrNull;
        if (firstPost == null) {
          return const <String>[];
        }
        return _parserService
            .parseInput(
              ComicPostParseInput(
                messageHtml: firstPost.message,
                attachmentImageUrls: _attachmentImageExtractor.extractImageUrls(firstPost),
              ),
            )
            .imageUrls;
      },
      failure: (_) => const <String>[],
    );
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
        key: normalizedKey == null || normalizedKey.isEmpty ? sourceUrl : normalizedKey,
        authHeaders: headers.isEmpty ? null : headers,
      );
      return ComicImageCacheResult(
        success: true,
        localPath: fileInfo.file.path,
        cacheKey: normalizedKey == null || normalizedKey.isEmpty ? sourceUrl : normalizedKey,
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

final comicReaderServiceProvider = FutureProvider<ComicReaderService>((ref) async {
  return NetworkComicReaderService(
    threadRepository: ref.read(threadRepositoryProvider),
    parserService: ref.read(comicParserServiceProvider),
    imageCacheService: ref.read(imageCacheServiceProvider),
    cacheManager: await ref.read(comicCacheManagerProvider.future),
    headerBuilder: ref.read(imageRequestHeaderBuilderProvider),
  );
});

final comicFirstEpisodeCoverServiceProvider = Provider<ComicFirstEpisodeCoverService>((ref) {
  return ComicFirstEpisodeCoverService(
    repository: ref.watch(comicRepositoryProvider),
    fetchEpisodeImagesByTid: (tid) async {
      final readerService = await ref.read(comicReaderServiceProvider.future);
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

    final imageCount = RegExp(r'<img\b', caseSensitive: false).allMatches(message).length;
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
    r'^(\d+(\.\d+)?|\u7b2c\s*.+\s*\u8bdd|.*\u7279\u5178.*)$',
  );
  final ComicPostParsingEngine _engine;
  final ForumPostDomExtractor _domExtractor;
  final ForumPostImageSourceCollector _imageSourceCollector;

  HtmlComicParserService({
    ComicPostParsingEngine? engine,
    ForumPostDomExtractor? domExtractor,
    ForumPostImageSourceCollector imageSourceCollector = const ForumPostImageSourceCollector(),
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
      ..add(ComicParsingSignal(stage: 'image', message: 'dom images=${domImageUrls.length}'))
      ..add(ComicParsingSignal(stage: 'image', message: 'attachment images=${input.attachmentImageUrls.length}'))
      ..add(ComicParsingSignal(stage: 'image', message: 'accepted images=${imageUrls.length}'));

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
    final catalogUrl = parsedByEngine.catalogLinks.isEmpty ? null : parsedByEngine.catalogLinks.first;
    signals.addAll(parsedByEngine.debugSignals);

    final plainText = _domExtractor.extractPlainText(input.messageHtml).replaceAll(RegExp(r'\s+'), ' ').trim();

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
    final authorMatch = RegExp(r'(\u4f5c\u8005|\u6c49\u5316|\u7ffb\u8bd1)[\uff1a:]\s*([^\s\uff0c\u3002\uff1b;]+)').firstMatch(plainText);
    return authorMatch?.group(2);
  }
}

extension _FirstOrNullExt<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
