import 'package:flutter/foundation.dart';
import 'package:y300/features/comic/data/comic_favorite_auto_refresh_coordinator.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/domain/services/comic_duplicate_merge_service.dart';
import 'package:y300/features/favorites/data/favorite_detail_context_loader.dart';
import 'package:y300/features/favorites/data/favorite_repository.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/favorite_content_ingest.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';

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
    required this.message,
    this.current = 0,
    this.total,
  });

  final FavoriteSyncProgressPhase phase;
  final String message;
  final int current;
  final int? total;

  bool get isActive {
    return switch (phase) {
      FavoriteSyncProgressPhase.fetchingList ||
      FavoriteSyncProgressPhase.savingList ||
      FavoriteSyncProgressPhase.loadingDetails ||
      FavoriteSyncProgressPhase.finishing =>
        true,
      FavoriteSyncProgressPhase.idle ||
      FavoriteSyncProgressPhase.completed ||
      FavoriteSyncProgressPhase.failed =>
        false,
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
    message: '',
  );
}

abstract class FavoriteSyncService {
  Future<FavoriteSyncResult> sync();

  Future<FavoriteSyncResult> syncRecentlyAddedThread({
    required String tid,
  });

  Future<void> runBackgroundMaintenance();

  ValueListenable<FavoriteSyncProgress> get progress;
}

class NetworkFavoriteSyncService implements FavoriteSyncService {
  NetworkFavoriteSyncService({
    required FavoriteRepository remoteRepository,
    required LocalFavoriteRepository localRepository,
    required FavoriteDetailContextLoader detailContextLoader,
    required FavoriteContentIngestRegistry contentIngestRegistry,
    ComicFavoriteAutoRefreshCoordinator? comicAutoRefreshCoordinator,
    ComicDuplicateMergeService? comicDuplicateMergeService,
    LibraryShelfRefreshBus? shelfRefreshBus,
    DownloadStorageService? downloadStorageService,
    int detailBatchLimit = 20,
  })  : _remoteRepository = remoteRepository,
        _localRepository = localRepository,
        _detailContextLoader = detailContextLoader,
        _contentIngestRegistry = contentIngestRegistry,
        _comicAutoRefreshCoordinator = comicAutoRefreshCoordinator,
        _comicDuplicateMergeService = comicDuplicateMergeService,
        _shelfRefreshBus = shelfRefreshBus,
        _downloadStorageService = downloadStorageService,
        _detailBatchLimit = detailBatchLimit;

  final FavoriteRepository _remoteRepository;
  final LocalFavoriteRepository _localRepository;
  final FavoriteDetailContextLoader _detailContextLoader;
  final FavoriteContentIngestRegistry _contentIngestRegistry;
  final ComicFavoriteAutoRefreshCoordinator? _comicAutoRefreshCoordinator;
  final ComicDuplicateMergeService? _comicDuplicateMergeService;
  final LibraryShelfRefreshBus? _shelfRefreshBus;
  final DownloadStorageService? _downloadStorageService;
  final int _detailBatchLimit;
  final ValueNotifier<FavoriteSyncProgress> _progress = ValueNotifier<FavoriteSyncProgress>(
    FavoriteSyncProgress.idle,
  );

  @override
  ValueListenable<FavoriteSyncProgress> get progress => _progress;

  @override
  Future<void> runBackgroundMaintenance() async {
    try {
      await _backfillExistingComicAutoRefreshIfNeeded();
    } catch (_) {
      // 后台维护不改变收藏同步主状态；失败时保留全局 marker 为空，
      // 下一次进入收藏页或手动同步仍可继续尝试。
    }
  }

