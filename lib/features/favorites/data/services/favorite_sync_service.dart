import 'package:flutter/foundation.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/features/favorites/data/services/favorite_detail_context_loader.dart';
import 'package:y300/features/favorites/data/services/favorite_detail_filler.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_maintenance.dart';
import 'package:y300/features/favorites/data/services/favorite_snapshot_writer.dart';
import 'package:y300/features/favorites/domain/services/favorite_sync_request_governor.dart';
import 'package:y300/features/favorites/data/repositories/local_favorite_repository.dart';
import 'package:y300/features/favorites/domain/models/favorite_cache_models.dart';
import 'package:y300/features/favorites/domain/models/favorite_content_ingest.dart';
import 'package:y300/features/favorites/domain/services/library_post_ingest_task_runner.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/favorites/data/services/default_favorite_sync_request_governor.dart';

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
    FavoriteSyncRequestGovernor Function()? governorFactory,
  }) : _remoteRepository = remoteRepository,
       _localRepository = localRepository,
       _contentIngestRegistry = contentIngestRegistry,
       _shelfRefreshBus = shelfRefreshBus,
       _detailFiller = FavoriteDetailFiller(
         localRepository: localRepository,
         detailContextLoader: detailContextLoader,
         contentIngestRegistry: contentIngestRegistry,
         postIngestTaskRunner: postIngestTaskRunner,
         batchLimit: detailBatchLimit,
       ),
       _maintenance = FavoriteSyncMaintenance(
         localRepository: localRepository,
         postIngestTaskRunner: postIngestTaskRunner,
         batchLimit: detailBatchLimit,
       ),
       _snapshotWriter = FavoriteSnapshotWriter(
         localRepository: localRepository,
         downloadStorageService: downloadStorageService,
       ),
       _governorFactory =
           governorFactory ?? (() => DefaultFavoriteSyncRequestGovernor());

  final FavoriteThreadDirectoryRepository _remoteRepository;
  final LocalFavoriteRepository _localRepository;
  final FavoriteContentIngestRegistry _contentIngestRegistry;
  final LibraryShelfRefreshBus? _shelfRefreshBus;
  final FavoriteDetailFiller _detailFiller;
  final FavoriteSyncMaintenance _maintenance;
  final FavoriteSnapshotWriter _snapshotWriter;
  final FavoriteSyncRequestGovernor Function() _governorFactory;
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
        const FavoriteSyncProgress(phase: FavoriteSyncProgressPhase.failed),
      );
      await _localRepository.markSyncFailure(error.message);
      throw StateError(error.message);
    } catch (error) {
      _emitProgress(
        const FavoriteSyncProgress(phase: FavoriteSyncProgressPhase.failed),
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
    final detailResult = await _detailFiller.fillMissingDetails(
      context: context,
      onProgress: ({required subject, required current, required total}) {
        _emitProgress(
          FavoriteSyncProgress(
            phase: FavoriteSyncProgressPhase.loadingDetails,
            subject: subject,
            current: current,
            total: total,
          ),
        );
      },
      mergeIngestedComics: !firstFullSync,
      forceComicSearchOnCatalogMissTids: <String>{
        ...forceComicSearchOnCatalogMissTids,
        ...newlySeenTids,
      },
    );
    if (firstFullSync) {
      await _maintenance.mergeAllComicDuplicatesAfterFirstSync();
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
    await _snapshotWriter.write(remoteCount: readSet.totalItems);
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
        preloadedDetail = await _detailFiller.loadTargetDetailOrNull(
          tid,
          context: context,
        );
        if (preloadedDetail != null) {
          upsertedCount += await _detailFiller
              .upsertRecentlyFavoritedThreadFromDetail(
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
        final loaded = await _detailFiller.fillOneDetail(
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
    await _snapshotWriter.write(remoteCount: readSet.totalItems);
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
      kind: FavoriteSyncRequestKind.favoriteListPage,
      action: () => _remoteRepository.load(
        FavoriteThreadDirectoryQuery(page: page),
        cachePolicy: CacheLoadPolicy.networkFirst,
      ),
    );
  }

  Future<void> runBackgroundMaintenanceWithContext({
    required FavoriteSyncExecutionContext context,
  }) => _maintenance.runBackgroundMaintenance(context: context);

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
}

class _FavoriteSyncFailure implements Exception {
  const _FavoriteSyncFailure(this.message);

  final String message;
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
