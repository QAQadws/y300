import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/catalog_thread_html_parser.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/favorites/data/favorite_first_sync_request_governor.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';
import 'package:y300/features/thread/domain/services/forum_thread_url_parser.dart';

enum EpisodeDiscoveryStrategy {
  direct,
  recursive,
  catalog,
}

class EpisodeDiscoveryResult {
  const EpisodeDiscoveryResult({
    required this.strategy,
    required this.episodeLinks,
    this.catalogUrl,
  });

  final EpisodeDiscoveryStrategy strategy;
  final List<ComicEpisodeLink> episodeLinks;
  /// 本次发现过程中解析出的 catalogUrl（可能为 null）。
  final String? catalogUrl;
}

class EpisodeDiscoveryConfig {
  const EpisodeDiscoveryConfig({
    this.directEnoughThreshold = 3,
    this.maxRecursiveDepth = 200,
    this.maxConsecutiveFailures = 3,
    this.maxCatalogPages = 10,
  });

  final int directEnoughThreshold;
  final int maxRecursiveDepth;
  final int maxConsecutiveFailures;
  final int maxCatalogPages;
}

abstract class CatalogHtmlFetcher {
  Future<String?> fetchHtml(String url);
}

class DioCatalogHtmlFetcher implements CatalogHtmlFetcher {
  DioCatalogHtmlFetcher({
    Dio? dio,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: AppConfig.connectTimeout,
               receiveTimeout: AppConfig.receiveTimeout,
             ),
           );

  final Dio _dio;

  @override
  Future<String?> fetchHtml(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
      );
      return response.data;
    } catch (_) {
      return null;
    }
  }
}

class ComicEpisodeDiscoveryService {
  ComicEpisodeDiscoveryService({
    required ThreadDetailFetcher fetchThreadDetail,
    required ComicConsecutiveOpPostParser opPostParser,
    required CatalogHtmlFetcher catalogHtmlFetcher,
    CatalogThreadHtmlParser? catalogThreadHtmlParser,
    ForumPostDomExtractor? domExtractor,
    ForumThreadUrlParser? urlParser,
    EpisodeDiscoveryConfig config = const EpisodeDiscoveryConfig(),
  }) : _fetchThreadDetail = fetchThreadDetail,
       _opPostParser = opPostParser,
       _catalogHtmlFetcher = catalogHtmlFetcher,
       _catalogThreadHtmlParser = catalogThreadHtmlParser ?? CatalogThreadHtmlParser(),
       _domExtractor = domExtractor ?? ForumPostDomExtractor(urlParser: urlParser ?? const ForumThreadUrlParser()),
       _urlParser = urlParser ?? const ForumThreadUrlParser(),
       _config = config;

  static final RegExp _subjectEpisodeNoPattern = RegExp(r'第\s*(\d+)\s*话', caseSensitive: false);

  final ThreadDetailFetcher _fetchThreadDetail;
  final ComicConsecutiveOpPostParser _opPostParser;
  final CatalogHtmlFetcher _catalogHtmlFetcher;
  final CatalogThreadHtmlParser _catalogThreadHtmlParser;
  final ForumPostDomExtractor _domExtractor;
  final ForumThreadUrlParser _urlParser;
  final EpisodeDiscoveryConfig _config;

  Future<EpisodeDiscoveryResult> discoverFromTid(String tid) async {
    return discoverFromTidWithPreference(tid: tid, preferCatalogFirst: false);
  }

  /// 直接通过 catalogUrl 发现章节列表。
  ///
  /// 不需要先请求帖子详情。可独立调用，用于 catalog 快速路径。
  Future<List<ComicEpisodeLink>> discoverFromCatalogUrl(
    String catalogUrl, {
    FavoriteFirstSyncRequestGovernor? governor,
  }) {
    return _discoverFromCatalog(catalogUrl, governor: governor);
  }

