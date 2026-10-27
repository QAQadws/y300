import 'package:flutter/foundation.dart';
import 'package:y300/features/thread/domain/thread_content_classifier.dart';
import 'package:y300/features/favorites/data/services/favorite_execution_queue.dart';
import 'package:y300/features/favorites/data/services/favorite_detail_scheduler.dart';
import 'package:y300/features/favorites/data/services/favorite_membership_tracker.dart';
import 'package:y300/features/favorites/data/services/favorite_sync_progress.dart';
import 'package:y300/features/favorites/data/services/favorite_snapshot_publication.dart';
import 'package:y300/features/favorites/domain/services/favorite_parse_service.dart';
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

export 'favorite_sync_progress.dart'
    show FavoriteSyncProgress, FavoriteSyncProgressPhase;

typedef _FavoriteDirectoryRead =
    DataReadSuccess<
      FavoriteThreadDirectoryData,
      FavoriteThreadDirectoryReadCapabilities
    >;

abstract class FavoriteSyncService {
  Future<FavoriteSyncResult> sync();

  Future<FavoriteSyncResult> syncRecentlyAddedThread({required String tid});

  Future<void> runBackgroundMaintenance();

  ValueListenable<FavoriteSyncProgress> get progress;
}

class NetworkFavoriteSyncService
    implements
        FavoriteSyncService,
        FavoriteThreadParseExecutor,
        FavoriteParseQueueObserver {
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
    Object? Function()? readOwner,
  }) : _readOwner = readOwner,
       _remoteRepository = remoteRepository,
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
  final FavoriteSyncProgressTracker _progressState =
      FavoriteSyncProgressTracker();
  final FavoriteSnapshotPublication _publications =
      FavoriteSnapshotPublication();
  Future<FavoriteSyncResult>? _inflightSync;
  final Map<String, Future<FavoriteSyncResult>> _inflightRecentAdds = {};
  Future<void> _operationTail = Future<void>.value();
  Object? _roundOwner;
  Future<void>? _maintenanceFlight;
  Object? _maintenanceOwner;
  int _detailRevision = 0;
  final Map<String, int> _detailVersions = {};
  final Object? Function()? _readOwner;
  final FavoriteExecutionQueue _execution = FavoriteExecutionQueue();
  final FavoriteMembershipTracker _membership = FavoriteMembershipTracker();
  late final FavoriteDetailScheduler _details = FavoriteDetailScheduler(
    _execution,
    _executeDetail,
    resultCovers: (current, requested, readStarted) async {
      if (!_ownerIsCurrent(current.owner)) return false;
      final record = await _localRepository.getActiveThreadByTid(
        current.target.tid,
      );
      return _ownerIsCurrent(current.owner) &&
          record != null &&
          record.contentKind != ThreadContentKind.comic &&
          current.covers(
            requested,
            readStarted: readStarted,
            comicOptions: false,
          );
    },
  );
  Object? _progressOwner;
  late final FavoriteSyncRequestGovernor _requestGovernor = _governorFactory();

  @override
  ValueListenable<FavoriteSyncProgress> get progress => _progressState.notifier;

  void resetOwnerProgress() {
    _progressOwner = _readOwner?.call();
    _detailRevision = 0;
    _detailVersions.clear();
    _progressState.reset();
  }

  void _prepareProgressOwner() {
    if (_readOwner?.call() != _progressOwner) resetOwnerProgress();
  }

  @override
  void updateQueueStatus(
    FavoriteParseQueueStatus status, {
    required bool Function() isCurrent,
  }) {
    if (isCurrent()) _progressState.queue(status);
  }

  @override
  Future<void> waitForPendingOperations() => _execution.settled;

  @override
  void noteMembershipChange(
    Set<String> tids, {
    required bool favorited,
    String? remoteFavoriteId,
    bool onlyIfUnknown = false,
  }) {
    _membership.record(
      _readOwner?.call(),
      tids,
      favorited: favorited,
      id: remoteFavoriteId,
      onlyIfUnknown: onlyIfUnknown,
    );
    if (!favorited) _progressState.forgetDetails(tids);
  }

  @override
  bool isUnfavorited(String tid) =>
      _membership.isUnfavorited(_readOwner?.call(), tid);

  bool _ownerIsCurrent(Object? owner) {
    try {
      return _readOwner?.call() == owner;
    } catch (_) {
      return false;
    }
  }

  void _checkOwner(Object? owner) {
    if (!_ownerIsCurrent(owner)) {
      try {
        _prepareProgressOwner();
      } catch (_) {
        // A disposed Host may no longer expose its current owner.
      }
      throw const _FavoriteOwnerRetired();
    }
  }

  @override
  Future<void> parseThread(
    FavoriteParseTarget target, {
    required Future<bool> Function() isCurrent,
  }) async {
    final owner = _readOwner?.call();
    _prepareProgressOwner();
    _progressState.beginForeground(target.tid);
    try {
      final loaded = await _details.request(
        FavoriteDetailWork(
          target: target,
          owner: owner,
          context: FavoriteSyncExecutionContext.manualRecentAdd(
            governor: _requestGovernor,
          ),
          isCurrent: isCurrent,
          foreground: true,
          forceRead: true,
          forceSearch: true,
          membershipRevision: _membership.versionFor(owner, target.tid),
        ),
      );
      if (!loaded) throw StateError('favorite_parse_detail_failed');
      await _publications.request(
        owner,
        () => _execution.run(() async {
          _checkOwner(owner);
          final snapshot = await _localRepository.getSyncSnapshot();
          _checkOwner(owner);
          await _snapshotWriter.write(
            remoteCount:
                snapshot?.remoteCount ??
                await _localRepository.countActiveThreads(),
          );
          _checkOwner(owner);
          _notifyFavoriteShelfChanged(
            reason: 'favorite_single_parse_completed',
            detailLoadedCount: 1,
          );
        }),
      );
    } finally {
      if (_ownerIsCurrent(owner)) _progressState.endForeground(target.tid);
    }
  }

  Future<bool> _executeDetail(
    FavoriteDetailWork work,
    void Function() onReadStarted,
  ) async {
    bool? succeeded;
    try {
      succeeded = await _executeDetailInternal(work, onReadStarted);
      return succeeded;
    } catch (_) {
      if (_ownerIsCurrent(work.owner) &&
          !_membership.isUnfavorited(work.owner, work.target.tid) &&
          await work.isCurrent()) {
        succeeded = false;
      }
      rethrow;
    } finally {
      if (_ownerIsCurrent(work.owner)) {
        if (succeeded == true) {
          _detailVersions[work.target.tid] = ++_detailRevision;
        }
        _progressState.detailSettled(work.target.tid, succeeded: succeeded);
      }
    }
  }

  Future<bool> _executeDetailInternal(
    FavoriteDetailWork work,
    void Function() onReadStarted,
  ) async {
    Future<void> check() async {
      _checkOwner(work.owner);
      if (!await work.isCurrent()) throw StateError('favorite_parse_retired');
      _checkOwner(work.owner);
    }

    await check();
    if (_membership.isUnfavorited(work.owner, work.target.tid)) {
      if (!work.foreground) return true;
      throw StateError('favorite_parse_target_unfavorited');
    }
    if (!work.foreground &&
        _membership.versionFor(work.owner, work.target.tid) !=
            work.membershipRevision) {
      return true;
    }
    var record = await _localRepository.getActiveThreadByTid(work.target.tid);
    if (work.target.confirmed) {
      await check();
      await _localRepository.upsertRemoteThreads([
        FavoriteThreadCacheUpsert(
          tid: work.target.tid,
          title: record?.title ?? work.target.title ?? work.target.tid,
          replyCount: record?.replyCount ?? 0,
          remoteFavoriteId:
              _membership.versionFor(work.owner, work.target.tid) > 0
              ? _membership.favoriteId(work.owner, work.target.tid) ??
                    record?.remoteFavoriteId
              : work.target.remoteFavoriteId ?? record?.remoteFavoriteId,
          description: record?.description,
          authorName: record?.authorName,
          favoritedAt: record?.favoritedAt,
          remoteOrder: record?.remoteOrder,
        ),
      ]);
      record = await _localRepository.getActiveThreadByTid(work.target.tid);
    }
    if (record == null) {
      if (!work.foreground) return true;
      throw StateError('favorite_parse_target_inactive');
    }
    await check();
    final repository = _localRepository;
    if (!work.forceRead && !record.needsDetail) {
      final usable = repository is FavoriteDetailReadinessRepository
          ? await (repository as FavoriteDetailReadinessRepository)
                .hasUsableDetail(record)
          : true;
      await check();
      if (usable) return true;
    }
    _progressState.detail(record.tid, record.title);
    onReadStarted();
    return _detailFiller.fillOneDetail(
      record,
      context: work.context,
      mergeIngestedComics: work.mergeComics,
      forceComicSearchOnCatalogMiss: work.forceSearch,
      preloadedDetail: work.preloadedDetail,
      isCurrent: () async {
        await check();
        return true;
      },
    );
  }

  @override
  Future<void> runBackgroundMaintenance() => _runMaintenance(
    FavoriteSyncExecutionContext.automaticResume(governor: _requestGovernor),
    _readOwner?.call(),
  );

  Future<void> _runMaintenance(
    FavoriteSyncExecutionContext context,
    Object? owner, {
    int? detailRevision,
  }) {
    final existing = _maintenanceFlight;
    if (existing != null && _maintenanceOwner == owner) return existing;
    _maintenanceOwner = owner;
    final since = detailRevision ?? _detailRevision;
    late final Future<void> future;
    future = _maintenance
        .runBackgroundMaintenance(
          context: context,
          shouldContinue: () => _ownerIsCurrent(owner),
          wasRefreshed: (tid) => (_detailVersions[tid] ?? 0) > since,
          runStep: (action) => _execution.run(() async {
            _checkOwner(owner);
            await action();
            _checkOwner(owner);
          }, priority: FavoriteWorkPriority.maintenance),
        )
        .whenComplete(() {
          if (identical(_maintenanceFlight, future)) _maintenanceFlight = null;
        });
    _maintenanceFlight = future;
    return future;
  }

  @override
  Future<FavoriteSyncResult> sync() async {
    final existing = _inflightSync;
    if (existing != null) {
      return existing;
    }
    late final Future<FavoriteSyncResult> future;
    future =
        _enqueueSync(() async {
          final snapshot = await _localRepository.getSyncSnapshot();
          final context =
              snapshot == null ||
                  (snapshot.requiresFullSync &&
                      snapshot.lastFullSyncedAt == null)
              ? FavoriteSyncExecutionContext.bootstrapInitial(
                  governor: _requestGovernor,
                )
              : FavoriteSyncExecutionContext.automaticResume(
                  governor: _requestGovernor,
                );
          // Coalesce all changes seen by this round into one follow-up. A
          // continuously changing or lagging directory stays retryable rather
          // than causing an unbounded scan loop.
          var result = await _syncInternal(context: context);
          if (result.needsReconciliation) {
            _checkOwner(_roundOwner);
            result = (await _syncInternal(context: context)).after(result);
          }
          return result;
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
    final existing = _inflightRecentAdds[normalizedTid];
    if (existing != null) {
      return existing;
    }
    late final Future<FavoriteSyncResult> future;
    future =
        _enqueueSync(() async {
          final snapshot = await _localRepository.getSyncSnapshot();
          final context = FavoriteSyncExecutionContext.manualRecentAdd(
            governor: _requestGovernor,
          );
          if (snapshot == null || snapshot.requiresFullSync) {
            // Rebuild an absent or interrupted baseline, while still forcing
            // this explicit target through detail loading and comic discovery.
            return _syncInternal(
              context: context,
              forceComicSearchOnCatalogMissTids: <String>{normalizedTid},
              forceDetailTids: <String>{normalizedTid},
            );
          }
          return _enqueueOperation(
            () => _syncRecentlyAddedThreadInternal(
              normalizedTid,
              context: context,
            ),
          );
        }).whenComplete(() {
          if (identical(_inflightRecentAdds[normalizedTid], future)) {
            _inflightRecentAdds.remove(normalizedTid);
          }
        });
    _inflightRecentAdds[normalizedTid] = future;
    return future;
  }

  Future<T> _enqueueOperation<T>(Future<T> Function() body) =>
      _execution.run(body);

  Future<FavoriteSyncResult> _enqueueSync(
    Future<FavoriteSyncResult> Function() body,
  ) {
    // Rounds remain serialized, but no round holds the execution slot while
    // waiting for detail tasks from the same queue.
    final owner = _readOwner?.call();
    _prepareProgressOwner();
    _progressState.beginRound();
    final operation = _operationTail.then((_) async {
      try {
        _checkOwner(owner);
        _roundOwner = owner;
        return await _runSync(body);
      } finally {
        if (_ownerIsCurrent(owner)) _progressState.endRound();
      }
    });
    _operationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<FavoriteSyncResult> _runSync(
    Future<FavoriteSyncResult> Function() body,
  ) async {
    try {
      final result = await body();
      _checkOwner(_roundOwner);
      _emitProgress(
        const FavoriteSyncProgress(phase: FavoriteSyncProgressPhase.completed),
      );
      return result;
    } on _FavoriteOwnerRetired {
      rethrow;
    } on _FavoriteSyncFailure catch (error) {
      _checkOwner(_roundOwner);
      _emitProgress(
        const FavoriteSyncProgress(phase: FavoriteSyncProgressPhase.failed),
      );
      await _localRepository.markSyncFailure(error.message);
      throw StateError(error.message);
    } catch (error) {
      _checkOwner(_roundOwner);
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
    Set<String> forceDetailTids = const <String>{},
  }) async {
    final owner = _roundOwner;
    _checkOwner(owner);
    final plan = await _readDirectory(context, owner);
    final maintenanceRevision = _detailRevision;
    final searches = {
      ...forceComicSearchOnCatalogMissTids,
      ...plan.newlySeenTids,
    };
    final failedInRound = <String>{};
    _progressState.automaticRemaining(
      await _localRepository.countMissingDetailRecords(),
    );
    final detailResult = await _detailFiller.fillMissingDetails(
      context: context,
      shouldContinue: () => _ownerIsCurrent(owner),
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
      mergeIngestedComics: !plan.firstFullSync,
      forceDetailTids: forceDetailTids,
      forceComicSearchOnCatalogMissTids: searches,
      execute: (record, preloaded) async {
        try {
          final loaded = await _details.request(
            FavoriteDetailWork(
              target: FavoriteParseTarget(tid: record.tid),
              owner: owner,
              context: context,
              isCurrent: () async => _ownerIsCurrent(owner),
              forceRead: forceDetailTids.contains(record.tid),
              forceSearch: searches.contains(record.tid),
              mergeComics: !plan.firstFullSync,
              membershipRevision: _membership.versionFor(owner, record.tid),
              preloadedDetail: preloaded,
            ),
          );
          if (!loaded) failedInRound.add(record.tid);
          return loaded;
        } catch (_) {
          failedInRound.add(record.tid);
          rethrow;
        } finally {
          if (_ownerIsCurrent(owner)) {
            try {
              _progressState.automaticRemaining(
                await _localRepository.countMissingDetailRecords() -
                    failedInRound.length,
              );
            } catch (_) {
              // Progress observation cannot turn a committed detail into a failure.
            }
          }
        }
      },
    );
    await _runMaintenance(context, owner, detailRevision: maintenanceRevision);
    var changed = false;
    await _enqueueOperation(() async {
      _checkOwner(owner);
      changed =
          plan.hasConflict || _membership.revision != plan.membershipRevision;
      if (plan.firstFullSync && !changed) {
        await _maintenance.mergeAllComicDuplicatesAfterFirstSync();
      }
      _checkOwner(owner);
      _emitProgress(
        const FavoriteSyncProgress(phase: FavoriteSyncProgressPhase.finishing),
      );
      changed = changed || _membership.revision != plan.membershipRevision;
      _progressState.reconciliation(changed);
      if (changed) {
        await _localRepository.markSyncFailure(
          'favorite_directory_membership_changed',
        );
      } else {
        await _localRepository.finishSync(
          mode: plan.mode,
          remoteCount: plan.readSet.totalItems,
          status: detailResult.failedTids.isEmpty ? 'ok' : 'partial',
          message: detailResult.failedTids.isEmpty
              ? null
              : _buildPartialFailureMessage(detailResult.errors),
        );
        _membership.acknowledge(owner, plan.membershipRevision);
        await _snapshotWriter.write(remoteCount: plan.readSet.totalItems);
      }
      _checkOwner(owner);
      _notifyFavoriteShelfChanged(
        reason: 'favorite_sync_completed',
        upsertedCount: plan.upsertedCount,
        removedCount: plan.removedRecords.length,
        detailLoadedCount: detailResult.loadedCount,
      );
    });
    return FavoriteSyncResult(
      mode: plan.mode,
      remoteCount: plan.readSet.totalItems,
      fetchedPages: plan.fetchedPages,
      upsertedCount: plan.upsertedCount,
      removedRecords: plan.removedRecords,
      detailLoadedCount: detailResult.loadedCount,
      failedDetailTids: detailResult.failedTids,
      directoryCapabilities: plan.readSet.capabilities,
      directoryMetadata: plan.readSet.metadata,
      needsReconciliation: changed,
    );
  }

  Future<_FavoriteDirectoryPlan> _readDirectory(
    FavoriteSyncExecutionContext context,
    Object? owner,
  ) async {
    _checkOwner(owner);
    final membershipRevision = _membership.revision;
    _emitProgress(
      const FavoriteSyncProgress(
        phase: FavoriteSyncProgressPhase.fetchingList,
        current: 0,
      ),
    );
    Future<_FavoriteDirectoryRead> loadPage(int page) =>
        _execution.run(() async {
          _checkOwner(owner);
          final result = await _readDirectoryPage(context, page);
          _checkOwner(owner);
          return result;
        });
    final firstRead = await loadPage(1);
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
    final mode = _membership.hasUnacknowledged(owner)
        ? FavoriteSyncMode.fullDiff
        : _resolveSyncMode(
            firstPage: firstPage,
            activeBefore: activeBefore,
            snapshot: snapshot,
          );

    final reads = <_FavoriteDirectoryRead>[firstRead];
    if (mode == FavoriteSyncMode.fullDiff) {
      reads.addAll(
        await _fetchRemainingPages(
          firstRead,
          context: context,
          loadPage: loadPage,
        ),
      );
    } else {
      reads.addAll(
        await _fetchIncrementalPages(
          firstPage: firstRead,
          activeBefore: activeBefore,
          context: context,
          loadPage: loadPage,
        ),
      );
    }
    final readSet = _validateReadSet(reads, mode: mode);
    final pages = reads.map((read) => read.data).toList(growable: false);
    // No page mutates the shelf before the complete read set is validated.
    // Applying the validated set remains one stable execution unit.
    return _execution.run(() async {
      _checkOwner(owner);
      final remoteIds = <String, String?>{
        for (final page in pages)
          for (final row in _cacheUpsertsFor(page))
            row.tid: row.remoteFavoriteId,
      };
      _membership.observeDirectory(
        owner,
        membershipRevision,
        remoteIds,
        complete: mode == FavoriteSyncMode.fullDiff,
      );
      final hasConflict = _membership.conflicts(owner, remoteIds);
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
        _checkOwner(owner);
        upsertedCount += await _localRepository.upsertRemoteThreads(
          _cacheUpsertsFor(page)
              .where(
                (row) => !_membership.blocksRemote(
                  owner,
                  row.tid,
                  row.remoteFavoriteId,
                  membershipRevision,
                ),
              )
              .toList(),
        );
      }

      _checkOwner(owner);
      final removedRecords =
          mode == FavoriteSyncMode.fullDiff &&
              _membership.revision == membershipRevision &&
              !hasConflict
          ? await _localRepository.markRemovedTids(remoteTids)
          : const <FavoriteThreadCacheRecord>[];
      await _removeModuleShelfItems(removedRecords);

      final firstFullSync =
          mode == FavoriteSyncMode.fullDiff &&
          (snapshot == null ||
              (snapshot.requiresFullSync && snapshot.lastFullSyncedAt == null));
      _checkOwner(owner);
      return _FavoriteDirectoryPlan(
        mode: mode,
        firstFullSync: firstFullSync,
        newlySeenTids: mode == FavoriteSyncMode.incremental
            ? remoteTids.difference(activeBefore)
            : const <String>{},
        readSet: readSet,
        fetchedPages: pages.length,
        upsertedCount: upsertedCount,
        removedRecords: removedRecords,
        membershipRevision: membershipRevision,
        hasConflict: hasConflict,
      );
    });
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
    if (snapshot == null || snapshot.requiresFullSync) {
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
    // An interrupted commit can leave a known first page but a missing tail.
    // Incremental scanning would stop immediately and preserve that gap.
    if (pageOneAllKnown && totalItems != activeBefore.length) {
      return FavoriteSyncMode.fullDiff;
    }
    if (totalItems == snapshot.localActiveCount && !pageOneAllKnown) {
      return FavoriteSyncMode.fullDiff;
    }

    return FavoriteSyncMode.incremental;
  }

  Future<List<_FavoriteDirectoryRead>> _fetchRemainingPages(
    _FavoriteDirectoryRead firstPage, {
    required FavoriteSyncExecutionContext context,
    Future<_FavoriteDirectoryRead> Function(int)? loadPage,
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
      current =
          await (loadPage?.call(nextPageNumber) ??
              _readDirectoryPage(context, nextPageNumber));
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
    Future<_FavoriteDirectoryRead> Function(int)? loadPage,
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
      current =
          await (loadPage?.call(nextPageNumber) ??
              _readDirectoryPage(context, nextPageNumber));
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
    _progressState.forgetDetails(records.map((record) => record.tid).toSet());
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
    _progressState.round(progress);
  }

  Future<_FavoriteDirectoryRead> _readDirectoryPage(
    FavoriteSyncExecutionContext context,
    int page,
  ) async {
    final result = await _runFavoriteListRequest(context: context, page: page);
    if (result
        case final DataReadFailure<
              FavoriteThreadDirectoryData,
              FavoriteThreadDirectoryReadCapabilities
            >
            failure) {
      throw _FavoriteSyncFailure(failure.diagnosticMessage);
    }
    return result as _FavoriteDirectoryRead;
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
  }) => _runMaintenance(context, _readOwner?.call());

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

class _FavoriteOwnerRetired implements Exception {
  const _FavoriteOwnerRetired();
}

class _FavoriteDirectoryPlan {
  const _FavoriteDirectoryPlan({
    required this.mode,
    required this.firstFullSync,
    required this.newlySeenTids,
    required this.readSet,
    required this.fetchedPages,
    required this.upsertedCount,
    required this.removedRecords,
    required this.membershipRevision,
    required this.hasConflict,
  });
  final FavoriteSyncMode mode;
  final bool firstFullSync;
  final bool hasConflict;
  final Set<String> newlySeenTids;
  final _FavoriteDirectoryReadSet readSet;
  final int fetchedPages, upsertedCount, membershipRevision;
  final List<FavoriteThreadCacheRecord> removedRecords;
}
