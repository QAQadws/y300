import 'package:flutter/foundation.dart';
import 'package:y300/core/data_source/data_read_contract.dart';
import 'package:y300/features/cache/domain/services/cache_load_policy.dart';
import 'package:y300/features/favorites/data/services/favorite_detail_context_loader.dart';
import 'package:y300/features/favorites/data/services/favorite_first_sync_request_governor.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/models/favorite_content_ingest.dart';
import 'package:y300/features/favorites/domain/models/favorite_detail_context.dart';
import 'package:y300/features/favorites/domain/models/favorite_directory_models.dart';
import 'package:y300/features/favorites/domain/repositories/favorite_directory_repositories.dart';
import 'package:y300/features/favorites/domain/services/library_post_ingest_task_runner.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/thread/domain/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/repositories/thread_repository.dart';

typedef _FavoriteDirectoryRead =
    DataReadSuccess<
      FavoriteThreadDirectoryData,
      FavoriteThreadDirectoryReadCapabilities
    >;

enum FavoriteSyncProgressPhase {
  idle,
  fetchingList,
  savingList,
  loadingDetails,
  finishing,
  completed,
  failed,
}

class FavoriteSyncProgress {
  const FavoriteSyncProgress({
    required this.phase,
    this.subject,
    this.current = 0,
    this.total,
  });

  final FavoriteSyncProgressPhase phase;

  /// Raw work title used only as a presentation placeholder.
  final String? subject;
  final int current;
  final int? total;

  bool get isActive {
    return switch (phase) {
      FavoriteSyncProgressPhase.fetchingList ||
      FavoriteSyncProgressPhase.savingList ||
      FavoriteSyncProgressPhase.loadingDetails ||
      FavoriteSyncProgressPhase.finishing => true,
      FavoriteSyncProgressPhase.idle ||
      FavoriteSyncProgressPhase.completed ||
      FavoriteSyncProgressPhase.failed => false,
    };
  }

  double? get fraction {
    final resolvedTotal = total;
    if (resolvedTotal == null || resolvedTotal <= 0) {
      return null;
    }
    return (current / resolvedTotal).clamp(0.0, 1.0).toDouble();
  }

  static const idle = FavoriteSyncProgress(
    phase: FavoriteSyncProgressPhase.idle,
  );
}

abstract class FavoriteSyncService {
  Future<FavoriteSyncResult> sync();

  Future<FavoriteSyncResult> syncRecentlyAddedThread({required String tid});

  Future<void> runBackgroundMaintenance();

  ValueListenable<FavoriteSyncProgress> get progress;
}

class NetworkFavoriteSyncService implements FavoriteSyncService {
  NetworkFavoriteSyncService({
    required FavoriteThreadDirectoryRepository remoteRepository,
    required LocalFavoriteRepository localRepository,
    required FavoriteDetailContextLoader detailContextLoader,
    required FavoriteContentIngestRegistry contentIngestRegistry,
    required LibraryPostIngestTaskRunner postIngestTaskRunner,
    LibraryShelfRefreshBus? shelfRefreshBus,
    DownloadStorageService? downloadStorageService,
    int detailBatchLimit = 20,
    FavoriteFirstSyncRequestGovernor Function()? governorFactory,
  }) : _remoteRepository = remoteRepository,
       _localRepository = localRepository,
       _detailContextLoader = detailContextLoader,
       _contentIngestRegistry = contentIngestRegistry,
       _postIngestTaskRunner = postIngestTaskRunner,
       _shelfRefreshBus = shelfRefreshBus,
       _downloadStorageService = downloadStorageService,
       _detailBatchLimit = detailBatchLimit,
       _governorFactory =
           governorFactory ?? (() => DefaultFavoriteFirstSyncRequestGovernor());

