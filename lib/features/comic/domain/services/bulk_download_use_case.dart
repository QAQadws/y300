// 整部下载用例只负责解析选中漫画的章节并批量入队。下载执行、限速、
// 进度与失败恢复均由 ComicDownloadQueue 统一负责。

/// 整部下载的结构化结果。
class BulkDownloadResult {
  const BulkDownloadResult({
    required this.requestedCount,
    required this.enqueuedCount,
    required this.deduplicatedCount,
    required this.skippedDownloadedCount,
  });

  final int requestedCount;
  final int enqueuedCount;
  final int deduplicatedCount;
  final int skippedDownloadedCount;
}

/// 批量整部下载用例（仅漫画）。
abstract class BulkDownloadUseCase {
  Future<BulkDownloadResult> downloadComics(Set<String> comicIds);
}
