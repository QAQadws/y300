import 'package:y300/features/comic/domain/models/comic_models.dart';

/// 当一篇帖子里既没解析出 catalog 章节链接，也没识别出任何独立章节结构时，
/// 它就被视为「单帖漫画」——整本作品就装在这一个帖子里。
/// 这种情形下需要给唯一一话起一个稳定可读的标题。
///
/// 命名策略集中在这里，目的有三：
/// 1. 把"取标题"这一段领域逻辑从仓储/存储层剥离，避免标题策略漂回 SQL 边界。
/// 2. 让上游的 [ComicSubjectMetadata]（已经经过标题分析器）成为一等公民，
///    不再让落地层重新解析或硬编码占位符。
/// 3. 通过抽象接口允许测试替身或不同发行版替换命名口径，而不动其它模块。
abstract class ComicSingleThreadEpisodeNamer {
  const ComicSingleThreadEpisodeNamer();

  /// 计算单帖漫画唯一一话的展示标题。
  ///
  /// 调用方应优先传入 [metadata]——通常来自
  /// `ParsedComicPost.subjectMetadata`，它内部已经走过 `ComicTitleAnalyzer`，
  /// 拿到了规范化的书名与章节标签。[fallbackComicTitle] 兜底，传入未做任何
  /// 处理的原始 thread subject 即可。
  String resolve({
    ComicSubjectMetadata? metadata,
    required String fallbackComicTitle,
  });
}

/// 默认命名策略：
///
/// 1. 若标题分析器抓到了章节标签（如 `第3话` / `Vol.2` / `番外`），用它做
///    话名——单帖漫画里这通常意味着"该帖就是第 N 话"，对读者最直观。
/// 2. 否则退化为规范化后的书名（如 `测试漫画`）——单帖里"整本就是一话"
///    时，话名就等于作品名。
/// 3. 都拿不到时再退到调用方提供的原始标题，保证总有一个非空字符串。
/// 4. 真的全空（罕见，几乎只出现在测试桩或脏数据）时落回 `首楼` 这个
///    历史占位符，作为最末端的安全网，避免把 NULL 推到 UI 层。
class DefaultComicSingleThreadEpisodeNamer implements ComicSingleThreadEpisodeNamer {
  const DefaultComicSingleThreadEpisodeNamer();

  static const String _legacyFallbackTitle = '首楼';

  @override
  String resolve({
    ComicSubjectMetadata? metadata,
    required String fallbackComicTitle,
  }) {
    final episodeLabel = _nonEmpty(metadata?.episodeLabel);
    if (episodeLabel != null) {
      return episodeLabel;
    }

    final normalizedTitle = _nonEmpty(metadata?.normalizedTitle);
    if (normalizedTitle != null) {
      return normalizedTitle;
    }

    final rawTitle = _nonEmpty(fallbackComicTitle);
    if (rawTitle != null) {
      return rawTitle;
    }

    return _legacyFallbackTitle;
  }

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
