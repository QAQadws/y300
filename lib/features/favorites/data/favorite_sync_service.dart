import 'package:flutter/foundation.dart';
import 'package:y300/features/comic/data/comic_favorite_auto_refresh_coordinator.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/data/comic_favorite_ingest_service.dart';
import 'package:y300/features/comic/domain/services/comic_duplicate_merge_service.dart';
import 'package:y300/features/favorites/data/favorite_repository.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/novel/data/novel_favorite_ingest_service.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/tags/domain/forum_tag_lookup.dart';
import 'package:y300/features/thread/data/models/thread_detail_models.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';

typedef FavoriteThreadDetailLoader = Future<ApiResult<ThreadDetailData>> Function(String tid);
typedef FavoriteTagLookupLoader = Future<ForumTagLookup> Function();

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

  Future<void> runBackgroundMaintenance();

  ValueListenable<FavoriteSyncProgress> get progress;
}

class NetworkFavoriteSyncService implements FavoriteSyncService {
  NetworkFavoriteSyncService({
    required FavoriteRepository remoteRepository,
    required LocalFavoriteRepository localRepository,
    required FavoriteThreadDetailLoader loadThreadDetail,
    required FavoriteTagLookupLoader loadTagLookup,
    required ThreadContentClassifier classifier,
    required ComicFavoriteIngestService comicIngestService,
    required NovelFavoriteIngestService novelIngestService,
    ComicFavoriteAutoRefreshCoordinator? comicAutoRefreshCoordinator,
    ComicDuplicateMergeService? comicDuplicateMergeService,
    LibraryShelfRefreshBus? shelfRefreshBus,
    DownloadStorageService? downloadStorageService,
    int detailBatchLimit = 20,
  })  : _remoteRepository = remoteRepository,
        _localRepository = localRepository,
        _loadThreadDetail = loadThreadDetail,
        _loadTagLookup = loadTagLookup,
        _classifier = classifier,
        _comicIngestService = comicIngestService,
        _novelIngestService = novelIngestService,
        _comicAutoRefreshCoordinator = comicAutoRefreshCoordinator,
        _comicDuplicateMergeService = comicDuplicateMergeService,
        _shelfRefreshBus = shelfRefreshBus,
        _downloadStorageService = downloadStorageService,
        _detailBatchLimit = detailBatchLimit;

  final FavoriteRepository _remoteRepository;
  final LocalFavoriteRepository _localRepository;
  final FavoriteThreadDetailLoader _loadThreadDetail;
  final FavoriteTagLookupLoader _loadTagLookup;
  final ThreadContentClassifier _classifier;
  final ComicFavoriteIngestService _comicIngestService;
  final NovelFavoriteIngestService _novelIngestService;
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
    try {
      final result = await _syncInternal();
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

  Future<FavoriteSyncResult> _syncInternal() async {
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
    final detailResult = await _fillMissingDetails(
      mergeIngestedComics: !firstFullSync,
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

  Future<_DetailFillResult> _fillMissingDetails({
    bool mergeIngestedComics = true,
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
  }) async {
    final result = await _loadThreadDetail(record.tid);
    if (result is ApiFailure<ThreadDetailData>) {
      return false;
    }

    final detail = result.dataOrNull;
    if (detail == null) {
      return false;
    }

    final tagName = await _findTagName(
      fid: detail.fid,
      typeid: detail.typeid,
    );
    final kind = _classifier.classify(
      fid: detail.fid,
      typeid: detail.typeid,
      tagName: tagName,
    );
    final workId = await _syncModule(
      detail: detail,
      kind: kind,
      tagName: tagName,
      favoriteTitle: record.title,
      mergeIngestedComic: mergeIngestedComics,
    );

    await _localRepository.updateThreadDetailMeta(
      tid: record.tid,
      fid: detail.fid,
      typeid: detail.typeid,
      tagName: tagName,
      contentKind: kind,
      workId: workId,
    );
    return true;
  }

  Future<String?> _findTagName({
    required String fid,
    required String typeid,
  }) async {
    if (fid.trim().isEmpty || typeid.trim().isEmpty) {
      return null;
    }
    try {
      final lookup = await _loadTagLookup();
      return lookup.findName(fid: fid, typeid: typeid);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _syncModule({
    required ThreadDetailData detail,
    required ThreadContentKind kind,
    required String? tagName,
    required String favoriteTitle,
    required bool mergeIngestedComic,
  }) async {
    switch (kind) {
      case ThreadContentKind.comic:
        final workId = await _comicIngestService.upsertFromThreadDetail(
          detail: detail,
          sourceTagName: tagName,
        );
        await _runComicAutoRefresh(
          comicId: workId,
          detail: detail,
          favoriteTitle: favoriteTitle,
          sourceTagName: tagName,
        );
        if (!mergeIngestedComic) {
          return workId;
        }
        return _mergeIngestedComicIfNeeded(workId);
      case ThreadContentKind.novel:
        final workId = await _novelIngestService.upsertFromThreadDetail(
          detail: detail,
          sourceTagName: tagName,
        );
        _shelfRefreshBus?.notify(
          modules: const <LibraryModuleKey>{
            LibraryModuleKey.novel,
            LibraryModuleKey.favorite,
          },
          reason: 'favorite_novel_refresh_completed',
        );
        return workId;
      case ThreadContentKind.unknown:
      case ThreadContentKind.forum:
        return 'thread:${detail.tid}';
    }
  }

  Future<void> _runComicAutoRefresh({
    required String comicId,
    required ThreadDetailData detail,
    required String favoriteTitle,
    String? sourceTagName,
  }) async {
    final coordinator = _comicAutoRefreshCoordinator;
    if (coordinator == null) {
      return;
    }
    try {
      await coordinator.refreshAfterFavoriteIngest(
        comicId: comicId,
        detail: detail,
        favoriteTitle: favoriteTitle,
        sourceTagName: sourceTagName,
      );
    } catch (_) {
      // 收藏详情已经入库；catalog 引导/队列入队失败不应让本条收藏反复
      // 停留在 detail_loaded_at 为空的状态。后续手动刷新或搜索队列可继续补偿。
    }
  }

  Future<String> _mergeIngestedComicIfNeeded(String comicId) async {
    final service = _comicDuplicateMergeService;
    if (service == null) {
      return comicId;
    }
    try {
      final result = await service.mergeComic(comicId: comicId);
      if (result.changed) {
        _shelfRefreshBus?.notify(
          modules: const <LibraryModuleKey>{
            LibraryModuleKey.comic,
            LibraryModuleKey.favorite,
          },
          reason: 'favorite_comic_duplicate_merge_completed',
        );
      }
      return result.targetComicId.trim().isEmpty ? comicId : result.targetComicId;
    } catch (_) {
      // 合并是收藏入库后的维护步骤；失败不应让本条收藏回到“未补详情”
      // 状态，后续手动“合并重复”或下一次增量仍可补偿。
      return comicId;
    }
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
      switch (record.contentKind) {
        case ThreadContentKind.comic:
          await _comicIngestService.removeFromShelf(workId: workId);
          break;
        case ThreadContentKind.novel:
          await _novelIngestService.removeFromShelf(workId: workId);
          break;
        case ThreadContentKind.unknown:
        case ThreadContentKind.forum:
          break;
      }
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