  @override
  Future<FavoriteSyncResult> sync() async {
    return _runSync(() => _syncInternal());
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
      if (snapshot == null) {
        // No baseline exists yet, so keep correctness by doing the regular
        // first sync while still forcing the just-favorited comic through the
        // search queue if catalog discovery misses.
        return _syncInternal(
          forceComicSearchOnCatalogMissTids: <String>{normalizedTid},
        );
      }
      return _syncRecentlyAddedThreadInternal(normalizedTid);
    });
  }

  Future<FavoriteSyncResult> _runSync(
    Future<FavoriteSyncResult> Function() body,
  ) async {
    try {
      final result = await body();
      _emitProgress(
        const FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.completed,
          message: '收藏同步完成',
        ),
      );
      return result;
    } on _FavoriteSyncFailure catch (error) {
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.failed,
          message: error.message,
        ),
      );
      await _localRepository.markSyncFailure(error.message);
      throw StateError(error.message);
    } catch (error) {
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.failed,
          message: '$error',
        ),
      );
      await _localRepository.markSyncFailure('$error');
      rethrow;
    }
  }

  Future<FavoriteSyncResult> _syncInternal({
    Set<String> forceComicSearchOnCatalogMissTids = const <String>{},
  }) async {
    _emitProgress(
      const FavoriteSyncProgress(
        phase: FavoriteSyncProgressPhase.fetchingList,
        message: '正在读取收藏列表 1/?',
        current: 0,
      ),
    );
    final firstPageResult = await _remoteRepository.getFavoriteThreads(page: 1);
    if (firstPageResult is ApiFailure<FavoriteThreadsPage>) {
      throw _FavoriteSyncFailure(firstPageResult.error.message);
    }

    final firstPage = firstPageResult.dataOrNull!;
    _emitProgress(
      FavoriteSyncProgress(
        phase: FavoriteSyncProgressPhase.fetchingList,
        message: '正在读取收藏列表 1/${_estimatedPageCount(firstPage)}',
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

    final pages = <FavoriteThreadsPage>[firstPage];
    if (mode == FavoriteSyncMode.fullDiff) {
      pages.addAll(await _fetchRemainingPages(firstPage));
    } else {
      pages.addAll(
        await _fetchIncrementalPages(
          firstPage: firstPage,
          activeBefore: activeBefore,
        ),
      );
    }

    var upsertedCount = 0;
    final remoteTids = <String>{};
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.savingList,
          message: '正在写入收藏列表 ${index + 1}/${pages.length}',
          current: index + 1,
          total: pages.length,
        ),
      );
      remoteTids.addAll(page.items.map((item) => item.tid.trim()).where((tid) => tid.isNotEmpty));
      final pageStartOrder = (page.page - 1) * page.perPage;
      upsertedCount += await _localRepository.upsertRemotePage(
        page: page,
        pageStartOrder: pageStartOrder,
      );
    }

    final removedRecords = mode == FavoriteSyncMode.fullDiff
        ? await _localRepository.markRemovedTids(remoteTids)
        : const <FavoriteThreadCacheRecord>[];
    await _removeModuleShelfItems(removedRecords);

    final firstFullSync = snapshot == null && mode == FavoriteSyncMode.fullDiff;
    await runBackgroundMaintenance();
    final newlySeenTids = mode == FavoriteSyncMode.incremental
        ? remoteTids.difference(activeBefore)
        : const <String>{};
    final detailResult = await _fillMissingDetails(
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
      const FavoriteSyncProgress(
        phase: FavoriteSyncProgressPhase.finishing,
        message: '正在整理收藏同步结果',
      ),
    );
    await _localRepository.finishSync(
      mode: mode,
      remoteCount: firstPage.totalCount,
      status: detailResult.failedTids.isEmpty ? 'ok' : 'partial',
      message: detailResult.failedTids.isEmpty
          ? null
          : _buildPartialFailureMessage(detailResult.errors),
    );
    await _writeFavoritesSnapshot(remoteCount: firstPage.totalCount);
    _notifyFavoriteShelfChanged(
      reason: 'favorite_sync_completed',
      upsertedCount: upsertedCount,
      removedCount: removedRecords.length,
      detailLoadedCount: detailResult.loadedCount,
    );

    return FavoriteSyncResult(
      mode: mode,
      remoteCount: firstPage.totalCount,
      fetchedPages: pages.length,
      upsertedCount: upsertedCount,
      removedRecords: removedRecords,
      detailLoadedCount: detailResult.loadedCount,
      failedDetailTids: detailResult.failedTids,
    );
  }

  Future<FavoriteSyncResult> _syncRecentlyAddedThreadInternal(String tid) async {
    _emitProgress(
      const FavoriteSyncProgress(
        phase: FavoriteSyncProgressPhase.fetchingList,
        message: '正在读取新增收藏列表 1/?',
        current: 0,
      ),
    );
    final firstPageResult = await _remoteRepository.getFavoriteThreads(page: 1);
    if (firstPageResult is ApiFailure<FavoriteThreadsPage>) {
      throw _FavoriteSyncFailure(firstPageResult.error.message);
    }

    final firstPage = firstPageResult.dataOrNull!;
    final activeBefore = await _localRepository.getActiveTids();
    final pages = <FavoriteThreadsPage>[firstPage];
    var current = firstPage;
    var foundTid = _pageContainsTid(current, tid);
    // A newly favorited thread is normally on page one. Keep a bounded
    // incremental scan for remote ordering drift without turning one button tap
    // into an unconditional full favorite sync.
    while (!foundTid && current.hasMore && !_pageAllKnown(current, activeBefore)) {
      final nextPageNumber = current.page + 1;
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.fetchingList,
          message: '正在查找新增收藏第 $nextPageNumber 页',
          current: pages.length,
        ),
      );
      final result = await _remoteRepository.getFavoriteThreads(page: nextPageNumber);
      if (result is ApiFailure<FavoriteThreadsPage>) {
        throw _FavoriteSyncFailure(result.error.message);
      }
      current = result.dataOrNull!;
      pages.add(current);
      foundTid = _pageContainsTid(current, tid);
    }

    var upsertedCount = 0;
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.savingList,
          message: '正在写入新增收藏 ${index + 1}/${pages.length}',
          current: index + 1,
          total: pages.length,
        ),
      );
      upsertedCount += await _localRepository.upsertRemotePage(
        page: page,
        pageStartOrder: (page.page - 1) * page.perPage,
      );
    }

    final failedTids = <String>[];
    var detailLoadedCount = 0;
    ThreadDetailData? preloadedDetail;
    var record = await _localRepository.getActiveThreadByTid(tid);
    if (record == null) {
      // favthread may return before the favorite list endpoint exposes the new
      // row. Seed the local cache from the thread detail so the shelf updates
      // immediately, then let later list syncs fill favid/remote ordering.
      try {
        preloadedDetail = await _loadTargetDetailOrNull(tid);
        if (preloadedDetail != null) {
          upsertedCount += await _upsertRecentlyFavoritedThreadFromDetail(
            tid: tid,
            detail: preloadedDetail,
            remoteCount: firstPage.totalCount,
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
          message: '正在解析: ${record.title}',
          current: 1,
          total: 1,
        ),
      );
      try {
        final loaded = await _fillOneDetail(
          record,
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
      remoteCount: firstPage.totalCount,
      status: failedTids.isEmpty ? 'ok' : 'partial',
      message: failedTids.isEmpty ? null : '新增收藏详情补全失败：${failedTids.join(',')}',
    );
    await _writeFavoritesSnapshot(remoteCount: firstPage.totalCount);
    _notifyFavoriteShelfChanged(
      reason: 'thread_favorite_recent_sync_completed',
      upsertedCount: upsertedCount,
      detailLoadedCount: detailLoadedCount,
    );

    return FavoriteSyncResult(
      mode: FavoriteSyncMode.incremental,
      remoteCount: firstPage.totalCount,
      fetchedPages: pages.length,
      upsertedCount: upsertedCount,
      removedRecords: const <FavoriteThreadCacheRecord>[],
      detailLoadedCount: detailLoadedCount,
      failedDetailTids: failedTids,
    );
  }

  FavoriteSyncMode _resolveSyncMode({
    required FavoriteThreadsPage firstPage,
    required Set<String> activeBefore,
    required FavoriteSyncSnapshot? snapshot,
  }) {
    if (snapshot == null) {
      return FavoriteSyncMode.fullDiff;
    }

    if (firstPage.totalCount < snapshot.localActiveCount) {
      return FavoriteSyncMode.fullDiff;
    }

    final pageOneTids = firstPage.items.map((item) => item.tid.trim()).where((tid) => tid.isNotEmpty);
    final pageOneAllKnown = pageOneTids.every(activeBefore.contains);
    if (firstPage.totalCount == snapshot.localActiveCount && !pageOneAllKnown) {
      return FavoriteSyncMode.fullDiff;
    }

    return FavoriteSyncMode.incremental;
  }

  Future<List<FavoriteThreadsPage>> _fetchRemainingPages(
    FavoriteThreadsPage firstPage,
  ) async {
    final pages = <FavoriteThreadsPage>[];
    var current = firstPage;
    final estimatedTotal = _estimatedPageCount(firstPage);
    while (current.hasMore) {
      final nextPageNumber = current.page + 1;
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.fetchingList,
          message: '正在读取收藏列表 $nextPageNumber/$estimatedTotal',
          current: nextPageNumber - 1,
          total: estimatedTotal,
        ),
      );
      final result = await _remoteRepository.getFavoriteThreads(page: nextPageNumber);
      if (result is ApiFailure<FavoriteThreadsPage>) {
        throw _FavoriteSyncFailure(result.error.message);
      }
      current = result.dataOrNull!;
      pages.add(current);
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.fetchingList,
          message: '正在读取收藏列表 $nextPageNumber/$estimatedTotal',
          current: nextPageNumber,
          total: estimatedTotal,
        ),
      );
    }
    return pages;
  }

  Future<List<FavoriteThreadsPage>> _fetchIncrementalPages({
    required FavoriteThreadsPage firstPage,
    required Set<String> activeBefore,
  }) async {
    final pages = <FavoriteThreadsPage>[];
    var current = firstPage;
    while (current.hasMore && !_pageAllKnown(current, activeBefore)) {
      final nextPageNumber = current.page + 1;
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.fetchingList,
          message: '正在读取新增收藏第 $nextPageNumber 页',
          current: pages.length + 1,
        ),
      );
      final result = await _remoteRepository.getFavoriteThreads(page: nextPageNumber);
      if (result is ApiFailure<FavoriteThreadsPage>) {
        throw _FavoriteSyncFailure(result.error.message);
      }
      current = result.dataOrNull!;
      pages.add(current);
    }
    return pages;
  }

  bool _pageAllKnown(FavoriteThreadsPage page, Set<String> activeBefore) {
    if (page.items.isEmpty) {
      return true;
    }
    return page.items
        .map((item) => item.tid.trim())
        .where((tid) => tid.isNotEmpty)
        .every(activeBefore.contains);
  }

  bool _pageContainsTid(FavoriteThreadsPage page, String tid) {
    return page.items.any((item) => item.tid.trim() == tid);
  }

  Future<ThreadDetailData?> _loadTargetDetailOrNull(String tid) async {
    final result = await _detailContextLoader.loadDetail(tid);
    if (result is ApiFailure<ThreadDetailData>) {
      return null;
    }
    return result.dataOrNull;
  }

  Future<int> _upsertRecentlyFavoritedThreadFromDetail({
    required String tid,
    required ThreadDetailData detail,
    required int remoteCount,
  }) {
    final normalizedTid = tid.trim();
    if (normalizedTid.isEmpty) {
      return Future<int>.value(0);
    }
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final title = detail.subject.trim().isEmpty ? normalizedTid : detail.subject;
    return _localRepository.upsertRemotePage(
      page: FavoriteThreadsPage(
        page: 1,
        perPage: 1,
        totalCount: remoteCount > 0 ? remoteCount : 1,
        items: <FavoriteThread>[
          FavoriteThread(
            favid: '',
            tid: normalizedTid,
            title: title,
            description: '',
            author: detail.author,
            replies: detail.replies,
            url: 'thread-$normalizedTid-1-1.html',
            dateline: nowSeconds,
          ),
        ],
      ),
      pageStartOrder: 0,
    );
  }

  Future<_DetailFillResult> _fillMissingDetails({
    bool mergeIngestedComics = true,
    Set<String> forceComicSearchOnCatalogMissTids = const <String>{},
  }) async {
    final totalMissingDetails = await _localRepository.countMissingDetailRecords();
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
            message: '正在解析: ${record.title}',
            current: processedCount + 1,
            total: totalMissingDetails,
          ),
        );
        try {
          final loaded = await _fillOneDetail(
            record,
            mergeIngestedComics: mergeIngestedComics,
            forceComicSearchOnCatalogMiss:
                forceComicSearchOnCatalogMissTids.contains(record.tid),
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
    required bool mergeIngestedComics,
    bool forceComicSearchOnCatalogMiss = false,
    ThreadDetailData? preloadedDetail,
  }) async {
    final result = await _detailContextLoader.load(
      record,
      preloadedDetail: preloadedDetail,
    );
    return result.when(
      success: (context) async {
        final ingestHandler = _contentIngestRegistry.handlerFor(context.kind);
        final ingestResult = await ingestHandler.ingest(
          FavoriteContentIngestRequest(
            context: context,
            options: FavoriteIngestOptions(
              mergeIngestedComic: mergeIngestedComics,
              forceComicSearchOnCatalogMiss: forceComicSearchOnCatalogMiss,
            ),
          ),
        );

        await _localRepository.updateThreadDetailMeta(
          tid: context.record.tid,
          fid: context.detail.fid,
          typeid: context.detail.typeid,
          tagName: context.tagName,
          contentKind: context.kind,
          workId: ingestResult.workId,
        );
        return true;
      },
      failure: (_) async => false,
    );
  }

  Future<void> _mergeAllComicDuplicatesAfterFirstSync() async {
    final service = _comicDuplicateMergeService;
    if (service == null) {
      return;
    }
    try {
      final summary = await service.mergeAllDuplicates();
      if (summary.changed) {
        _shelfRefreshBus?.notify(
          modules: const <LibraryModuleKey>{
            LibraryModuleKey.comic,
            LibraryModuleKey.favorite,
          },
          reason: 'favorite_first_sync_comic_duplicate_merge_completed',
        );
      }
    } catch (_) {
      // 首次同步的主结果优先；全量去重失败可由书架菜单或下一次同步补偿。
    }
  }

  Future<void> _backfillExistingComicAutoRefreshIfNeeded() async {
    final coordinator = _comicAutoRefreshCoordinator;
    if (coordinator == null) {
      return;
    }
    if (await _localRepository.hasCompletedComicAutoRefreshBackfill()) {
      return;
    }

    final checkedTids = <String>{};
    final failedTids = <String>[];
    var checkedCount = 0;

    while (true) {
      final records = await _localRepository.getComicAutoRefreshBackfillCandidates(
        limit: _detailBatchLimit,
        excludedTids: checkedTids,
      );
      if (records.isEmpty) {
        break;
      }

      final checkedBefore = checkedTids.length;
      for (final record in records) {
        checkedTids.add(record.tid);
        final comicId = record.workId?.trim();
        if (comicId == null || comicId.isEmpty) {
          failedTids.add(record.tid);
          continue;
        }
        try {
          await coordinator.refreshFavoriteComic(
            comicId: comicId,
            sourceTid: record.tid,
            favoriteTitle: record.title,
            sourceTitle: record.title,
            sourceTagName: record.sourceTagName,
          );
          checkedCount++;
        } catch (_) {
          failedTids.add(record.tid);
        }
      }

      // Defensive break: if a repository implementation returns only already
      // excluded records, avoid spinning forever in background maintenance.
      if (checkedTids.length == checkedBefore) {
        break;
      }
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
      final ingestHandler = _contentIngestRegistry.handlerFor(record.contentKind);
      await ingestHandler.removeFromShelf(workId: workId);
    }
  }

  String _buildPartialFailureMessage(Map<String, String> errors) {
    final details = errors.entries.map((entry) => '${entry.key}:${entry.value}').join(',');
    return '部分收藏详情补全失败：$details';
  }

  int _estimatedPageCount(FavoriteThreadsPage page) {
    if (page.perPage <= 0 || page.totalCount <= 0) {
      return page.page;
    }
    return (page.totalCount / page.perPage).ceil();
  }

  void _emitProgress(FavoriteSyncProgress progress) {
    _progress.value = progress;
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
    );
  }

  Future<void> _writeFavoritesSnapshot({required int remoteCount}) async {
    final storage = _downloadStorageService;
    if (storage == null) {
      return;
    }
    final records = await _localRepository.getActiveThreadsForSnapshot();
    await storage.writeFavoritesSnapshot(
      <String, Object?>{
        'schemaVersion': 1,
        'remoteCount': remoteCount,
        'syncedAt': DateTime.now().toUtc().toIso8601String(),
        'threads': records.map(_favoriteSnapshotRow).toList(growable: false),
      },
    );
  }

  Map<String, Object?> _favoriteSnapshotRow(FavoriteThreadCacheRecord record) {
    return <String, Object?>{
      'tid': record.tid,
      'favid': record.favid,
      'title': record.title,
      'author': record.author,
      'fid': record.sourceFid,
      'typeid': record.sourceTypeid,
      'tagName': record.sourceTagName,
      'contentKind': favoriteContentKindToDb(record.contentKind),
      'workId': record.workId,
      'removed': record.removedAt != null,
      'dateline': record.dateline?.millisecondsSinceEpoch == null
          ? null
          : record.dateline!.millisecondsSinceEpoch ~/ 1000,
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
