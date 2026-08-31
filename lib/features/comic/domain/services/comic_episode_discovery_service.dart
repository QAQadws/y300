import 'dart:collection';

import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/comic/domain/repositories/comic_catalog_directory_reader.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_recursive_thread_eligibility_policy.dart';
import 'package:y300/features/comic/domain/services/comic_recursive_thread_request_governor.dart';
import 'package:y300/features/comic/domain/services/comic_thread_discovery_cache.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_request_governor.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';

enum EpisodeDiscoveryStrategy { direct, recursive, catalog }

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

class ComicEpisodeDiscoveryService {
  ComicEpisodeDiscoveryService({
    required ComicThreadDiscoveryRepository repository,
    required ComicConsecutiveOpPostParser opPostParser,
    required ComicCatalogDirectoryReader catalogDirectoryReader,
    ForumReferenceResolver references = const ForumReferenceResolver(
      siteOrigin: AppConfig.siteBaseUrl,
    ),
    ForumPostDomExtractor? domExtractor,
    ComicRecursiveThreadEligibilityPolicy eligibilityPolicy =
        const DefaultComicRecursiveThreadEligibilityPolicy(),
    ComicRecursiveThreadRequestGovernor? recursiveRequestGovernor,
    EpisodeDiscoveryConfig config = const EpisodeDiscoveryConfig(),
  }) : _repository = repository,
       _opPostParser = opPostParser,
       _catalogDirectoryReader = catalogDirectoryReader,
       _references = references,
       _domExtractor = domExtractor ?? const ForumPostDomExtractor(),
       _eligibilityPolicy = eligibilityPolicy,
       _recursiveRequestGovernor =
           recursiveRequestGovernor ??
           DefaultComicRecursiveThreadRequestGovernor(),
       _config = config;

  static final RegExp _subjectEpisodeNoPattern = RegExp(
    r'第\s*(\d+)\s*话',
    caseSensitive: false,
  );

  final ComicThreadDiscoveryRepository _repository;
  final ComicConsecutiveOpPostParser _opPostParser;
  final ComicCatalogDirectoryReader _catalogDirectoryReader;
  final ForumReferenceResolver _references;
  final ForumPostDomExtractor _domExtractor;
  final ComicRecursiveThreadEligibilityPolicy _eligibilityPolicy;
  final ComicRecursiveThreadRequestGovernor _recursiveRequestGovernor;
  final EpisodeDiscoveryConfig _config;

  Future<EpisodeDiscoveryResult> discoverFromTid(String tid) async {
    return discoverFromTidWithPreference(tid: tid, preferCatalogFirst: false);
  }

  /// 直接通过 catalogUrl 发现章节列表。
  ///
  /// 不需要先请求帖子详情。可独立调用，用于 catalog 快速路径。
  Future<List<ComicEpisodeLink>> discoverFromCatalogUrl(
    String catalogUrl, {
    FavoriteSyncRequestGovernor? governor,
  }) {
    return _discoverFromCatalog(catalogUrl, governor: governor);
  }

