import 'package:y300/features/favorites/domain/favorite_content_ingest.dart';

/// 任务执行结果。
///
/// 保留逐 task 的成功/失败列表，便于后续测试与诊断。`resolvedWorkId` 用于
/// 漫画重复合并：命中合并时返回新的 `comicId`，由收藏同步写回
/// `favorite_thread_cache.work_id`，未命中或失败时为空。
class LibraryPostIngestTaskReport {
  const LibraryPostIngestTaskReport({
    this.completed = const <LibraryPostIngestTask>[],
    this.failures = const <LibraryPostIngestTaskFailure>[],
    this.resolvedWorkId,
  });

  static const empty = LibraryPostIngestTaskReport();

  final List<LibraryPostIngestTask> completed;
  final List<LibraryPostIngestTaskFailure> failures;

  /// 重复合并任务命中时给出的合并目标 `comicId`，未命中或失败时为 null。
  final String? resolvedWorkId;
}

class LibraryPostIngestTaskFailure {
  const LibraryPostIngestTaskFailure({
    required this.task,
    required this.error,
  });

  final LibraryPostIngestTask task;
  final Object error;
}

/// 模块后处理任务执行器。
///
/// 内容处理器只负责声明任务（[FavoriteContentIngestResult.postTasks]）；
/// 自动刷新、重复合并、书架通知统一在 runner 内执行，并在内部捕获非关键
/// 失败，避免污染收藏详情补全主流程。
abstract class LibraryPostIngestTaskRunner {
  Future<LibraryPostIngestTaskReport> runAll(
    List<LibraryPostIngestTask> tasks,
  );
}
