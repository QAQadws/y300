import 'package:y300/features/novel/domain/models/novel_parsing_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

class NovelEpisodeDraft {
  const NovelEpisodeDraft({
    required this.episodeId,
    required this.novelId,
    required this.sourceTid,
    required this.sourcePid,
    required this.sourcePage,
    required this.episodeTitle,
    required this.orderIndex,
    required this.datelineText,
    required this.rawHtml,
    required this.plainText,
    required this.paragraphs,
    this.imageUrls = const <String>[],
  });

  final String episodeId;
  final String novelId;
  final String sourceTid;
  final String sourcePid;
  final int sourcePage;
  final String episodeTitle;
  final int orderIndex;
  final String datelineText;
  final String rawHtml;
  final String plainText;
  final List<String> paragraphs;
  final List<String> imageUrls;
}

class NovelRefreshPlan {
  const NovelRefreshPlan({
    required this.tid,
    required this.subject,
    required this.author,
    required this.episodes,
    this.intro,
    this.coverImageUrl,
    this.inlineImageUrls = const <String>[],
    this.debugInfo,
  });

  final String tid;
  final String subject;
  final String author;
  final List<NovelEpisodeDraft> episodes;
  final String? intro;
  final String? coverImageUrl;
  final List<String> inlineImageUrls;
  final NovelParsingDebugInfo? debugInfo;
}

/// Legacy refresh mode retained for historical repository tests only.
enum NovelEpisodeRefreshMode {
  /// 从第 1 页开始全量爬取并重建章节、封面、简介。
  ///
  /// 适用场景：收藏首次同步、加入书架、Shelf 添加、阅读器自愈。
  full,

  /// 增量刷新：从已解析过的最大 source_page 开始（包含该页本身重新拉一次）
  /// 往后继续抓取，标题仍走 sanitizer 重写，但封面/简介/作者/目录全部不动，
  /// 旧章节也不删。
  ///
  /// 适用场景：详情页下拉刷新与「更新」菜单。
  ///
  /// 仓库内部会在以下情况自动降级为 [full]：
  /// 1. 本地零章节
  /// 2. 已知最大 source_page ≤ 1（增量与全量等价）
  /// 3. catalog 模式（page=1 上有 ≥ 2 个章节，目录对应章节散落多页）
  incremental,
}

/// 章节发现服务的运行时开关。
///
/// 通过显式参数代替散落的 if 分支，避免在 service 内部硬编码各种刷新模式。
class NovelDiscoveryOptions {
  const NovelDiscoveryOptions({
    this.orderIndexOffset = 0,
    this.skipCatalogExtraction = false,
    this.skipFirstChapterMetadata = false,
  });

  /// 新章节起始 orderIndex（含）。
  ///
  /// 同时投影到 [NovelParsingContext.currentOrderIndex] —— 让那些依赖
  /// `currentOrderIndex == 0` 自我门控的规则（CoverImageRule /
  /// IntroBeforeFirstChapterRule）在增量刷新时自然失效。
  final int orderIndexOffset;

  /// 跳过同帖目录抽取。
  ///
  /// catalog 只出现在首页前 10 楼，增量刷新从更后的页开始时跑 catalog 既无效
  /// 又会浪费 anchor 抽取调用。
  final bool skipCatalogExtraction;

  /// 进一步显式压制 cover/intro 元数据 —— 防御性兜底。
  ///
  /// rule 已经被 currentOrderIndex != 0 兜住，但 plan builder 也不暴露这两个
  /// 字段时，调用方可以更安心地直接读 plan 字段。
  final bool skipFirstChapterMetadata;

  static const NovelDiscoveryOptions defaults = NovelDiscoveryOptions();
}

abstract interface class NovelThreadGateway {
  Future<ThreadDetailData> loadAuthorPostsPage({
    required String tid,
    required String authorId,
    required int page,
    int postsPerPage = 200,
  });
}

/// Test-only compatibility port for the pre-hydration repository flow.
///
/// New synchronization services must depend on [NovelThreadGateway], whose
/// contract cannot issue an unfiltered chapter request.
abstract interface class LegacyNovelThreadGateway {
  Future<ThreadDetailData> getThreadDetail({
    required String tid,
    required int page,
  });
}

abstract interface class NovelSourceMetadataRecoveryGateway {
  Future<ThreadDetailData> loadFirstPage({required String tid});
}
