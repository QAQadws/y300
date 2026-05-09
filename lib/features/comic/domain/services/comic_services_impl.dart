import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/comic_parser_service.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/models/comic_parsing_debug_models.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_post_parsing_engine.dart';
import 'package:y300/features/comic/domain/services/comic_detector.dart';
import 'package:y300/features/comic/domain/services/comic_subject_parser.dart';
import 'package:y300/features/search/data/models/discuz_search_models.dart';
import 'package:y300/features/search/data/discuz_search_service.dart';
import 'package:y300/features/thread/data/thread_repository.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';

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
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid);
}

class NetworkComicEpisodeRefreshService implements ComicEpisodeRefreshService {
  NetworkComicEpisodeRefreshService({
    required ComicEpisodeDiscoveryService discoveryService,
    required ForumSearchService searchService,
    required ComicSubjectParser subjectParser,
    ThreadSeedFetcher? threadSeedFetcher,
  }) : _discoveryService = discoveryService,
       _searchService = searchService,
       _subjectParser = subjectParser,
       _threadSeedFetcher = threadSeedFetcher;

  final ComicEpisodeDiscoveryService _discoveryService;
  final ForumSearchService _searchService;
  final ComicSubjectParser _subjectParser;
  final ThreadSeedFetcher? _threadSeedFetcher;

  @override
  Future<List<ComicEpisodeLink>> fetchEpisodeLinksFromTid(String tid) async {
    // 当前帖的连续跳转链接常只覆盖“上一话/历史话”，不能作为完整章节表。
    // 因此仅在目录解析成功时直接信任；否则继续走搜索补全，并按 tid 合并。
    final current = await _discoveryService.discoverFromTidWithPreference(
      tid: tid,
      preferCatalogFirst: true,
    );
    if (current.strategy == EpisodeDiscoveryStrategy.catalog && current.episodeLinks.isNotEmpty) {
      return current.episodeLinks;
    }

    final searchLinks = await _searchFallbackFromCurrentTid(tid);
    if (searchLinks.isNotEmpty) {
      return _mergeEpisodeLinks(
        current.episodeLinks,
        searchLinks,
        preferSupplement: true,
      );
    }

    return current.episodeLinks;
  }

  Future<List<ComicEpisodeLink>> _searchFallbackFromCurrentTid(String tid) async {
    final thread = await _fetchThreadDetail(tid);
    if (thread == null) {
      return const <ComicEpisodeLink>[];
    }
    final keyword = _subjectParser.parse(thread.subject).normalizedTitle.trim();
    if (keyword.isEmpty) {
      return const <ComicEpisodeLink>[];
    }

    final search = await _searchService.searchForum(
      keyword: keyword,
      context: const DiscuzSearchContext.curForum(srhfid: '30'),
      enforceRateLimit: true,
    );
    if (search.rateLimited || search.items.isEmpty) {
      return const <ComicEpisodeLink>[];
    }

    final currentScore = _scoreTitleSimilarity(thread.subject, keyword);
    final candidates = search.items
        .map(
          (item) => _ScoredSearchItem(
            item: item,
            score: _scoreTitleSimilarity(item.title, keyword),
          ),
        )
        .where((item) => item.score >= currentScore - 0.25)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    const topK = 3;
    var collectedLinks = const <ComicEpisodeLink>[];
    for (final candidate in candidates
        .where((item) => item.item.tid.trim() != tid.trim())
        .take(topK)) {
      final result = await _discoveryService.discoverFromTidWithPreference(
        tid: candidate.item.tid,
        preferCatalogFirst: true,
      );
      if (result.episodeLinks.isNotEmpty) {
        collectedLinks = _mergeEpisodeLinks(collectedLinks, result.episodeLinks);
      }
    }
    return collectedLinks;
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
  });

  final DiscuzSearchResultItem item;
  final double score;
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
  })  : _threadRepository = threadRepository,
        _parserService = parserService,
        _imageCacheService = imageCacheService,
        _cacheManager = cacheManager ?? DefaultCacheManager();

  final ThreadRepository _threadRepository;
  final ComicParserService _parserService;
  final ImageCacheService? _imageCacheService;
  final BaseCacheManager _cacheManager;

  @override
  Future<List<String>> fetchEpisodeImagesByTid(String tid) async {
    final result = await _threadRepository.getThreadDetail(tid: tid, page: 1);
    return result.when(
      success: (data) {
        final firstPost = data.posts.where((post) => post.isFirst).firstOrNull;
        if (firstPost == null) {
          return const <String>[];
        }
        return _parserService.parse(message: firstPost.message).imageUrls;
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
          sourceUrl: imageUrl,
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
      final fileInfo = await _cacheManager.downloadFile(
        imageUrl,
        key: normalizedKey == null || normalizedKey.isEmpty ? imageUrl : normalizedKey,
      );
      return ComicImageCacheResult(
        success: true,
        localPath: fileInfo.file.path,
        cacheKey: normalizedKey == null || normalizedKey.isEmpty ? imageUrl : normalizedKey,
        bytes: await fileInfo.file.length(),
      );
    } catch (_) {
      return const ComicImageCacheResult(success: false);
    }
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

  HtmlComicParserService({
    ComicPostParsingEngine? engine,
    ForumPostDomExtractor? domExtractor,
  }) : _domExtractor = domExtractor ?? const ForumPostDomExtractor(),
       _engine = engine ?? ComicPostParsingEngine(domExtractor: domExtractor);

  @override
  ParsedComicPost parse({required String message}) {
    final signals = <ComicParsingSignal>[];
    final imageUrls = _domExtractor.extractImageSources(message);
    signals.add(ComicParsingSignal(stage: 'image', message: 'accepted images=${imageUrls.length}'));

    final parsedByEngine = _engine.parse(messageHtml: message);
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

    final plainText = _domExtractor.extractPlainText(message).replaceAll(RegExp(r'\s+'), ' ').trim();

    final debugInfo = ComicParsingDebugInfo(
      signals: signals,
      totalAnchors: _domExtractor.extractAnchors(message).length,
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
