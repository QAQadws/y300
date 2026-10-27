import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/models/favorite_content_ingest.dart';
import 'package:y300/features/favorites/domain/services/favorite_sync_request_governor.dart';
import 'package:y300/features/favorites/domain/services/library_post_ingest_task_runner.dart';

/// Runs historical backfill and first-sync cleanup using the shared task runner.
class FavoriteSyncMaintenance {
  const FavoriteSyncMaintenance({
    required LocalFavoriteRepository localRepository,
    required LibraryPostIngestTaskRunner postIngestTaskRunner,
    required int batchLimit,
  }) : _localRepository = localRepository,
       _postIngestTaskRunner = postIngestTaskRunner,
       _batchLimit = batchLimit;

  final LocalFavoriteRepository _localRepository;
  final LibraryPostIngestTaskRunner _postIngestTaskRunner;
  final int _batchLimit;

  Future<void> runBackgroundMaintenance({
    required FavoriteSyncExecutionContext context,
    Future<void> Function(Future<void> Function())? runStep,
    bool Function()? shouldContinue,
    bool Function(String)? wasRefreshed,
  }) async {
    try {
      await _backfillExistingComicAutoRefreshIfNeeded(
        context: context,
        runStep: runStep ?? (action) => action(),
        shouldContinue: shouldContinue ?? () => true,
        wasRefreshed: wasRefreshed ?? (_) => false,
      );
    } catch (_) {
      // 后台维护不改变收藏同步主状态；失败时保留全局 marker 为空，
      // 下一次进入收藏页或手动同步仍可继续尝试。
    }
  }

  Future<void> mergeAllComicDuplicatesAfterFirstSync() async {
    // 首次全量同步收尾的全量去重交给 runner，与单条入库后的合并共用同一执行器，
    // 失败语义统一“不阻断收藏同步主结果”。
    await _postIngestTaskRunner.runAll(const <LibraryPostIngestTask>[
      ComicDuplicateMergeAllTask(),
    ]);
  }

  Future<void> _backfillExistingComicAutoRefreshIfNeeded({
    required FavoriteSyncExecutionContext context,
    required Future<void> Function(Future<void> Function()) runStep,
    required bool Function() shouldContinue,
    required bool Function(String) wasRefreshed,
  }) async {
    if (!shouldContinue()) return;
    if (await _localRepository.hasCompletedComicAutoRefreshBackfill()) {
      return;
    }
    const capabilityProbe = ComicAutoRefreshBackfillTask(
      comicId: '_',
      sourceTid: '_',
      favoriteTitle: '_',
    );
    if (!_postIngestTaskRunner.canRun(capabilityProbe)) {
      return;
    }

    final checkedTids = <String>{};
    final failedTids = <String>[];
    var checkedCount = 0;
    var sawAnyCandidate = false;

    while (true) {
      if (!shouldContinue()) return;
      final records = await _localRepository
          .getComicAutoRefreshBackfillCandidates(
            limit: _batchLimit,
            excludedTids: checkedTids,
          );
      if (records.isEmpty) {
        break;
      }

      final checkedBefore = checkedTids.length;
      for (final record in records) {
        if (!shouldContinue()) return;
        checkedTids.add(record.tid);
        if (wasRefreshed(record.tid)) continue;
        await runStep(() async {
          if (!shouldContinue()) return;
          final current = await _localRepository.getActiveThreadByTid(
            record.tid,
          );
          if (!shouldContinue() ||
              current == null ||
              current.contentKind != record.contentKind) {
            return;
          }
          // A foreground or automatic detail may have refreshed this comic
          // while its historical backfill step waited in the queue.
          if (wasRefreshed(current.tid)) return;
          sawAnyCandidate = true;
          final comicId = current.workId?.trim();
          if (comicId == null || comicId.isEmpty) {
            failedTids.add(record.tid);
            return;
          }
          final report = await _postIngestTaskRunner.runAll(
            <LibraryPostIngestTask>[
              ComicAutoRefreshBackfillTask(
                comicId: comicId,
                sourceTid: current.tid,
                favoriteTitle: current.title,
                sourceTitle: current.title,
                sourceFid: current.sourceFid,
                sourceTypeId: current.sourceTypeid,
                sourceTagName: current.sourceTagName,
              ),
            ],
            executionContext: context,
          );
          if (report.failures.isNotEmpty) {
            failedTids.add(record.tid);
          } else {
            checkedCount++;
          }
        });
      }

      // Defensive break: if a repository implementation returns only already
      // excluded records, avoid spinning forever in background maintenance.
      if (checkedTids.length == checkedBefore) {
        break;
      }
    }

    if (!sawAnyCandidate) {
      return;
    }

    await runStep(() async {
      if (!shouldContinue()) return;
      await _localRepository.markComicAutoRefreshBackfillCompleted(
        checkedCount: checkedCount,
        message: failedTids.isEmpty
            ? null
            : '部分历史漫画自动刷新检查失败：${failedTids.join(',')}',
      );
    });
  }
}
