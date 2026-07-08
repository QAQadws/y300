import 'package:y300/features/comic/data/services/comic_favorite_auto_refresh_coordinator.dart';
import 'package:y300/features/comic/domain/services/comic_duplicate_merge_service.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/favorites/domain/models/favorite_content_ingest.dart';
import 'package:y300/features/favorites/domain/services/library_post_ingest_task_runner.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

/// 默认任务执行器：把漫画自动刷新、重复合并、书架通知集中在此执行。
///
/// 阶段 3 的目标是“收藏同步主流程不再直接执行模块后处理”。本实现持有
/// 模块级服务，handler/sync service 只声明任务、读取 report。
///
/// - 单条 task 失败被吞下并记入 [LibraryPostIngestTaskReport.failures]，与
///   阶段 0/1 测试守护的“自动刷新失败仍标记详情已补全 / 重复合并失败保留
///   原 workId”补偿语义保持一致。
/// - `ComicAutoRefreshTask`/`ComicAutoRefreshBackfillTask` 在 coordinator
///   内已经发出 catalog/queued/skipped 三种刷新信号，runner 不重复发送，
///   留待阶段 4 的“漫画刷新结果应用器”收口。
/// - `ComicDuplicateMergeTask` 命中合并时把目标 `comicId` 写入
///   [LibraryPostIngestTaskReport.resolvedWorkId]，由收藏同步写回
///   `favorite_thread_cache.work_id`。
class DefaultLibraryPostIngestTaskRunner
    implements LibraryPostIngestTaskRunner {
  const DefaultLibraryPostIngestTaskRunner({
    ComicFavoriteAutoRefreshCoordinator? comicAutoRefreshCoordinator,
    ComicDuplicateMergeService? comicDuplicateMergeService,
    LibraryShelfRefreshBus? shelfRefreshBus,
  }) : _comicAutoRefreshCoordinator = comicAutoRefreshCoordinator,
       _comicDuplicateMergeService = comicDuplicateMergeService,
       _shelfRefreshBus = shelfRefreshBus;

  final ComicFavoriteAutoRefreshCoordinator? _comicAutoRefreshCoordinator;
  final ComicDuplicateMergeService? _comicDuplicateMergeService;
  final LibraryShelfRefreshBus? _shelfRefreshBus;

  @override
  bool canRun(LibraryPostIngestTask task) {
    if (task is ComicAutoRefreshTask || task is ComicAutoRefreshBackfillTask) {
      return _comicAutoRefreshCoordinator != null;
    }
    if (task is ComicDuplicateMergeTask || task is ComicDuplicateMergeAllTask) {
      return _comicDuplicateMergeService != null;
    }
    if (task is ShelfRefreshTask) {
      return _shelfRefreshBus != null;
    }
    return false;
  }

  @override
  Future<LibraryPostIngestTaskReport> runAll(
    List<LibraryPostIngestTask> tasks, {
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    if (tasks.isEmpty) {
      return LibraryPostIngestTaskReport.empty;
    }
    final completed = <LibraryPostIngestTask>[];
    final failures = <LibraryPostIngestTaskFailure>[];
    String? resolvedWorkId;

    for (final task in tasks) {
      try {
        if (task is ComicAutoRefreshTask) {
          await _runComicAutoRefresh(task, executionContext: executionContext);
        } else if (task is ComicAutoRefreshBackfillTask) {
          await _runComicAutoRefreshBackfill(
            task,
            executionContext: executionContext,
          );
        } else if (task is ComicDuplicateMergeTask) {
          final merged = await _runComicDuplicateMerge(task);
          // 只有真正合并发生时才覆盖 workId；未变化或失败保留原 id。
          resolvedWorkId = merged ?? resolvedWorkId;
        } else if (task is ComicDuplicateMergeAllTask) {
          await _runComicDuplicateMergeAll();
        } else if (task is ShelfRefreshTask) {
          _runShelfRefresh(task);
        } else {
          // 未识别任务类型不应静默忽略，但也不该让收藏详情回退到未补全状态。
          // 记入 failures 让上层观测到。
          failures.add(
            LibraryPostIngestTaskFailure(
              task: task,
              error: StateError(
                'Unsupported LibraryPostIngestTask: ${task.runtimeType}',
              ),
            ),
          );
          continue;
        }
        completed.add(task);
      } catch (error) {
        failures.add(LibraryPostIngestTaskFailure(task: task, error: error));
      }
    }

    return LibraryPostIngestTaskReport(
      completed: List<LibraryPostIngestTask>.unmodifiable(completed),
      failures: List<LibraryPostIngestTaskFailure>.unmodifiable(failures),
      resolvedWorkId: resolvedWorkId,
    );
  }

  Future<void> _runComicAutoRefresh(
    ComicAutoRefreshTask task, {
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    final coordinator = _comicAutoRefreshCoordinator;
    if (coordinator == null) {
      return;
    }
    await coordinator.refreshAfterFavoriteIngest(
      comicId: task.comicId,
      detail: task.detail,
      favoriteTitle: task.favoriteTitle,
      sourceFid: task.sourceFid ?? task.detail.fid,
      sourceTypeId: task.sourceTypeId ?? task.detail.typeid,
      sourceTagName: task.sourceTagName,
      forceSearchOnCatalogMiss: task.forceSearchOnCatalogMiss,
      executionContext: executionContext,
      preloadedRootDetail: task.detail,
    );
  }

  Future<void> _runComicAutoRefreshBackfill(
    ComicAutoRefreshBackfillTask task, {
    FavoriteSyncExecutionContext? executionContext,
  }) async {
    final coordinator = _comicAutoRefreshCoordinator;
    if (coordinator == null) {
      return;
    }
    await coordinator.refreshFavoriteComic(
      comicId: task.comicId,
      sourceTid: task.sourceTid,
      favoriteTitle: task.favoriteTitle,
      sourceTitle: task.sourceTitle,
      sourceFid: task.sourceFid,
      sourceTypeId: task.sourceTypeId,
      sourceTagName: task.sourceTagName,
      executionContext: executionContext,
    );
  }

  /// 命中合并时返回合并目标 `comicId`；未命中或服务未注入返回 null。
  Future<String?> _runComicDuplicateMerge(ComicDuplicateMergeTask task) async {
    final service = _comicDuplicateMergeService;
    if (service == null) {
      return null;
    }
    final result = await service.mergeComic(comicId: task.comicId);
    if (!result.changed) {
      return null;
    }
    final target = result.targetComicId.trim();
    _shelfRefreshBus?.notify(
      modules: const <LibraryModuleKey>{
        LibraryModuleKey.comic,
        LibraryModuleKey.favorite,
      },
      reason: 'favorite_comic_duplicate_merge_completed',
      source: LibraryMutationSource.duplicateMerge,
      workId: target.isEmpty ? null : target,
      payload: <String, Object?>{
        'sourceComicId': task.comicId,
        'targetComicId': target,
      },
    );
    return target.isEmpty ? null : target;
  }

  Future<void> _runComicDuplicateMergeAll() async {
    final service = _comicDuplicateMergeService;
    if (service == null) {
      return;
    }
    final summary = await service.mergeAllDuplicates();
    if (summary.changed) {
      _shelfRefreshBus?.notify(
        modules: const <LibraryModuleKey>{
          LibraryModuleKey.comic,
          LibraryModuleKey.favorite,
        },
        reason: 'favorite_first_sync_comic_duplicate_merge_completed',
        source: LibraryMutationSource.duplicateMerge,
        payload: <String, Object?>{
          'removedComicCount': summary.removedComicCount,
        },
      );
    }
  }

  void _runShelfRefresh(ShelfRefreshTask task) {
    _shelfRefreshBus?.notify(
      modules: task.modules,
      reason: task.reason,
      source: task.source,
      workId: task.workId,
      tid: task.tid,
      payload: task.payload,
    );
  }
}
