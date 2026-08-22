import 'package:y300/core/config/app_config.dart';
import 'package:y300/features/comic/domain/models/comic_models.dart';
import 'package:y300/features/comic/domain/services/comic_consecutive_op_post_parser.dart';
import 'package:y300/features/comic/domain/services/comic_episode_discovery_service.dart';
import 'package:y300/features/comic/domain/services/comic_recursive_thread_eligibility_policy.dart';
import 'package:y300/features/comic/domain/services/comic_recursive_thread_request_governor.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/services/forum_post_dom_extractor.dart';
import 'package:y300/features/thread/domain/services/forum_thread_url_parser.dart';

/// 增量章节发现服务。
///
/// 与全量 [ComicEpisodeDiscoveryService] 不同，本服务基于已知章节
/// tid 集合做增量更新：
/// - direct 模式只做本地 tid 差集，不发网络请求
/// - recursive 模式沿帖子内"上一话"超链接回溯，遇到已知 tid 立即终止
class ComicIncrementalEpisodeDiscovery {
  ComicIncrementalEpisodeDiscovery({
    required ThreadDetailFetcher fetchThreadDetail,
    required ComicConsecutiveOpPostParser opPostParser,
    ForumPostDomExtractor? domExtractor,
    ForumThreadUrlParser? urlParser,
    ComicRecursiveThreadEligibilityPolicy eligibilityPolicy =
        const DefaultComicRecursiveThreadEligibilityPolicy(),
    ComicRecursiveThreadRequestGovernor? recursiveRequestGovernor,
    int maxRecursiveDepth = 50,
    int maxConsecutiveFailures = 3,
  }) : _fetchThreadDetail = fetchThreadDetail,
       _opPostParser = opPostParser,
       _domExtractor =
           domExtractor ??
           ForumPostDomExtractor(
             urlParser: urlParser ?? const ForumThreadUrlParser(),
           ),
       _urlParser = urlParser ?? const ForumThreadUrlParser(),
       _eligibilityPolicy = eligibilityPolicy,
       _recursiveRequestGovernor =
           recursiveRequestGovernor ??
           DefaultComicRecursiveThreadRequestGovernor(),
       _maxRecursiveDepth = maxRecursiveDepth,
       _maxConsecutiveFailures = maxConsecutiveFailures;

  final ThreadDetailFetcher _fetchThreadDetail;
  final ComicConsecutiveOpPostParser _opPostParser;
  final ForumPostDomExtractor _domExtractor;
  final ForumThreadUrlParser _urlParser;
  final ComicRecursiveThreadEligibilityPolicy _eligibilityPolicy;
  final ComicRecursiveThreadRequestGovernor _recursiveRequestGovernor;
  final int _maxRecursiveDepth;
  final int _maxConsecutiveFailures;

  /// Direct 增量：从已解析的链接列表中，倒序提取新 tid。
  ///
  /// [currentLinks] 是当前帖解析出的跳转链接。
  /// [knownTids] 是本地已有章节的 tid 集合。
  /// 返回不在 knownTids 中的新链接，不请求候选帖子详情。
  List<ComicEpisodeLink> discoverDirectIncremental({
    required List<ComicEpisodeLink> currentLinks,
    required Set<String> knownTids,
  }) {
    final newLinks = <ComicEpisodeLink>[];
    // 倒序遍历：最新章节在列表末尾，优先发现新增
    for (var i = currentLinks.length - 1; i >= 0; i--) {
      final link = currentLinks[i];
      final tid = _urlParser.extractTid(link.url);
      if (tid == null) continue;
      if (knownTids.contains(tid)) {
        // 遇到已知 tid，前面的也一定已知，提前停止
        break;
      }
      newLinks.add(link);
    }
    return newLinks.reversed.toList(growable: false);
  }

  /// Recursive 增量：从 startTid 开始连续回溯，遇到已知 tid 停止。
  ///
  /// [startTid] 通常是搜索结果返回的最新章节 tid。
  /// [knownTids] 是本地已有章节的 tid 集合。
  /// 沿帖子内实际超链接（"上一话"等）回溯，遇到已知 tid 或达到
  /// maxRecursiveDepth 时终止。
  Future<List<ComicEpisodeLink>> discoverRecursiveIncremental({
    required String startTid,
    required Set<String> knownTids,
  }) async {
    final discovered = <ComicEpisodeLink>[];
    final visited = <String>{};
    var currentTid = startTid;
    var consecutiveFailures = 0;
    var depth = 0;

    while (depth < _maxRecursiveDepth &&
        consecutiveFailures < _maxConsecutiveFailures) {
      if (visited.contains(currentTid)) break;
      visited.add(currentTid);

      // 遇到已知 tid -> 之前的章节已在本地，更新完毕
      if (knownTids.contains(currentTid)) break;

      final result = await _recursiveRequestGovernor.schedule(
        () => _fetchThreadDetail(currentTid),
      );
      depth++;
      final detail = result.dataOrNull;
      if (detail == null) {
        consecutiveFailures++;
        break; // recursive 模式下单链失败即停
      }
      consecutiveFailures = 0;

      if (!_eligibilityPolicy.allows(fid: detail.fid, typeid: detail.typeid)) {
        break;
      }

      // 记录当前 tid 为新章节
      discovered.add(
        ComicEpisodeLink(
          url: _buildThreadUrl(currentTid),
          rawText: detail.subject,
          episodeTitle: detail.subject,
        ),
      );

      // 沿帖子内超链接找下一个跳转 tid
      final nextTid = _extractNextRecursiveTid(detail, visited);
      if (nextTid == null) break;
      currentTid = nextTid;
    }

    return discovered;
  }

  /// 从帖子详情中提取下一个递归候选 tid。
  ///
  /// 复用 [ComicEpisodeDiscoveryService._collectRecursiveTidCandidates] 的
  /// 逻辑模式：先从解析出的 episodeLinks 收集，再从 DOM fallback 收集。
  String? _extractNextRecursiveTid(
    ThreadDetailData detail,
    Set<String> visited,
  ) {
    final parsed = _opPostParser.parse(
      tid: detail.tid,
      fid: detail.fid,
      subject: detail.subject,
      posts: detail.posts,
    );

    // 从解析出的跳转链接中收集候选
    final candidates = <String>{};
    for (final link in parsed.episodeLinks) {
      final candidateTid = _urlParser.extractTid(link.url);
      if (candidateTid != null && candidateTid != detail.tid) {
        candidates.add(candidateTid);
      }
    }

    // DOM fallback：帖子正文中的 anchor 链接
    for (final post in detail.posts) {
      for (final candidateTid in _domExtractor.extractThreadTids(
        post.message,
      )) {
        if (candidateTid != detail.tid) {
          candidates.add(candidateTid);
        }
      }
    }

    // 返回第一个未访问的候选
    for (final candidate in candidates) {
      if (!visited.contains(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  String _buildThreadUrl(String tid) {
    return '${AppConfig.siteBaseUrl}/forum.php?mod=viewthread&tid=$tid';
  }
}