  Future<EpisodeDiscoveryResult> discoverFromTidWithPreference({
    required String tid,
    required bool preferCatalogFirst,
    // Search/current-only refresh needs current-post links without letting the
    // same catalog fallback run twice. The default keeps legacy discovery.
    bool allowCatalogFallback = true,
    FavoriteFirstSyncRequestGovernor? governor,
  }) async {
    final root = await _fetchAndParse(tid, governor: governor);
    if (root == null) {
      return const EpisodeDiscoveryResult(
        strategy: EpisodeDiscoveryStrategy.direct,
        episodeLinks: <ComicEpisodeLink>[],
      );
    }

    if (allowCatalogFallback && preferCatalogFirst && root.parsed.catalogUrl != null) {
      final catalogLinks = await _discoverFromCatalog(
        root.parsed.catalogUrl,
        governor: governor,
      );
      if (catalogLinks.isNotEmpty) {
        return EpisodeDiscoveryResult(
          strategy: EpisodeDiscoveryStrategy.catalog,
          episodeLinks: catalogLinks,
          catalogUrl: root.parsed.catalogUrl,
        );
      }
    }

    if (_isDirectEnough(root.parsed.episodeLinks)) {
      return EpisodeDiscoveryResult(
        strategy: EpisodeDiscoveryStrategy.direct,
        episodeLinks: root.parsed.episodeLinks,
        catalogUrl: root.parsed.catalogUrl,
      );
    }

    final recursiveLinks = await _discoverRecursive(root, governor: governor);
    if (recursiveLinks.length > root.parsed.episodeLinks.length) {
      return EpisodeDiscoveryResult(
        strategy: EpisodeDiscoveryStrategy.recursive,
        episodeLinks: recursiveLinks,
        catalogUrl: root.parsed.catalogUrl,
      );
    }

    if (allowCatalogFallback) {
      final catalogLinks = await _discoverFromCatalog(
        root.parsed.catalogUrl,
        governor: governor,
      );
      if (catalogLinks.isNotEmpty) {
        return EpisodeDiscoveryResult(
          strategy: EpisodeDiscoveryStrategy.catalog,
          episodeLinks: catalogLinks,
          catalogUrl: root.parsed.catalogUrl,
        );
      }
    }

    return EpisodeDiscoveryResult(
      strategy: EpisodeDiscoveryStrategy.direct,
      episodeLinks: root.parsed.episodeLinks,
      catalogUrl: root.parsed.catalogUrl,
    );
  }

  bool _isDirectEnough(List<ComicEpisodeLink> links) {
    return links.length >= _config.directEnoughThreshold;
  }

  bool _shouldTryRecursive(_ParsedThreadRoot root) {
    final candidateCount = root.recursiveTidCandidates.length;
    if (candidateCount == 0 || candidateCount > 2) {
      return false;
    }
    final subjectEpisodeNo = _tryParseSubjectEpisodeNo(root.detail.subject);
    if (subjectEpisodeNo == null) {
      return true;
    }
    return subjectEpisodeNo > candidateCount + 1;
  }