  final FavoriteThreadDirectoryRepository _remoteRepository;
  final LocalFavoriteRepository _localRepository;
  final FavoriteDetailContextLoader _detailContextLoader;
  final FavoriteContentIngestRegistry _contentIngestRegistry;
  final LibraryPostIngestTaskRunner _postIngestTaskRunner;
  final LibraryShelfRefreshBus? _shelfRefreshBus;
  final DownloadStorageService? _downloadStorageService;
  final int _detailBatchLimit;
  final FavoriteFirstSyncRequestGovernor Function() _governorFactory;
  final ValueNotifier<FavoriteSyncProgress> _progress =
      ValueNotifier<FavoriteSyncProgress>(FavoriteSyncProgress.idle);
  Future<FavoriteSyncResult>? _inflightSync;

  @override
  ValueListenable<FavoriteSyncProgress> get progress => _progress;

  @override
  Future<void> runBackgroundMaintenance() async {
    await runBackgroundMaintenanceWithContext(
      context: FavoriteSyncExecutionContext.automaticResume(
        governor: _governorFactory(),
      ),
    );
  }

  @override
  Future<FavoriteSyncResult> sync() async {
    final existing = _inflightSync;
    if (existing != null) {
      return existing;
    }
    late final Future<FavoriteSyncResult> future;
    future =
        _runSync(() async {
          final snapshot = await _localRepository.getSyncSnapshot();
          final context = snapshot == null
              ? FavoriteSyncExecutionContext.bootstrapInitial(
                  governor: _governorFactory(),
                )
              : FavoriteSyncExecutionContext.automaticResume(
                  governor: _governorFactory(),
                );
          return _syncInternal(context: context);
        }).whenComplete(() {
          if (identical(_inflightSync, future)) {
            _inflightSync = null;
          }
        });
    _inflightSync = future;
    return future;
  }

  @override
  Future<FavoriteSyncResult> syncRecentlyAddedThread({
    required String tid,
  }) async {
    final normalizedTid = tid.trim();
    if (normalizedTid.isEmpty) {
      throw StateError('收藏帖子 tid 不能为空');
    }
    return _runSync(() async {
      final snapshot = await _localRepository.getSyncSnapshot();
      final context = FavoriteSyncExecutionContext.manualRecentAdd(
        governor: _governorFactory(),
      );
      if (snapshot == null) {
        // No baseline exists yet, so keep correctness by doing the regular
        // first sync while still forcing the just-favorited comic through the
        // search queue if catalog discovery misses.
        return _syncInternal(
          context: context,
          forceComicSearchOnCatalogMissTids: <String>{normalizedTid},
        );
      }
      return _syncRecentlyAddedThreadInternal(normalizedTid, context: context);
    });
  }

  Future<FavoriteSyncResult> _runSync(
    Future<FavoriteSyncResult> Function() body,
  ) async {
    try {
      final result = await body();
      _emitProgress(
        const FavoriteSyncProgress(phase: FavoriteSyncProgressPhase.completed),
      );
      return result;
    } on _FavoriteSyncFailure catch (error) {
      _emitProgress(
        FavoriteSyncProgress(phase: FavoriteSyncProgressPhase.failed),
      );
      await _localRepository.markSyncFailure(error.message);
      throw StateError(error.message);
    } catch (error) {
      _emitProgress(
        FavoriteSyncProgress(phase: FavoriteSyncProgressPhase.failed),
      );
      await _localRepository.markSyncFailure('$error');
      rethrow;
    }
  }

