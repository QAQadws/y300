import 'package:flutter/foundation.dart';
import 'package:y300/core/network/api_result.dart';
import 'package:y300/features/comic/data/comic_favorite_ingest_service.dart';
import 'package:y300/features/favorites/data/favorite_repository.dart';
import 'package:y300/features/favorites/data/local_favorite_repository.dart';
import 'package:y300/features/favorites/data/models/favorite_models.dart';
import 'package:y300/features/favorites/domain/favorite_cache_models.dart';
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
  classifying,     // 快速分类中：加载详情 + contentKind 判定（不摄入模块）
  classified,      // 快速分类完成：收藏页此时已可按分类展示
  ingesting,       // 渐进摄入中：逐个摄入漫画/小说模块
  loadingDetails,  // 向后兼容旧阶段
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
      FavoriteSyncProgressPhase.classifying ||
      FavoriteSyncProgressPhase.ingesting ||
      FavoriteSyncProgressPhase.loadingDetails ||
      FavoriteSyncProgressPhase.finishing =>
        true,
      FavoriteSyncProgressPhase.idle ||
      FavoriteSyncProgressPhase.classified ||
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
    DownloadStorageService? downloadStorageService,
    int detailBatchLimit = 20,
    int ingestNotifyBatchSize = 3,
  })  : _remoteRepository = remoteRepository,
        _localRepository = localRepository,
        _loadThreadDetail = loadThreadDetail,
        _loadTagLookup = loadTagLookup,
        _classifier = classifier,
        _comicIngestService = comicIngestService,
        _novelIngestService = novelIngestService,
        _downloadStorageService = downloadStorageService,
        _detailBatchLimit = detailBatchLimit,
        _ingestNotifyBatchSize = ingestNotifyBatchSize;

  final FavoriteRepository _remoteRepository;
  final LocalFavoriteRepository _localRepository;
  final FavoriteThreadDetailLoader _loadThreadDetail;
  final FavoriteTagLookupLoader _loadTagLookup;
  final ThreadContentClassifier _classifier;
  final ComicFavoriteIngestService _comicIngestService;
  final NovelFavoriteIngestService _novelIngestService;
  final DownloadStorageService? _downloadStorageService;
  final int _detailBatchLimit;

  /// 每摄入多少条后通知 UI 刷新一次。
  final int _ingestNotifyBatchSize;

  final ValueNotifier<FavoriteSyncProgress> _progress = ValueNotifier<FavoriteSyncProgress>(
    FavoriteSyncProgress.idle,
  );

  @override
  ValueListenable<FavoriteSyncProgress> get progress => _progress;

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

    // 阶段 A：快速分类 — 加载详情 + contentKind 判定，不摄入模块。
    final classifyResult = await _lightClassify();
    final classifyTotal = classifyResult.loadedCount + classifyResult.failedTids.length;
    _emitProgress(
      FavoriteSyncProgress(
        phase: FavoriteSyncProgressPhase.classified,
        message: '已完成快速分类',
        current: classifyResult.loadedCount,
        total: classifyTotal,
      ),
    );

    // 阶段 B：渐进摄入 — 逐个摄入漫画/小说模块，按 remote_order ASC。
    final ingestResult = await _progressiveIngest();

    _emitProgress(
      const FavoriteSyncProgress(
        phase: FavoriteSyncProgressPhase.finishing,
        message: '正在整理收藏同步结果',
      ),
    );
    final allFailedTids = [...classifyResult.failedTids, ...ingestResult.failedTids];
    final allErrors = {...classifyResult.errors, ...ingestResult.errors};
    await _localRepository.finishSync(
      mode: mode,
      remoteCount: firstPage.totalCount,
      status: allFailedTids.isEmpty ? 'ok' : 'partial',
      message: allFailedTids.isEmpty ? null : _buildPartialFailureMessage(allErrors),
    );
    await _writeFavoritesSnapshot(remoteCount: firstPage.totalCount);

    return FavoriteSyncResult(
      mode: mode,
      remoteCount: firstPage.totalCount,
      fetchedPages: pages.length,
      upsertedCount: upsertedCount,
      removedRecords: removedRecords,
      detailLoadedCount: classifyResult.loadedCount + ingestResult.loadedCount,
      failedDetailTids: allFailedTids,
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

  /// 阶段 A：快速分类。
  ///
  /// 加载未分类线程的详情，通过 ThreadContentClassifier 判定
  /// contentKind 并写入 DB。此阶段不摄入漫画/小说模块，确保
  /// 收藏页在最短时间内显示分类后的列表。
  Future<_DetailFillResult> _lightClassify() async {
    final failedTids = <String>[];
    final failedTidSet = <String>{};
    final errors = <String, String>{};
    var classifiedCount = 0;

    while (true) {
      final records = await _localRepository.getMissingDetailRecords(
        limit: _detailBatchLimit,
        excludedTids: failedTidSet,
      );
      if (records.isEmpty) break;

      var madeProgress = false;
      final failedCountBefore = failedTidSet.length;
      for (final record in records) {
        _emitProgress(
          FavoriteSyncProgress(
            phase: FavoriteSyncProgressPhase.classifying,
            message: '正在快速分类 ${classifiedCount + failedTidSet.length + 1}',
            current: classifiedCount + failedTidSet.length,
          ),
        );
        try {
          final loaded = await _classifyOnly(record);
          if (loaded) {
            classifiedCount++;
            madeProgress = true;
          } else {
            failedTidSet.add(record.tid);
            failedTids.add(record.tid);
            errors[record.tid] = '分类失败';
          }
        } catch (error) {
          failedTidSet.add(record.tid);
          failedTids.add(record.tid);
          errors[record.tid] = '$error';
        }
      }

      if (!madeProgress && failedTidSet.length == failedCountBefore) break;
    }

    return _DetailFillResult(
      loadedCount: classifiedCount,
      failedTids: failedTids,
      errors: errors,
    );
  }

  /// 仅分类一条收藏记录，不摄入模块。
  Future<bool> _classifyOnly(FavoriteThreadCacheRecord record) async {
    final result = await _loadThreadDetail(record.tid);
    if (result is ApiFailure<ThreadDetailData>) return false;

    final detail = result.dataOrNull;
    if (detail == null) return false;

    final tagName = await _findTagName(fid: detail.fid, typeid: detail.typeid);
    final kind = _classifier.classify(
      fid: detail.fid,
      typeid: detail.typeid,
      tagName: tagName,
    );

    await _localRepository.updateThreadDetailMeta(
      tid: record.tid,
      fid: detail.fid,
      typeid: detail.typeid,
      tagName: tagName,
      contentKind: kind,
      workId: null, // 先不关联模块 workId
    );
    return true;
  }

  /// 阶段 B：渐进摄入。
  ///
  /// 按 remote_order ASC（最新收藏在前）逐个处理已分类的漫画/小说
  /// 记录，使用轻量摄入（只做直接解析，不搜索、不提取封面）。
  /// 每 [_ingestNotifyBatchSize] 个发出进度通知 UI 增量刷新。
  Future<_DetailFillResult> _progressiveIngest() async {
    final failedTids = <String>[];
    final errors = <String, String>{};
    var ingestedCount = 0;

    // 获取所有已分类的漫画/小说记录，按 remote_order ASC 排序
    final records = await _localRepository.getClassifiedModuleRecords();
    final totalIngest = records.length;

    if (totalIngest == 0) {
      return _DetailFillResult(
        loadedCount: 0,
        failedTids: const <String>[],
        errors: const <String, String>{},
      );
    }

    for (final record in records) {
      try {
        // 重新加载详情以获取完整帖子数据用于摄入。
        final result = await _loadThreadDetail(record.tid);
        if (result is ApiFailure ||
            result.dataOrNull == null) {
          failedTids.add(record.tid);
          errors[record.tid] = '摄入时加载详情失败';
          continue;
        }
        final detail = result.dataOrNull!;

        final workId = await _syncModuleLight(
          detail: detail,
          kind: record.contentKind,
          tagName: record.sourceTagName,
        );

        // 回填 workId
        await _localRepository.updateThreadWorkId(
          tid: record.tid,
          workId: workId,
        );
        ingestedCount++;

        // 每 N 个或最后一个时发出进度 → 触发 UI 增量刷新。
        if (ingestedCount % _ingestNotifyBatchSize == 0 ||
            ingestedCount == totalIngest) {
          _emitProgress(
            FavoriteSyncProgress(
              phase: FavoriteSyncProgressPhase.ingesting,
              message: '已更新 $ingestedCount/$totalIngest 部作品',
              current: ingestedCount,
              total: totalIngest,
            ),
          );
        }
      } catch (error) {
        failedTids.add(record.tid);
        errors[record.tid] = '$error';
      }
    }

    // 最终刷新确保所有模块 UI 一致。
    if (ingestedCount > 0) {
      _emitProgress(
        FavoriteSyncProgress(
          phase: FavoriteSyncProgressPhase.ingesting,
          message: '已更新 $ingestedCount/$totalIngest 部作品',
          current: ingestedCount,
          total: totalIngest,
        ),
      );
    }

    return _DetailFillResult(
      loadedCount: ingestedCount,
      failedTids: failedTids,
      errors: errors,
    );
  }

  /// 轻量摄入：根据内容类型路由到对应的轻量摄入服务。
  Future<String?> _syncModuleLight({
    required ThreadDetailData detail,
    required ThreadContentKind kind,
    required String? tagName,
  }) async {
    switch (kind) {
      case ThreadContentKind.comic:
        return _comicIngestService.lightUpsertFromThreadDetail(
          detail: detail,
          sourceTagName: tagName,
        );
      case ThreadContentKind.novel:
        return _novelIngestService.lightUpsertFromThreadDetail(
          detail: detail,
          sourceTagName: tagName,
        );
      case ThreadContentKind.unknown:
      case ThreadContentKind.forum:
        return 'thread:${detail.tid}';
    }
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