  int? _tryParseSubjectEpisodeNo(String subject) {
    final match = _subjectEpisodeNoPattern.firstMatch(subject);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1) ?? '');
  }

  Future<List<ComicEpisodeLink>> _discoverRecursive(
    _ParsedThreadRoot root, {
    FavoriteFirstSyncRequestGovernor? governor,
  }) async {
    if (!_shouldTryRecursive(root)) {
      return root.parsed.episodeLinks;
    }

    final queue = Queue<String>();
    final visited = <String>{root.detail.tid};
    final merged = <String, ComicEpisodeLink>{};
    var depth = 0;
    var consecutiveFailures = 0;

    void addLinks(List<ComicEpisodeLink> links) {
      for (final link in links) {
        final linkTid = _extractTidFromUrl(link.url);
        if (linkTid == null) {
          continue;
        }
        merged.putIfAbsent(linkTid, () => link);
      }
    }

    void addWeakTidCandidates(Iterable<String> tids) {
      for (final candidateTid in tids) {
        merged.putIfAbsent(
          candidateTid,
          () => ComicEpisodeLink(
            url: '${AppConfig.siteBaseUrl}/forum.php?mod=viewthread&tid=$candidateTid',
            rawText: '上一话',
            episodeTitle: null,
          ),
        );
      }
    }

    addLinks(root.parsed.episodeLinks);
    addWeakTidCandidates(root.recursiveTidCandidates);
    for (final candidateTid in root.recursiveTidCandidates) {
      if (visited.add(candidateTid)) {
        queue.add(candidateTid);
      }
    }

    while (queue.isNotEmpty &&
        depth < _config.maxRecursiveDepth &&
        consecutiveFailures < _config.maxConsecutiveFailures) {
      final currentTid = queue.removeFirst();
      final parsed = await _fetchAndParse(currentTid, governor: governor);
      depth += 1;
      if (parsed == null) {
        consecutiveFailures += 1;
        continue;
      }
      consecutiveFailures = 0;

      addLinks(parsed.parsed.episodeLinks);
      addWeakTidCandidates(parsed.recursiveTidCandidates);
      for (final nextTid in parsed.recursiveTidCandidates) {
        if (visited.add(nextTid)) {
          queue.add(nextTid);
        }
      }
    }

    return merged.values.toList(growable: false);
  }

  Future<List<ComicEpisodeLink>> _discoverFromCatalog(
    String? catalogUrl, {
    FavoriteFirstSyncRequestGovernor? governor,
  }) async {
    if (catalogUrl == null || catalogUrl.isEmpty) {
      return const <ComicEpisodeLink>[];
    }

    final queue = Queue<String>();
    final visitedPages = <String>{};
    final links = <String, ComicEpisodeLink>{};
    final normalizedEntry = _normalizeCatalogEntryUrl(catalogUrl);
    queue.add(normalizedEntry);

    while (queue.isNotEmpty && visitedPages.length < _config.maxCatalogPages) {
      final pageUrl = queue.removeFirst();
      if (!visitedPages.add(pageUrl)) {
        continue;
      }

      final html = await _runCatalogRequest(
        governor: governor,
        action: () => _catalogHtmlFetcher.fetchHtml(pageUrl),
      );
      if (html == null || html.isEmpty) {
        continue;
      }

      final parsedCatalog = _catalogThreadHtmlParser.parse(
        html: html,
        pageUrl: pageUrl,
      );

      for (final entry in parsedCatalog.entries) {
        links.putIfAbsent(
          entry.tid,
          () => ComicEpisodeLink(
            url: entry.url,
            rawText: entry.subject.isEmpty ? '目录条目' : entry.subject,
            episodeTitle: entry.subject.isEmpty ? null : entry.subject,
          ),
        );
      }

      final nextPage = parsedCatalog.nextPageUrl;
      if (nextPage != null && !visitedPages.contains(nextPage)) {
        queue.add(nextPage);
      }

      // When parser can infer total pages, eagerly enqueue remaining pages to avoid missing tails.
      final basePageUri = Uri.tryParse(pageUrl);
      final currentPage = parsedCatalog.currentPage ?? int.tryParse(basePageUri?.queryParameters['page'] ?? '') ?? 1;
      final totalPages = parsedCatalog.totalPages;
      if (basePageUri != null && totalPages != null && totalPages > currentPage) {
        for (var page = currentPage + 1; page <= totalPages; page++) {
          final candidate = _withPage(basePageUri, page).toString();
          if (!visitedPages.contains(candidate)) {
            queue.add(candidate);
          }
        }
      }
    }

    return links.values.toList(growable: false);
  }

  String _normalizeCatalogEntryUrl(String rawUrl) {
    final parsed = Uri.tryParse(rawUrl.trim());
    if (parsed == null) {
      return rawUrl;
    }
    final resolved = parsed.hasScheme ? parsed : Uri.parse('${AppConfig.siteBaseUrl}/').resolveUri(parsed);
    final params = Map<String, String>.from(resolved.queryParameters);
    if ((params['mod'] ?? '').toLowerCase() == 'tag') {
      params['type'] = 'thread';
      params['page'] = params['page']?.trim().isNotEmpty == true ? params['page']! : '1';
      return resolved.replace(queryParameters: params).toString();
    }
    return resolved.toString();
  }

  Uri _withPage(Uri uri, int page) {
    final params = Map<String, String>.from(uri.queryParameters);
    params['page'] = page.toString();
    if ((params['mod'] ?? '').toLowerCase() == 'tag') {
      params['type'] = 'thread';
    }
    return uri.replace(queryParameters: params);
  }

  Future<_ParsedThreadRoot?> _fetchAndParse(
    String tid, {
    FavoriteFirstSyncRequestGovernor? governor,
  }) async {
    final result = await _runThreadRequest(
      governor: governor,
      action: () => _fetchThreadDetail(tid),
    );
    return result.when(
      success: (data) {
        final parsed = _opPostParser.parse(
          tid: data.tid,
          fid: data.fid,
          subject: data.subject,
          posts: data.posts,
        );
        return _ParsedThreadRoot(
          detail: data,
          parsed: parsed,
          recursiveTidCandidates: _collectRecursiveTidCandidates(
            tid: data.tid,
            episodeLinks: parsed.episodeLinks,
            posts: data.posts,
          ),
        );
      },
      failure: (_) => null,
    );
  }

  List<String> _collectRecursiveTidCandidates({
    required String tid,
    required List<ComicEpisodeLink> episodeLinks,
    required List<ThreadPost> posts,
  }) {
    final candidates = <String>{};
    for (final link in episodeLinks) {
      final candidateTid = _extractTidFromUrl(link.url);
      if (candidateTid != null && candidateTid != tid) {
        candidates.add(candidateTid);
      }
    }

    // Fallback: recursive posts often only contain previous-link anchors,
    // which may not match strict episode semantic rules. Keep this DOM-based
    // so plain text, scripts, and quoted raw URLs are not promoted accidentally.
    for (final post in posts) {
      for (final candidateTid in _domExtractor.extractThreadTids(post.message)) {
        if (candidateTid != tid) {
          candidates.add(candidateTid);
        }
      }
    }
    return candidates.toList(growable: false);
  }

  String? _extractTidFromUrl(String url) {
    return _urlParser.extractTid(url);
  }

  /// 获取并解析帖子详情，返回跳转链接和候选 tid。
  ///
  /// 用于增量发现：adapter 调用后根据 [ParsedThreadResult] 决定
  /// direct/recursive 增量策略。返回 null 表示请求或解析失败。
  Future<ParsedThreadResult?> fetchAndParseThread(String tid) async {
    final root = await _fetchAndParse(tid);
    if (root == null) return null;
    return ParsedThreadResult(
      episodeLinks: root.parsed.episodeLinks,
      recursiveTidCandidates: root.recursiveTidCandidates,
      catalogUrl: root.parsed.catalogUrl,
    );
  }

  Future<T> _runThreadRequest<T>({
    required FavoriteFirstSyncRequestGovernor? governor,
    required Future<T> Function() action,
  }) {
    if (governor == null) {
      return action();
    }
    return governor.run(
      kind: FavoriteFirstSyncRequestKind.comicThreadDetail,
      action: action,
    );
  }

  Future<T> _runCatalogRequest<T>({
    required FavoriteFirstSyncRequestGovernor? governor,
    required Future<T> Function() action,
  }) {
    if (governor == null) {
      return action();
    }
    return governor.run(
      kind: FavoriteFirstSyncRequestKind.comicCatalogHtml,
      action: action,
    );
  }
}

typedef ThreadDetailFetcher = Future<ApiResult<ThreadDetailData>> Function(String tid);

/// 帖子解析结果（public），用于增量发现。
///
/// 由 [ComicEpisodeDiscoveryService.fetchAndParseThread] 返回，
/// 包含帖子内的跳转链接、递归候选 tid 和 catalogUrl。
class ParsedThreadResult {
  const ParsedThreadResult({
    required this.episodeLinks,
    required this.recursiveTidCandidates,
    required this.catalogUrl,
  });

  final List<ComicEpisodeLink> episodeLinks;
  final List<String> recursiveTidCandidates;
  final String? catalogUrl;
}

class _ParsedThreadRoot {
  const _ParsedThreadRoot({
    required this.detail,
    required this.parsed,
    required this.recursiveTidCandidates,
  });

  final ThreadDetailData detail;
  final ParsedComicPost parsed;
  final List<String> recursiveTidCandidates;
}