  Future<EpisodeDiscoveryResult> discoverFromTidWithPreference({
    required String tid,
    required bool preferCatalogFirst,
    // Search/current-only refresh needs current-post links without letting the
    // same catalog fallback run twice. The default keeps legacy discovery.
    bool allowCatalogFallback = true,
    FavoriteSyncRequestGovernor? governor,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
    ComicThreadDiscoveryCache? threadCache,
  }) async {
    final activeThreadCache = threadCache ?? ComicThreadDiscoveryCache();
    final root = await _fetchAndParse(
      tid,
      governor: governor,
      preloadedDetail: preloadedRootDetail,
      threadCache: activeThreadCache,
    );
    if (root == null) {
      return const EpisodeDiscoveryResult(
        strategy: EpisodeDiscoveryStrategy.direct,
        episodeLinks: <ComicEpisodeLink>[],
      );
    }

    if (allowCatalogFallback &&
        preferCatalogFirst &&
        root.parsed.catalogUrl != null) {
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

    final directLinks = root.parsed.episodeLinks;
    if (_isDirectEnough(directLinks)) {
      return EpisodeDiscoveryResult(
        strategy: EpisodeDiscoveryStrategy.direct,
        episodeLinks: directLinks,
        catalogUrl: root.parsed.catalogUrl,
      );
    }

    List<ComicEpisodeLink>? recursiveLinks;
    if (_shouldTryRecursive(root)) {
      final candidateSession = _ComicRecursiveCandidateValidationSession(
        policy: _eligibilityPolicy,
        loader: (candidateTid) => _fetchAndParse(
          candidateTid,
          governor: governor,
          threadCache: activeThreadCache,
          isRecursiveRequest: true,
        ),
      );
      recursiveLinks = await _discoverRecursive(
        root,
        candidateSession: candidateSession,
      );
      if (recursiveLinks.length > directLinks.length) {
        return EpisodeDiscoveryResult(
          strategy: EpisodeDiscoveryStrategy.recursive,
          episodeLinks: recursiveLinks,
          catalogUrl: root.parsed.catalogUrl,
        );
      }
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
      strategy: recursiveLinks == null
          ? EpisodeDiscoveryStrategy.direct
          : EpisodeDiscoveryStrategy.recursive,
      episodeLinks: recursiveLinks ?? directLinks,
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
    final subjectEpisodeNo = _tryParseSubjectEpisodeNo(root.document.subject);
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
    required _ComicRecursiveCandidateValidationSession candidateSession,
  }) async {
    final queue = Queue<String>();
    final scheduled = <String>{root.document.tid};
    final merged = <String, ComicEpisodeLink>{};
    final preferredLinks = <String, ComicEpisodeLink>{};
    var depth = 0;
    var consecutiveFailures = 0;

    void rememberLinks(List<ComicEpisodeLink> links) {
      for (final link in links) {
        final linkTid = _extractTidFromUrl(link.url);
        if (linkTid == null) {
          continue;
        }
        preferredLinks.putIfAbsent(linkTid, () => link);
      }
    }

    void enqueue(String candidateTid) {
      if (scheduled.add(candidateTid)) {
        queue.add(candidateTid);
      }
    }

    rememberLinks(root.parsed.episodeLinks);
    for (final candidateTid in root.recursiveTidCandidates) {
      enqueue(candidateTid);
    }

    while (queue.isNotEmpty &&
        depth < _config.maxRecursiveDepth &&
        consecutiveFailures < _config.maxConsecutiveFailures) {
      final currentTid = queue.removeFirst();
      final resolution = await candidateSession.resolve(currentTid);
      depth += 1;
      if (resolution.status == _CandidateValidationStatus.failed) {
        consecutiveFailures += 1;
        continue;
      }
      consecutiveFailures = 0;
      if (resolution.status == _CandidateValidationStatus.rejected) {
        continue;
      }

      final parsed = resolution.parsed!;
      merged.putIfAbsent(
        currentTid,
        () =>
            preferredLinks[currentTid] ??
            ComicEpisodeLink(
              url:
                  '${AppConfig.siteBaseUrl}/forum.php?mod=viewthread&tid=$currentTid',
              rawText: '上一话',
              episodeTitle: null,
            ),
      );
      rememberLinks(parsed.parsed.episodeLinks);
      for (final nextTid in parsed.recursiveTidCandidates) {
        enqueue(nextTid);
      }
    }

    return merged.values.toList(growable: false);
  }

  Future<List<ComicEpisodeLink>> _discoverFromCatalog(
    String? catalogUrl, {
    FavoriteSyncRequestGovernor? governor,
  }) async {
    if (catalogUrl == null || catalogUrl.isEmpty) {
      return const <ComicEpisodeLink>[];
    }
    final result = await _catalogDirectoryReader.load(
      ComicCatalogDirectoryRequest(
        catalogUrl: catalogUrl,
        maxPages: _config.maxCatalogPages,
        requestGate: governor == null
            ? null
            : _FavoriteCatalogRequestGate(governor),
      ),
    );
    return result.when(
      success: (directory, _, _) => directory.links,
      failure: (_) => const <ComicEpisodeLink>[],
    );
  }

  Future<_ParsedThreadRoot?> _fetchAndParse(
    String tid, {
    FavoriteSyncRequestGovernor? governor,
    ComicThreadDiscoveryDocument? preloadedDetail,
    ComicThreadDiscoveryCache? threadCache,
    bool isRecursiveRequest = false,
  }) async {
    if (preloadedDetail != null && preloadedDetail.tid == tid) {
      threadCache?.store(preloadedDetail);
      final parsed = _opPostParser.parse(
        tid: preloadedDetail.tid,
        fid: preloadedDetail.fid,
        subject: preloadedDetail.subject,
        posts: preloadedDetail.posts,
      );
      return _ParsedThreadRoot(
        document: preloadedDetail,
        parsed: parsed,
        recursiveTidCandidates: _collectRecursiveTidCandidates(
          tid: preloadedDetail.tid,
          episodeLinks: parsed.episodeLinks,
          posts: preloadedDetail.posts,
        ),
      );
    }
    final cached = threadCache?.get(tid);
    if (cached != null) {
      final parsed = _opPostParser.parse(
        tid: cached.tid,
        fid: cached.fid,
        subject: cached.subject,
        posts: cached.posts,
      );
      return _ParsedThreadRoot(
        document: cached,
        parsed: parsed,
        recursiveTidCandidates: _collectRecursiveTidCandidates(
          tid: cached.tid,
          episodeLinks: parsed.episodeLinks,
          posts: cached.posts,
        ),
      );
    }
    final result = await _runThreadRequest(
      governor: governor,
      isRecursiveRequest: isRecursiveRequest,
      action: () =>
          _repository.load(ComicThreadDiscoveryRequest(sourceTid: tid)),
    );
    return result.when(
      success: (data, _, _) {
        threadCache?.store(data);
        final parsed = _opPostParser.parse(
          tid: data.tid,
          fid: data.fid,
          subject: data.subject,
          posts: data.posts,
        );
        return _ParsedThreadRoot(
          document: data,
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
    required List<ComicThreadDiscoveryPost> posts,
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
      for (final candidateTid in _domExtractor.extractThreadTids(
        post.messageHtml,
      )) {
        if (candidateTid != tid) {
          candidates.add(candidateTid);
        }
      }
    }
    return candidates.toList(growable: false);
  }

  String? _extractTidFromUrl(String url) {
    return _references.extractTid(url);
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
    required FavoriteSyncRequestGovernor? governor,
    required bool isRecursiveRequest,
    required Future<T> Function() action,
  }) {
    Future<T> runWithFavoriteGovernor() {
      if (governor == null) {
        return action();
      }
      return governor.run(
        kind: FavoriteSyncRequestKind.comicThreadDetail,
        action: action,
      );
    }

    if (!isRecursiveRequest) {
      return runWithFavoriteGovernor();
    }
    return _recursiveRequestGovernor.schedule(runWithFavoriteGovernor);
  }
}

final class _FavoriteCatalogRequestGate implements ComicCatalogRequestGate {
  const _FavoriteCatalogRequestGate(this._governor);

  final FavoriteSyncRequestGovernor _governor;

  @override
  Future<T> run<T>(Future<T> Function() action) => _governor.run(
    kind: FavoriteSyncRequestKind.comicCatalogHtml,
    action: action,
  );
}

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
    required this.document,
    required this.parsed,
    required this.recursiveTidCandidates,
  });

  final ComicThreadDiscoveryDocument document;
  final ParsedComicPost parsed;
  final List<String> recursiveTidCandidates;
}

