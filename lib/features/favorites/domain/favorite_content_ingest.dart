import 'package:y300/features/favorites/domain/favorite_detail_context.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

/// 阶段 3：模块后处理任务基类。
///
/// 内容处理器只负责把帖子详情入库到对应模块，并**声明**入库后还需要哪些
/// 后处理工作（自动刷新、重复合并、书架通知等）。具体执行交由
/// [LibraryPostIngestTaskRunner]，避免 handler 与刷新策略、合并 SQL、
/// 刷新事件总线长期耦合在一起。
abstract class LibraryPostIngestTask {
  const LibraryPostIngestTask();
}

/// 漫画收藏入库后的 catalog 引导刷新。
///
/// 现阶段委托给 `ComicFavoriteAutoRefreshCoordinator.refreshAfterFavoriteIngest`，
/// 保持原有 catalog-only / 入队 / 标签门控语义，只是把调用点从 handler 移到
/// runner，方便阶段 4 把刷新结果应用收口为单一 service。
class ComicAutoRefreshTask extends LibraryPostIngestTask {
  const ComicAutoRefreshTask({
    required this.comicId,
    required this.detail,
    required this.favoriteTitle,
    this.sourceTagName,
    this.forceSearchOnCatalogMiss = false,
  });

  final String comicId;
  final ThreadDetailData detail;
  final String favoriteTitle;
  final String? sourceTagName;
  final bool forceSearchOnCatalogMiss;
}

/// 历史漫画自动刷新回填任务。
///
/// 后台维护扫描已入库漫画时只有缓存字段（无 detail），用单独 task 类型避免
/// `ComicAutoRefreshTask` 字段半空。委托给
/// `ComicFavoriteAutoRefreshCoordinator.refreshFavoriteComic`。
class ComicAutoRefreshBackfillTask extends LibraryPostIngestTask {
  const ComicAutoRefreshBackfillTask({
    required this.comicId,
    required this.sourceTid,
    required this.favoriteTitle,
    this.sourceTitle,
    this.sourceTagName,
  });

  final String comicId;
  final String sourceTid;
  final String favoriteTitle;
  final String? sourceTitle;
  final String? sourceTagName;
}

/// 单条漫画的重复合并。
///
/// 命中合并时 runner 会通过 [LibraryPostIngestTaskReport.resolvedWorkId]
/// 把合并目标 id 回传给收藏同步，由后者更新 `favorite_thread_cache.work_id`。
class ComicDuplicateMergeTask extends LibraryPostIngestTask {
  const ComicDuplicateMergeTask({required this.comicId});

  final String comicId;
}

/// 首次全量同步后的全量重复漫画合并。
class ComicDuplicateMergeAllTask extends LibraryPostIngestTask {
  const ComicDuplicateMergeAllTask();
}

/// 通知一组书架模块刷新。
class ShelfRefreshTask extends LibraryPostIngestTask {
  const ShelfRefreshTask({
    required this.modules,
    required this.reason,
  });

  final Set<LibraryModuleKey> modules;
  final String reason;
}

class FavoriteIngestOptions {
  const FavoriteIngestOptions({
    this.mergeIngestedComic = true,
    this.forceComicSearchOnCatalogMiss = false,
  });

  final bool mergeIngestedComic;
  final bool forceComicSearchOnCatalogMiss;
}

class FavoriteContentIngestRequest {
  const FavoriteContentIngestRequest({
    required this.context,
    required this.options,
  });

  final FavoriteDetailContext context;
  final FavoriteIngestOptions options;
}

class FavoriteContentIngestResult {
  const FavoriteContentIngestResult({
    required this.kind,
    required this.workId,
    this.postTasks = const <LibraryPostIngestTask>[],
  });

  final ThreadContentKind kind;
  final String workId;
  final List<LibraryPostIngestTask> postTasks;
}

abstract class FavoriteContentIngestHandler {
  ThreadContentKind get kind;

  Future<FavoriteContentIngestResult> ingest(
    FavoriteContentIngestRequest request,
  );

  Future<void> removeFromShelf({required String workId});
}

abstract class FavoriteContentIngestRegistry {
  FavoriteContentIngestHandler handlerFor(ThreadContentKind kind);
}
