import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/catalog_thread_html_parser.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

enum EpisodeDiscoveryStrategy {
  direct,
  recursive,
  catalog,
}

class EpisodeDiscoveryResult {
  const EpisodeDiscoveryResult({
    required this.strategy,
    required this.episodeLinks,
  });

  final EpisodeDiscoveryStrategy strategy;
  final List<ComicEpisodeLink> episodeLinks;
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
    EpisodeDiscoveryConfig config = const EpisodeDiscoveryConfig(),
  }) : _fetchThreadDetail = fetchThreadDetail,
       _opPostParser = opPostParser,
       _catalogHtmlFetcher = catalogHtmlFetcher,
       _catalogThreadHtmlParser = catalogThreadHtmlParser ?? CatalogThreadHtmlParser(),
       _config = config;

  static final RegExp _threadPathPattern = RegExp(
    r'thread-(\d+)-\d+-\d+\.html',
    caseSensitive: false,
  );
  static final RegExp _viewThreadPattern = RegExp(
    r'forum\.php\?[^#]*\bmod=viewthread\b[^#]*\btid=(\d+)',
    caseSensitive: false,
  );
  static final RegExp _damagedTidPattern = RegExp(
    r'(^|[?&;])tid=(\d+)(?:[&#]|$)',
    caseSensitive: false,
  );
  static final RegExp _subjectEpisodeNoPattern = RegExp(r'第\s*(\d+)\s*话', caseSensitive: false);

  final ThreadDetailFetcher _fetchThreadDetail;
  final ComicConsecutiveOpPostParser _opPostParser;
  final CatalogHtmlFetcher _catalogHtmlFetcher;
  final CatalogThreadHtmlParser _catalogThreadHtmlParser;
  final EpisodeDiscoveryConfig _config;

  Future<EpisodeDiscoveryResult> discoverFromTid(String tid) async {
    return discoverFromTidWithPreference(tid: tid, preferCatalogFirst: false);
  }

  Future<EpisodeDiscoveryResult> discoverFromTidWithPreference({
    required String tid,
    required bool preferCatalogFirst,
  }) async {
    final root = await _fetchAndParse(tid);
    if (root == null) {
      return const EpisodeDiscoveryResult(
        strategy: EpisodeDiscoveryStrategy.direct,
        episodeLinks: <ComicEpisodeLink>[],
      );
    }

    if (preferCatalogFirst && root.parsed.catalogUrl != null) {
      final catalogLinks = await _discoverFromCatalog(root.parsed.catalogUrl);
      if (catalogLinks.isNotEmpty) {
        return EpisodeDiscoveryResult(
          strategy: EpisodeDiscoveryStrategy.catalog,
          episodeLinks: catalogLinks,
        );
      }
    }

    if (_isDirectEnough(root.parsed.episodeLinks)) {
      return EpisodeDiscoveryResult(
        strategy: EpisodeDiscoveryStrategy.direct,
        episodeLinks: root.parsed.episodeLinks,
      );
    }

    final recursiveLinks = await _discoverRecursive(root);
    if (recursiveLinks.length > root.parsed.episodeLinks.length) {
      return EpisodeDiscoveryResult(
        strategy: EpisodeDiscoveryStrategy.recursive,
        episodeLinks: recursiveLinks,
      );
    }

    final catalogLinks = await _discoverFromCatalog(root.parsed.catalogUrl);
    if (catalogLinks.isNotEmpty) {
      return EpisodeDiscoveryResult(
        strategy: EpisodeDiscoveryStrategy.catalog,
        episodeLinks: catalogLinks,
      );
    }

    return EpisodeDiscoveryResult(
      strategy: EpisodeDiscoveryStrategy.direct,
      episodeLinks: root.parsed.episodeLinks,
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

  Future<List<ComicEpisodeLink>> _discoverRecursive(_ParsedThreadRoot root) async {
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
      final parsed = await _fetchAndParse(currentTid);
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

  Future<List<ComicEpisodeLink>> _discoverFromCatalog(String? catalogUrl) async {
    if (catalogUrl == null || catalogUrl.isEmpty) {
      return const <ComicEpisodeLink>[];
    }

    final queue = Queue<String>();
    final visitedPages = <String>{};
    final links = <String, ComicEpisodeLink>{};
    queue.add(catalogUrl);

    while (queue.isNotEmpty && visitedPages.length < _config.maxCatalogPages) {
      final pageUrl = queue.removeFirst();
      if (!visitedPages.add(pageUrl)) {
        continue;
      }

      final html = await _catalogHtmlFetcher.fetchHtml(pageUrl);
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
    }

    return links.values.toList(growable: false);
  }

  Future<_ParsedThreadRoot?> _fetchAndParse(String tid) async {
    final result = await _fetchThreadDetail(tid);
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

    // Fallback: recursive posts often only contain previous-link text,
    // which may not match strict episode semantic rules.
    for (final post in posts) {
      final html = post.message;
      for (final match in _threadPathPattern.allMatches(html)) {
        final candidateTid = match.group(1);
        if (candidateTid != null && candidateTid != tid) {
          candidates.add(candidateTid);
        }
      }
      for (final match in _viewThreadPattern.allMatches(html)) {
        final candidateTid = match.group(1);
        if (candidateTid != null && candidateTid != tid) {
          candidates.add(candidateTid);
        }
      }
      for (final match in _damagedTidPattern.allMatches(html)) {
        final candidateTid = match.group(2);
        if (candidateTid != null && candidateTid != tid) {
          candidates.add(candidateTid);
        }
      }
    }
    return candidates.toList(growable: false);
  }

  String? _extractTidFromUrl(String url) {
    final threadMatch = _threadPathPattern.firstMatch(url);
    if (threadMatch != null) {
      return threadMatch.group(1);
    }
    final viewThreadMatch = _viewThreadPattern.firstMatch(url);
    if (viewThreadMatch != null) {
      return viewThreadMatch.group(1);
    }
    final damagedMatch = _damagedTidPattern.firstMatch(url);
    return damagedMatch?.group(2);
  }
}

typedef ThreadDetailFetcher = Future<ApiResult<ThreadDetailData>> Function(String tid);

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
