import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/services/favorite_detail_context_loader.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/models/favorite_content_ingest.dart';
import 'package:y300/features/favorites/domain/models/favorite_detail_context.dart';
import 'package:y300/features/favorites/domain/services/favorite_sync_request_governor.dart';
import 'package:y300/features/favorites/domain/services/library_post_ingest_task_runner.dart';

typedef FavoriteDetailFillProgress =
    void Function({
      required String subject,
      required int current,
      required int total,
    });

/// Completes cached favorites through the existing loader, ingest handlers and runner.
class FavoriteDetailFiller {
  const FavoriteDetailFiller({
    required LocalFavoriteRepository localRepository,
    required FavoriteDetailContextLoader detailContextLoader,
    required FavoriteContentIngestRegistry contentIngestRegistry,
    required LibraryPostIngestTaskRunner postIngestTaskRunner,
    required int batchLimit,
  }) : _localRepository = localRepository,
       _detailContextLoader = detailContextLoader,
       _contentIngestRegistry = contentIngestRegistry,
       _postIngestTaskRunner = postIngestTaskRunner,
       _batchLimit = batchLimit;

  final LocalFavoriteRepository _localRepository;
  final FavoriteDetailContextLoader _detailContextLoader;
  final FavoriteContentIngestRegistry _contentIngestRegistry;
  final LibraryPostIngestTaskRunner _postIngestTaskRunner;
  final int _batchLimit;

  Future<DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>?>
  loadTargetDetailOrNull(
    String tid, {
    required FavoriteSyncExecutionContext context,
  }) async {
    final result = await _detailContextLoader.loadDetail(
      tid,
      executionContext: context,
    );
    return result
            is DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>
        ? result
        : null;
  }

  Future<int> upsertRecentlyFavoritedThreadFromDetail({
    required String tid,
    required ThreadDetailData detail,
  }) {
    final normalizedTid = tid.trim();
    if (normalizedTid.isEmpty) {
      return Future<int>.value(0);
    }
    final title = detail.subject.trim();
    if (title.isEmpty) {
      return Future<int>.value(0);
    }
    return _localRepository.upsertRemoteThreads(<FavoriteThreadCacheUpsert>[
      FavoriteThreadCacheUpsert(
        tid: normalizedTid,
        title: title,
        authorName: detail.author.trim().isEmpty ? null : detail.author.trim(),
        replyCount: detail.replies,
        remoteOrder: 0,
      ),
    ]);
  }

  Future<FavoriteDetailFillResult> fillMissingDetails({
    required FavoriteSyncExecutionContext context,
    required FavoriteDetailFillProgress onProgress,
    bool mergeIngestedComics = true,
    Set<String> forceComicSearchOnCatalogMissTids = const <String>{},
  }) async {
    final totalMissingDetails = await _localRepository
        .countMissingDetailRecords();
    final failedTids = <String>[];
    final failedTidSet = <String>{};
    final errors = <String, String>{};
    var loadedCount = 0;
    var processedCount = 0;

    while (true) {
      final records = await _localRepository.getMissingDetailRecords(
        limit: _batchLimit,
        excludedTids: failedTidSet,
      );
      if (records.isEmpty) {
        break;
      }

      var madeProgress = false;
      final failedCountBefore = failedTidSet.length;
      for (final record in records) {
        onProgress(
          subject: record.title,
          current: processedCount + 1,
          total: totalMissingDetails,
        );
        try {
          final loaded = await fillOneDetail(
            record,
            context: context,
            mergeIngestedComics: mergeIngestedComics,
            forceComicSearchOnCatalogMiss: forceComicSearchOnCatalogMissTids
                .contains(record.tid),
          );
          if (loaded) {
            loadedCount++;
            madeProgress = true;
          } else {
            failedTidSet.add(record.tid);
            failedTids.add(record.tid);
            errors[record.tid] = '加载帖子详情失败';
          }
        } catch (error) {
          failedTidSet.add(record.tid);
          failedTids.add(record.tid);
          errors[record.tid] = '$error';
        }
        processedCount++;
      }

      // 如果一批全部失败，失败 tid 会被本轮同步临时排除，继续处理后续收藏；
      // 只有既没有成功也没有新增失败时才退出，避免仓储实现异常导致死循环。
      if (!madeProgress && failedTidSet.length == failedCountBefore) {
        break;
      }
    }

    return FavoriteDetailFillResult(
      loadedCount: loadedCount,
      failedTids: failedTids,
      errors: errors,
    );
  }

  Future<bool> fillOneDetail(
    FavoriteThreadCacheRecord record, {
    required FavoriteSyncExecutionContext context,
    required bool mergeIngestedComics,
    bool forceComicSearchOnCatalogMiss = false,
    DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>?
    preloadedDetail,
  }) async {
    final result = await _detailContextLoader.load(
      record,
      preloadedDetail: preloadedDetail,
      executionContext: context,
    );
    return result.when(
      success: (resolution, _, _) async {
        if (resolution is InvalidFavoriteDetail) {
          await _localRepository.markThreadDetailInvalid(
            tid: resolution.record.tid,
          );
          return true;
        }

        final detailContext = (resolution as ResolvedFavoriteDetail).context;
        final ingestHandler = _contentIngestRegistry.handlerFor(
          detailContext.kind,
        );
        final ingestResult = await ingestHandler.ingest(
          FavoriteContentIngestRequest(
            context: detailContext,
            options: FavoriteIngestOptions(
              mergeIngestedComic: mergeIngestedComics,
              forceComicSearchOnCatalogMiss: forceComicSearchOnCatalogMiss,
              executionContext: context,
            ),
          ),
        );
        // 阶段 3：handler 只声明后处理任务（自动刷新、重复合并、书架通知），
        // 由 runner 集中执行并捕获非关键失败。命中重复合并时 runner 会回传
        // 合并目标 workId，写回收藏缓存的 work_id 字段。
        final taskReport = await _postIngestTaskRunner.runAll(
          ingestResult.postTasks,
          executionContext: context,
        );
        final finalWorkId = taskReport.resolvedWorkId ?? ingestResult.workId;

        await _localRepository.updateThreadDetailMeta(
          tid: detailContext.record.tid,
          fid: detailContext.detail.fid,
          typeid: detailContext.detail.typeid,
          tagName: detailContext.tagName,
          contentKind: detailContext.kind,
          workId: finalWorkId,
        );
        return true;
      },
      failure: (_) async => false,
    );
  }
}

class FavoriteDetailFillResult {
  const FavoriteDetailFillResult({
    required this.loadedCount,
    required this.failedTids,
    required this.errors,
  });

  final int loadedCount;
  final List<String> failedTids;
  final Map<String, String> errors;
}