  Future<FavoriteSyncResult> _syncInternal({
    required FavoriteSyncExecutionContext context,
    Set<String> forceComicSearchOnCatalogMissTids = const <String>{},
  }) async {
    _emitProgress(
      const FavoriteSyncProgress(
        phase: FavoriteSyncProgressPhase.fetchingList,
        current: 0,
      ),
    );
    final firstPageResult = await _runFavoriteListRequest(
      context: context,
      page: 1,
    );
    if (firstPageResult
        case final DataReadFailure<
              FavoriteThreadDirectoryData,
              FavoriteThreadDirectoryReadCapabilities
            >
            failure) {
      throw _FavoriteSyncFailure(failure.diagnosticMessage);
    }

    final firstRead =
        firstPageResult
            as DataReadSuccess<
              FavoriteThreadDirectoryData,
              FavoriteThreadDirectoryReadCapabilities
            >;
    final firstPage = firstRead.data;
    _emitProgress(
      FavoriteSyncProgress(
        phase: FavoriteSyncProgressPhase.fetchingList,
        current: 1,
        total: _estimatedPageCount(firstPage),
      ),
    );
    final activeBefore = await _localRepository.getActiveTids();
    final snapshot = await _localRepository.getSyncSnapshot();
    final mode = _resolveSyncMode(
      firstPage: firstPage,
      activeBefore: activeBefore,
      snapshot: snapshot,
    );

    final reads = <_FavoriteDirectoryRead>[firstRead];
    if (mode == FavoriteSyncMode.fullDiff) {
      reads.addAll(await _fetchRemainingPages(firstRead, context: context));
    } else {
      reads.addAll(
        await _fetchIncrementalPages(
          firstPage: firstRead,
          activeBefore: activeBefore,
          context: context,
        ),
      );
    }
    final readSet = _validateReadSet(reads, mode: mode);
    final pages = reads.map((read) => read.data).toList(growable: false);

    var upsertedCount = 0;
    final remoteTids = <String>{};
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.savingList,
          current: index + 1,
          total: pages.length,
        ),
      );
      remoteTids.addAll(
        page.items
            .map((item) => item.tid.trim())
            .where((tid) => tid.isNotEmpty),
      );
      upsertedCount += await _localRepository.upsertRemoteThreads(
        _cacheUpsertsFor(page),
      );
    }

    final removedRecords = mode == FavoriteSyncMode.fullDiff
        ? await _localRepository.markRemovedTids(remoteTids)
        : const <FavoriteThreadCacheRecord>[];
    await _removeModuleShelfItems(removedRecords);

    final firstFullSync = snapshot == null && mode == FavoriteSyncMode.fullDiff;
    await runBackgroundMaintenanceWithContext(context: context);
    final newlySeenTids = mode == FavoriteSyncMode.incremental
        ? remoteTids.difference(activeBefore)
        : const <String>{};
    final detailResult = await _fillMissingDetails(
      context: context,
      mergeIngestedComics: !firstFullSync,
      forceComicSearchOnCatalogMissTids: <String>{
        ...forceComicSearchOnCatalogMissTids,
        ...newlySeenTids,
      },
    );
    if (firstFullSync) {
      await _mergeAllComicDuplicatesAfterFirstSync();
    }
    _emitProgress(
      const FavoriteSyncProgress(phase: FavoriteSyncProgressPhase.finishing),
    );
    await _localRepository.finishSync(
      mode: mode,
      remoteCount: readSet.totalItems,
      status: detailResult.failedTids.isEmpty ? 'ok' : 'partial',
      message: detailResult.failedTids.isEmpty
          ? null
          : _buildPartialFailureMessage(detailResult.errors),
    );
    await _writeFavoritesSnapshot(remoteCount: readSet.totalItems);
    _notifyFavoriteShelfChanged(
      reason: 'favorite_sync_completed',
      upsertedCount: upsertedCount,
      removedCount: removedRecords.length,
      detailLoadedCount: detailResult.loadedCount,
    );

    return FavoriteSyncResult(
      mode: mode,
      remoteCount: readSet.totalItems,
      fetchedPages: pages.length,
      upsertedCount: upsertedCount,
      removedRecords: removedRecords,
      detailLoadedCount: detailResult.loadedCount,
      failedDetailTids: detailResult.failedTids,
      directoryCapabilities: readSet.capabilities,
      directoryMetadata: readSet.metadata,
    );
  }

  Future<FavoriteSyncResult> _syncRecentlyAddedThreadInternal(
    String tid, {
    required FavoriteSyncExecutionContext context,
  }) async {
    _emitProgress(
      const FavoriteSyncProgress(
        phase: FavoriteSyncProgressPhase.fetchingList,
        current: 0,
      ),
    );
    final firstPageResult = await _runFavoriteListRequest(
      context: context,
      page: 1,
    );
    if (firstPageResult
        case final DataReadFailure<
              FavoriteThreadDirectoryData,
              FavoriteThreadDirectoryReadCapabilities
            >
            failure) {
      throw _FavoriteSyncFailure(failure.diagnosticMessage);
    }

    final firstRead =
        firstPageResult
            as DataReadSuccess<
              FavoriteThreadDirectoryData,
              FavoriteThreadDirectoryReadCapabilities
            >;
    final activeBefore = await _localRepository.getActiveTids();
    final reads = <_FavoriteDirectoryRead>[firstRead];
    var current = firstRead;
    var foundTid = _pageContainsTid(current.data, tid);
    // A newly favorited thread is normally on page one. Keep a bounded
    // incremental scan for remote ordering drift without turning one button tap
    // into an unconditional full favorite sync.
    while (!foundTid &&
        current.data.pagination.hasNext == true &&
        !_pageAllKnown(current.data, activeBefore)) {
      final nextPageNumber = current.data.pagination.currentPage + 1;
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.fetchingList,
          current: reads.length,
        ),
      );
      final result = await _runFavoriteListRequest(
        context: context,
        page: nextPageNumber,
      );
      if (result
          case final DataReadFailure<
                FavoriteThreadDirectoryData,
                FavoriteThreadDirectoryReadCapabilities
              >
              failure) {
        throw _FavoriteSyncFailure(failure.diagnosticMessage);
      }
      current = result as _FavoriteDirectoryRead;
      reads.add(current);
      foundTid = _pageContainsTid(current.data, tid);
    }
    final readSet = _validateReadSet(reads, mode: FavoriteSyncMode.incremental);
    final pages = reads.map((read) => read.data).toList(growable: false);

    var upsertedCount = 0;
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.savingList,
          current: index + 1,
          total: pages.length,
        ),
      );
      upsertedCount += await _localRepository.upsertRemoteThreads(
        _cacheUpsertsFor(page),
      );
    }

    final failedTids = <String>[];
    var detailLoadedCount = 0;
    DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>?
    preloadedDetail;
    var record = await _localRepository.getActiveThreadByTid(tid);
    if (record == null) {
      // favthread may return before the favorite list endpoint exposes the new
      // row. Seed the local cache from the thread detail so the shelf updates
      // immediately, then let later list syncs fill favid/remote ordering.
      try {
        preloadedDetail = await _loadTargetDetailOrNull(tid, context: context);
        if (preloadedDetail != null) {
          upsertedCount += await _upsertRecentlyFavoritedThreadFromDetail(
            tid: tid,
            detail: preloadedDetail.data,
          );
          record = await _localRepository.getActiveThreadByTid(tid);
        }
      } catch (_) {
        preloadedDetail = null;
      }
    }
    if (record == null) {
      failedTids.add(tid);
    } else {
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.loadingDetails,
          subject: record.title,
          current: 1,
          total: 1,
        ),
      );
      try {
        final loaded = await _fillOneDetail(
          record,
          context: context,
          mergeIngestedComics: true,
          forceComicSearchOnCatalogMiss: true,
          preloadedDetail: preloadedDetail,
        );
        if (loaded) {
          detailLoadedCount = 1;
        } else {
          failedTids.add(tid);
        }
      } catch (_) {
        failedTids.add(tid);
      }
    }

    await _localRepository.finishSync(
      mode: FavoriteSyncMode.incremental,
      remoteCount: readSet.totalItems,
      status: failedTids.isEmpty ? 'ok' : 'partial',
      message: failedTids.isEmpty ? null : '新增收藏详情补全失败：${failedTids.join(',')}',
    );
    await _writeFavoritesSnapshot(remoteCount: readSet.totalItems);
    _notifyFavoriteShelfChanged(
      reason: 'thread_favorite_recent_sync_completed',
      upsertedCount: upsertedCount,
      detailLoadedCount: detailLoadedCount,
    );

    return FavoriteSyncResult(
      mode: FavoriteSyncMode.incremental,
      remoteCount: readSet.totalItems,
      fetchedPages: pages.length,
      upsertedCount: upsertedCount,
      removedRecords: const <FavoriteThreadCacheRecord>[],
      detailLoadedCount: detailLoadedCount,
      failedDetailTids: failedTids,
      directoryCapabilities: readSet.capabilities,
      directoryMetadata: readSet.metadata,
    );
  }

  FavoriteSyncMode _resolveSyncMode({
    required FavoriteThreadDirectoryData firstPage,
    required Set<String> activeBefore,
    required FavoriteSyncSnapshot? snapshot,
  }) {
    if (snapshot == null) {
      return FavoriteSyncMode.fullDiff;
    }

    final totalItems = firstPage.pagination.totalItems;
    if (totalItems == null) {
      throw const _FavoriteSyncFailure(
        'Favorite directory does not provide an exact total count.',
      );
    }
    if (totalItems < snapshot.localActiveCount) {
      return FavoriteSyncMode.fullDiff;
    }

    final pageOneTids = firstPage.items
        .map((item) => item.tid.trim())
        .where((tid) => tid.isNotEmpty);
    final pageOneAllKnown = pageOneTids.every(activeBefore.contains);
    if (totalItems == snapshot.localActiveCount && !pageOneAllKnown) {
      return FavoriteSyncMode.fullDiff;
    }

    return FavoriteSyncMode.incremental;
  }

  Future<List<_FavoriteDirectoryRead>> _fetchRemainingPages(
    _FavoriteDirectoryRead firstPage, {
    required FavoriteSyncExecutionContext context,
  }) async {
    final pages = <_FavoriteDirectoryRead>[];
    var current = firstPage;
    final estimatedTotal = _estimatedPageCount(firstPage.data);
    while (current.data.pagination.hasNext == true) {
      if (pages.length + 1 >= estimatedTotal) {
        throw const _FavoriteSyncFailure(
          'Favorite directory pagination exceeds its exact total pages.',
        );
      }
      final nextPageNumber = current.data.pagination.currentPage + 1;
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.fetchingList,
          current: nextPageNumber - 1,
          total: estimatedTotal,
        ),
      );
      final result = await _runFavoriteListRequest(
        context: context,
        page: nextPageNumber,
      );
      if (result
          case final DataReadFailure<
                FavoriteThreadDirectoryData,
                FavoriteThreadDirectoryReadCapabilities
              >
              failure) {
        throw _FavoriteSyncFailure(failure.diagnosticMessage);
      }
      current = result as _FavoriteDirectoryRead;
      pages.add(current);
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.fetchingList,
          current: nextPageNumber,
          total: estimatedTotal,
        ),
      );
    }
    return pages;
  }

  Future<List<_FavoriteDirectoryRead>> _fetchIncrementalPages({
    required _FavoriteDirectoryRead firstPage,
    required Set<String> activeBefore,
    required FavoriteSyncExecutionContext context,
  }) async {
    final pages = <_FavoriteDirectoryRead>[];
    var current = firstPage;
    while (current.data.pagination.hasNext == true &&
        !_pageAllKnown(current.data, activeBefore)) {
      final nextPageNumber = current.data.pagination.currentPage + 1;
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.fetchingList,
          current: pages.length + 1,
        ),
      );
      final result = await _runFavoriteListRequest(
        context: context,
        page: nextPageNumber,
      );
      if (result
          case final DataReadFailure<
                FavoriteThreadDirectoryData,
                FavoriteThreadDirectoryReadCapabilities
              >
              failure) {
        throw _FavoriteSyncFailure(failure.diagnosticMessage);
      }
      current = result as _FavoriteDirectoryRead;
      pages.add(current);
    }
    return pages;
  }

  bool _pageAllKnown(
    FavoriteThreadDirectoryData page,
    Set<String> activeBefore,
  ) {
    if (page.items.isEmpty) {
      return true;
    }
    return page.items
        .map((item) => item.tid.trim())
        .where((tid) => tid.isNotEmpty)
        .every(activeBefore.contains);
  }

  bool _pageContainsTid(FavoriteThreadDirectoryData page, String tid) {
    return page.items.any((item) => item.tid.trim() == tid);
  }

  Future<DataReadSuccess<ThreadDetailData, ThreadDetailReadCapabilities>?>
  _loadTargetDetailOrNull(
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

  Future<int> _upsertRecentlyFavoritedThreadFromDetail({
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

  Future<_DetailFillResult> _fillMissingDetails({
    required FavoriteSyncExecutionContext context,
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
        limit: _detailBatchLimit,
        excludedTids: failedTidSet,
      );
      if (records.isEmpty) {
        break;
      }

      var madeProgress = false;
      final failedCountBefore = failedTidSet.length;
      for (final record in records) {
        _emitProgress(
          FavoriteSyncProgress(
            phase: FavoriteSyncProgressPhase.loadingDetails,
            subject: record.title,
            current: processedCount + 1,
            total: totalMissingDetails,
          ),
        );
        try {
          final loaded = await _fillOneDetail(
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

    return _DetailFillResult(
      loadedCount: loadedCount,
      failedTids: failedTids,
      errors: errors,
    );
  }

  Future<bool> _fillOneDetail(
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

  Future<void> _mergeAllComicDuplicatesAfterFirstSync() async {
    // 首次全量同步收尾的全量去重交给 runner，与单条入库后的合并共用同一执行器，
    // 失败语义统一“不阻断收藏同步主结果”。
    await _postIngestTaskRunner.runAll(const <LibraryPostIngestTask>[
      ComicDuplicateMergeAllTask(),
    ]);
  }

  Future<void> _backfillExistingComicAutoRefreshIfNeeded({
    required FavoriteSyncExecutionContext context,
  }) async {
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
      final records = await _localRepository
          .getComicAutoRefreshBackfillCandidates(
            limit: _detailBatchLimit,
            excludedTids: checkedTids,
          );
      if (records.isEmpty) {
        break;
      }
      sawAnyCandidate = true;

      final checkedBefore = checkedTids.length;
      for (final record in records) {
        checkedTids.add(record.tid);
        final comicId = record.workId?.trim();
        if (comicId == null || comicId.isEmpty) {
          failedTids.add(record.tid);
          continue;
        }
        final report = await _postIngestTaskRunner
            .runAll(<LibraryPostIngestTask>[
              ComicAutoRefreshBackfillTask(
                comicId: comicId,
                sourceTid: record.tid,
                favoriteTitle: record.title,
                sourceTitle: record.title,
                sourceFid: record.sourceFid,
                sourceTypeId: record.sourceTypeid,
                sourceTagName: record.sourceTagName,
              ),
            ], executionContext: context);
        if (report.failures.isNotEmpty) {
          failedTids.add(record.tid);
        } else {
          checkedCount++;
        }
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

    await _localRepository.markComicAutoRefreshBackfillCompleted(
      checkedCount: checkedCount,
      message: failedTids.isEmpty
          ? null
          : '部分历史漫画自动刷新检查失败：${failedTids.join(',')}',
    );
  }

  Future<void> _removeModuleShelfItems(
    List<FavoriteThreadCacheRecord> records,
  ) async {
    for (final record in records) {
      final workId = record.workId?.trim();
      if (workId == null || workId.isEmpty) {
        continue;
      }
      final ingestHandler = _contentIngestRegistry.handlerFor(
        record.contentKind,
      );
      await ingestHandler.removeFromShelf(workId: workId);
    }
  }

  String _buildPartialFailureMessage(Map<String, String> errors) {
    final details = errors.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join(',');
    return '部分收藏详情补全失败：$details';
  }

  _FavoriteDirectoryReadSet _validateReadSet(
    List<_FavoriteDirectoryRead> reads, {
    required FavoriteSyncMode mode,
  }) {
    if (reads.isEmpty) {
      throw const _FavoriteSyncFailure('Favorite directory read set is empty.');
    }

    const requiredCapabilities = <FavoriteThreadDirectoryCapability>[
      FavoriteThreadDirectoryCapability.stableThreadIdentity,
      FavoriteThreadDirectoryCapability.orderedThreads,
      FavoriteThreadDirectoryCapability.threadTitle,
      FavoriteThreadDirectoryCapability.threadReplyCount,
      FavoriteThreadDirectoryCapability.directionalPagination,
      FavoriteThreadDirectoryCapability.pageSize,
      FavoriteThreadDirectoryCapability.totalItemCount,
      FavoriteThreadDirectoryCapability.totalPageCount,
    ];
    var combinedCapabilities = reads.first.capabilities;
    var combinedMetadata = reads.first.metadata;
    final firstPagination = reads.first.data.pagination;
    final pageSize = firstPagination.pageSize;
    final totalItems = firstPagination.totalItems;
    final totalPages = firstPagination.totalPages;
    if (pageSize == null ||
        pageSize <= 0 ||
        totalItems == null ||
        totalItems < 0 ||
        totalPages == null ||
        totalPages < 1) {
      throw const _FavoriteSyncFailure(
        'Favorite directory pagination is incomplete.',
      );
    }

    final threadIds = <String>{};
    final remoteFavoriteIds = <String>{};
    for (var index = 0; index < reads.length; index++) {
      final read = reads[index];
      if (index > 0) {
        combinedCapabilities = combinedCapabilities.intersect(
          read.capabilities,
        );
        combinedMetadata = combinedMetadata.merge(read.metadata);
      }
      if (read.capabilities.paginationPrecision != PaginationPrecision.exact ||
          !requiredCapabilities.every(read.capabilities.supports)) {
        throw const _FavoriteSyncFailure(
          'Favorite directory capabilities are insufficient for sync.',
        );
      }

      final page = read.data;
      final pagination = page.pagination;
      if (pagination.currentPage != index + 1 ||
          pagination.pageSize != pageSize ||
          pagination.totalItems != totalItems ||
          pagination.totalPages != totalPages ||
          pagination.hasPrevious != (pagination.currentPage > 1) ||
          pagination.hasNext != (pagination.currentPage < totalPages)) {
        throw const _FavoriteSyncFailure(
          'Favorite directory pages are inconsistent.',
        );
      }
      for (final item in page.items) {
        final tid = item.tid.trim();
        if (tid.isEmpty ||
            item.title.trim().isEmpty ||
            item.replyCount == null ||
            item.replyCount! < 0 ||
            !threadIds.add(tid)) {
          throw const _FavoriteSyncFailure(
            'Favorite directory contains invalid thread data.',
          );
        }
        final remoteFavoriteId = item.remoteFavoriteId?.trim();
        if (remoteFavoriteId != null &&
            remoteFavoriteId.isNotEmpty &&
            !remoteFavoriteIds.add(remoteFavoriteId)) {
          throw const _FavoriteSyncFailure(
            'Favorite directory contains duplicate remote identity.',
          );
        }
      }
    }

    if (mode == FavoriteSyncMode.fullDiff &&
        (reads.last.data.pagination.hasNext != false ||
            reads.length != totalPages ||
            threadIds.length != totalItems)) {
      throw const _FavoriteSyncFailure(
        'Favorite directory full read is incomplete.',
      );
    }
    return _FavoriteDirectoryReadSet(
      capabilities: combinedCapabilities,
      metadata: combinedMetadata,
      totalItems: totalItems,
    );
  }

  List<FavoriteThreadCacheUpsert> _cacheUpsertsFor(
    FavoriteThreadDirectoryData page,
  ) {
    final pageSize = page.pagination.pageSize!;
    final pageStartOrder = (page.pagination.currentPage - 1) * pageSize;
    return <FavoriteThreadCacheUpsert>[
      for (var index = 0; index < page.items.length; index++)
        FavoriteThreadCacheUpsert(
          tid: page.items[index].tid,
          title: page.items[index].title,
          replyCount: page.items[index].replyCount!,
          remoteFavoriteId: page.items[index].remoteFavoriteId,
          description: page.items[index].description,
          authorName: page.items[index].authorName,
          favoritedAt: page.items[index].favoritedAt,
          remoteOrder: pageStartOrder + index,
        ),
    ];
  }

  int _estimatedPageCount(FavoriteThreadDirectoryData page) {
    return page.pagination.totalPages ?? page.pagination.currentPage;
  }

  void _emitProgress(FavoriteSyncProgress progress) {
    _progress.value = progress;
  }

  Future<
    DataReadResult<
      FavoriteThreadDirectoryData,
      FavoriteThreadDirectoryReadCapabilities
    >
  >
  _runFavoriteListRequest({
    required FavoriteSyncExecutionContext context,
    required int page,
  }) {
    final governor = context.governor;
    if (governor == null) {
      return _remoteRepository.load(
        FavoriteThreadDirectoryQuery(page: page),
        cachePolicy: CacheLoadPolicy.networkFirst,
      );
    }
    return governor.run(
      kind: FavoriteFirstSyncRequestKind.favoriteListPage,
      action: () => _remoteRepository.load(
        FavoriteThreadDirectoryQuery(page: page),
        cachePolicy: CacheLoadPolicy.networkFirst,
      ),
    );
  }

  Future<void> runBackgroundMaintenanceWithContext({
    required FavoriteSyncExecutionContext context,
  }) async {
    try {
      await _backfillExistingComicAutoRefreshIfNeeded(context: context);
    } catch (_) {
      // 后台维护不改变收藏同步主状态；失败时保留全局 marker 为空，
      // 下一次进入收藏页或手动同步仍可继续尝试。
    }
  }

  void _notifyFavoriteShelfChanged({
    required String reason,
    int upsertedCount = 0,
    int removedCount = 0,
    int detailLoadedCount = 0,
  }) {
    if (upsertedCount <= 0 && removedCount <= 0 && detailLoadedCount <= 0) {
      return;
    }
    _shelfRefreshBus?.notify(
      modules: const <LibraryModuleKey>{LibraryModuleKey.favorite},
      reason: reason,
      source: LibraryMutationSource.favoriteSync,
      payload: <String, Object?>{
        'upsertedCount': upsertedCount,
        'removedCount': removedCount,
        'detailLoadedCount': detailLoadedCount,
      },
    );
  }

  Future<void> _writeFavoritesSnapshot({required int remoteCount}) async {
    final storage = _downloadStorageService;
    if (storage == null) {
      return;
    }
    final records = await _localRepository.getActiveThreadsForSnapshot();
    await storage.writeFavoritesSnapshot(<String, Object?>{
      'schemaVersion': 1,
      'remoteCount': remoteCount,
      'syncedAt': DateTime.now().toUtc().toIso8601String(),
      'threads': records.map(_favoriteSnapshotRow).toList(growable: false),
    });
  }

  Map<String, Object?> _favoriteSnapshotRow(FavoriteThreadCacheRecord record) {
    return <String, Object?>{
      'tid': record.tid,
      'favid': record.remoteFavoriteId,
      'title': record.title,
      'author': record.authorName,
      'fid': record.sourceFid,
      'typeid': record.sourceTypeid,
      'tagName': record.sourceTagName,
      'contentKind': favoriteContentKindToDb(record.contentKind),
      'workId': record.workId,
      'removed': record.removedAt != null,
      'dateline': record.favoritedAt?.millisecondsSinceEpoch == null
          ? null
          : record.favoritedAt!.millisecondsSinceEpoch ~/
                Duration.millisecondsPerSecond,
    };
  }
}

class _FavoriteSyncFailure implements Exception {
  const _FavoriteSyncFailure(this.message);

  final String message;
}

class _DetailFillResult {
  const _DetailFillResult({
    required this.loadedCount,
    required this.failedTids,
    required this.errors,
  });

  final int loadedCount;
  final List<String> failedTids;
  final Map<String, String> errors;
}

class _FavoriteDirectoryReadSet {
  const _FavoriteDirectoryReadSet({
    required this.capabilities,
    required this.metadata,
    required this.totalItems,
  });

  final FavoriteThreadDirectoryReadCapabilities capabilities;
  final DataReadMetadata metadata;
  final int totalItems;
}
