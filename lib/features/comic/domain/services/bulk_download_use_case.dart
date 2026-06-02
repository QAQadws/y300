// 阶段 0 契约冻结（书架多选与取消收藏方案）。
//
// 整部下载用例：把「下载选中漫画的所有章节」收口为一个领域用例，
// 而不是在 UI 里裸遍历章节循环调用 ComicDownloadService。
//
// 实现落在阶段 4：内部遍历每部漫画的章节调用现有 ComicDownloadService，
// 限流 + 进度 + 失败收集，进度复用现有 LibraryTaskProgressHub / 队列基础设施。
// 小说当前无下载能力，故本用例只服务漫画。

/// 整部下载的结构化结果。
class BulkDownloadResult {
  const BulkDownloadResult({
    required this.requestedComicIds,
    required this.completedComicIds,
    required this.failedComicIds,
    required this.downloadedEpisodeCount,
  });

  final List<String> requestedComicIds;
  final List<String> completedComicIds;

  /// 至少有一章下载失败的漫画。
  final List<String> failedComicIds;
  final int downloadedEpisodeCount;

  bool get hasFailure => failedComicIds.isNotEmpty;
}

/// 批量整部下载用例（仅漫画）。
abstract class BulkDownloadUseCase {
  Future<BulkDownloadResult> downloadComics(Set<String> comicIds);
}