typedef _CandidateThreadLoader =
    Future<_ParsedThreadRoot?> Function(String tid);

enum _CandidateValidationStatus { eligible, rejected, failed }

class _CandidateValidationResolution {
  const _CandidateValidationResolution({required this.status, this.parsed});

  final _CandidateValidationStatus status;
  final _ParsedThreadRoot? parsed;
}

class _ComicRecursiveCandidateValidationSession {
  _ComicRecursiveCandidateValidationSession({
    required ComicRecursiveThreadEligibilityPolicy policy,
    required _CandidateThreadLoader loader,
  }) : _policy = policy,
       _loader = loader;

  final ComicRecursiveThreadEligibilityPolicy _policy;
  final _CandidateThreadLoader _loader;
  final Map<String, Future<_CandidateValidationResolution>> _resolutions =
      <String, Future<_CandidateValidationResolution>>{};

  Future<_CandidateValidationResolution> resolve(String tid) {
    final normalizedTid = tid.trim();
    return _resolutions.putIfAbsent(normalizedTid, () => _load(normalizedTid));
  }

  Future<_CandidateValidationResolution> _load(String tid) async {
    final parsed = await _loader(tid);
    if (parsed == null) {
      return const _CandidateValidationResolution(
        status: _CandidateValidationStatus.failed,
      );
    }
    if (!_policy.allows(
      fid: parsed.document.fid,
      typeid: parsed.document.typeId,
    )) {
      return const _CandidateValidationResolution(
        status: _CandidateValidationStatus.rejected,
      );
    }
    return _CandidateValidationResolution(
      status: _CandidateValidationStatus.eligible,
      parsed: parsed,
    );
  }
}
