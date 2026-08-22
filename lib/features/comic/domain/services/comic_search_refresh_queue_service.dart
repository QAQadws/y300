import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:y300/features/comic/data/repositories/comic_search_refresh_queue_repository.dart';
import 'package:y300/features/comic/domain/models/comic_thread_discovery_models.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/search/data/services/forum_search_scheduler.dart';

class ComicSearchRefreshRetryPolicy {
  const ComicSearchRefreshRetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(seconds: 30),
  });

  final int maxAttempts;
  final Duration initialDelay;

  Duration delayForAttempt(int attempts) {
    final multiplier = attempts <= 1 ? 1 : 1 << (attempts - 1);
    return Duration(milliseconds: initialDelay.inMilliseconds * multiplier);
  }
}

abstract class ComicSearchRefreshQueueEnqueuer {
  Future<ComicSearchRefreshEnqueueResult> enqueue({
    required ComicEpisodeRefreshRequest request,
    required String title,
    required ComicSearchRefreshOrigin origin,
    // 内存侧通道：让队列任务复用收藏 ingest 已抓的 ThreadDetailData，
    // 跨入队边界保留，省掉 _discoverCurrentOnly + _searchFallback 在
    // 队列任务内对源 tid 的两次重复 viewthread。
    // 不持久化——冷启动只是回退到原行为，不影响正确性。
    ComicThreadDiscoveryDocument? preloadedRootDetail,
  });
}

abstract class ComicSearchRefreshQueueStateReader {
  ValueListenable<ComicSearchRefreshQueueSnapshot> get snapshot;
}

/// Background worker for comics that missed catalog refresh and must use
/// search/current-only fallback.
///
/// The worker deliberately knows nothing about favorite/detail pages.  It
/// persists queue state, delegates actual search throttling to
/// [ForumSearchScheduler] through [ComicEpisodeRefreshService], and delegates
/// local merge/cover/refresh application to [ComicRefreshOutcomeApplier].
class ComicSearchRefreshQueueService
    implements
        ComicSearchRefreshQueueEnqueuer,
        ComicSearchRefreshQueueStateReader {
  ComicSearchRefreshQueueService({
    required ComicSearchRefreshQueueRepository queueRepository,
    required ComicEpisodeRefreshService refreshService,
    required ComicRefreshOutcomeApplier refreshOutcomeApplier,
    this.cadence = ForumSearchScheduler.defaultInterval,
    ComicSearchRefreshRetryPolicy retryPolicy =
        const ComicSearchRefreshRetryPolicy(),
    DateTime Function()? nowProvider,
  }) : _queueRepository = queueRepository,
       _refreshService = refreshService,
       _refreshOutcomeApplier = refreshOutcomeApplier,
       _retryPolicy = retryPolicy,
       _nowProvider = nowProvider ?? DateTime.now,
       _snapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
         ComicSearchRefreshQueueSnapshot(
           entries: const <ComicSearchRefreshQueueEntry>[],
           cadence: cadence,
         ),
       );

  final ComicSearchRefreshQueueRepository _queueRepository;
  final ComicEpisodeRefreshService _refreshService;
  final ComicRefreshOutcomeApplier _refreshOutcomeApplier;
  final ComicSearchRefreshRetryPolicy _retryPolicy;
  final DateTime Function() _nowProvider;
  final ValueNotifier<ComicSearchRefreshQueueSnapshot> _snapshot;
  final Duration cadence;

  bool _started = false;
  bool _processing = false;
  bool _disposed = false;
  bool _pumpRequested = false;
  Timer? _wakeTimer;
  Future<void>? _pumpFuture;

  // 跨入队边界透传窄化的 discovery document。键是 queue entry id；任务跑完
  // （成功或彻底失败）就清掉。app 重启时丢失没关系——任务会照常跑，
  // 只是少一次缓存命中。
  final Map<int, ComicThreadDiscoveryDocument> _preloadedRootDetails =
      <int, ComicThreadDiscoveryDocument>{};

  @override
  ValueListenable<ComicSearchRefreshQueueSnapshot> get snapshot => _snapshot;

  @override
  Future<ComicSearchRefreshEnqueueResult> enqueue({
    required ComicEpisodeRefreshRequest request,
    required String title,
    required ComicSearchRefreshOrigin origin,
    ComicThreadDiscoveryDocument? preloadedRootDetail,
  }) async {
    final comicId = request.comicId?.trim();
    if (comicId == null || comicId.isEmpty) {
      throw ArgumentError(
        'Comic search refresh queue requires request.comicId',
      );
    }

    final result = await _queueRepository.enqueue(
      ComicSearchRefreshQueueDraft(
        title: title,
        request: request,
        origin: origin,
      ),
      now: _nowProvider(),
    );
    if (preloadedRootDetail != null &&
        preloadedRootDetail.tid == request.sourceTid) {
      _preloadedRootDetails[result.entry.id] = preloadedRootDetail;
    }
    final entries = await _refreshSnapshot();
    final position = _positionOf(result.entry, entries);
    _logQueue(
      'enqueue comicId=$comicId title=$title position=$position '
      'deduplicated=${result.deduplicated}',
    );
    if (!_started) {
      unawaited(start());
    } else {
      _schedulePump();
    }
    return ComicSearchRefreshEnqueueResult(
      entry: result.entry,
      position: position,
      estimatedDuration: Duration(
        milliseconds: cadence.inMilliseconds * position,
      ),
      deduplicated: result.deduplicated,
    );
  }

  Future<void> start() async {
    if (_disposed) {
      return;
    }
    if (!_started) {
      _started = true;
      await _queueRepository.resetRunningToPending(now: _nowProvider());
      await _refreshSnapshot();
    }
    _schedulePump();
  }

  @visibleForTesting
  Future<void> drainForTest() async {
    while (!_disposed) {
      final activePump = _pumpFuture;
      if (activePump != null) {
        await activePump;
      } else {
        await _pump();
      }

      // `_pumpFuture` can be replaced by a follow-up microtask in
      // `whenComplete`. Wait until that trailing scheduled pump also settles,
      // otherwise tests may close the SQLite handle while the worker is still
      // performing its final no-op claim/query pass.
      if (_pumpFuture != null || _processing) {
        continue;
      }

      final entries = await _refreshSnapshot();
      final hasRunning = entries.any(
        (entry) => entry.status == ComicSearchRefreshQueueStatus.running,
      );
      if (!hasRunning && !_hasDuePending(entries)) {
        return;
      }
    }
  }

  void dispose() {
    _disposed = true;
    _pumpRequested = false;
    _wakeTimer?.cancel();
    _preloadedRootDetails.clear();
    _snapshot.dispose();
  }

  void _schedulePump() {
    if (_disposed) {
      return;
    }
    if (_processing || _pumpFuture != null) {
      _pumpRequested = true;
      return;
    }
    _pumpRequested = false;
    late final Future<void> scheduled;
    scheduled = Future<void>.microtask(_pump).whenComplete(() {
      if (identical(_pumpFuture, scheduled)) {
        _pumpFuture = null;
      }
      if (_pumpRequested && !_disposed) {
        _schedulePump();
      }
    });
    _pumpFuture = scheduled;
  }

  Future<void> _pump() async {
    if (_disposed || _processing) {
      return;
    }
    _processing = true;
    _wakeTimer?.cancel();
    try {
      while (!_disposed) {
        final task = await _queueRepository.claimNextPending(
          now: _nowProvider(),
        );
        if (task == null) {
          final entries = await _refreshSnapshot();
          _scheduleWakeFor(entries);
          return;
        }
        if (!_disposed) {
          await _refreshSnapshot();
        }
        await _runTask(task);
        if (_disposed) {
          return;
        }
        await _refreshSnapshot();
      }
    } finally {
      _processing = false;
      // If a new task was enqueued while the pump was between "no due task"
      // and releasing `_processing`, make sure it is not left waiting for a
      // later external trigger.
      if (!_disposed && _snapshot.value.entries.isNotEmpty) {
        if (_hasDuePending(_snapshot.value.entries)) {
          unawaited(
            Future<void>.microtask(() {
              _schedulePump();
            }),
          );
        } else {
          _scheduleWakeFor(_snapshot.value.entries);
        }
      }
    }
  }

  Future<void> _runTask(ComicSearchRefreshQueueEntry task) async {
    _logQueue(
      'run task=${task.id} comicId=${task.comicId} '
      'sourceTid=${task.request.sourceTid}',
    );
    try {
      final preloaded = _preloadedRootDetails[task.id];
      final outcome = await _refreshService.fetchSearchAndCurrentOnly(
        task.request,
        preloadedRootDetail: preloaded,
      );
      if (outcome.hasLinks) {
        final applied = await _refreshOutcomeApplier.apply(
          ComicRefreshApplyRequest(
            comicId: task.comicId,
            sourceTid: task.request.sourceTid,
            links: outcome.links,
            source: outcome.source,
            mutationSource: LibraryMutationSource.comicSearchQueue,
            reason: 'comic_search_refresh_completed',
            catalogUrl: outcome.catalogUrl,
            // 队列任务在 bootstrap 之外执行，没有 governor；threadCache 仍然
            // 透传过去——可能省掉一次封面 viewthread。
            threadCache: outcome.threadCache,
          ),
        );
        _logQueue(
          'done task=${task.id} comicId=${task.comicId} '
          'links=${outcome.links.length} inserted=${applied.insertedCount} '
          'updated=${applied.updatedCount}',
        );
      } else {
        _logQueue('done task=${task.id} comicId=${task.comicId} links=0');
      }
      await _queueRepository.markCompleted(id: task.id, now: _nowProvider());
      _preloadedRootDetails.remove(task.id);
    } catch (error) {
      await _handleFailure(task, error);
    }
  }

  Future<void> _handleFailure(
    ComicSearchRefreshQueueEntry task,
    Object error,
  ) async {
    final attempts = task.attempts + 1;
    final now = _nowProvider();
    final message = error.toString();
    if (attempts >= _retryPolicy.maxAttempts) {
      _logQueue(
        'failed task=${task.id} comicId=${task.comicId} '
        'attempts=$attempts error=$message',
      );
      await _queueRepository.markFailed(
        id: task.id,
        attempts: attempts,
        lastError: message,
        now: now,
      );
      _preloadedRootDetails.remove(task.id);
      return;
    }
    _logQueue(
      'retry task=${task.id} comicId=${task.comicId} '
      'attempts=$attempts error=$message',
    );
    await _queueRepository.markRetry(
      id: task.id,
      attempts: attempts,
      lastError: message,
      availableAt: now.add(_retryPolicy.delayForAttempt(attempts)),
      now: now,
    );
  }

  Future<List<ComicSearchRefreshQueueEntry>> _refreshSnapshot() async {
    if (_disposed) {
      return const <ComicSearchRefreshQueueEntry>[];
    }
    final entries = await _queueRepository.loadActiveEntries();
    if (_disposed) {
      return entries;
    }
    _snapshot.value = ComicSearchRefreshQueueSnapshot(
      entries: entries,
      cadence: cadence,
    );
    return entries;
  }

  int _positionOf(
    ComicSearchRefreshQueueEntry target,
    List<ComicSearchRefreshQueueEntry> entries,
  ) {
    final index = entries.indexWhere((entry) => entry.id == target.id);
    return index < 0 ? entries.length : index + 1;
  }

  bool _hasDuePending(List<ComicSearchRefreshQueueEntry> entries) {
    return entries.any((entry) {
      return entry.status == ComicSearchRefreshQueueStatus.pending &&
          !entry.availableAt.isAfter(_nowProvider());
    });
  }

  void _scheduleWakeFor(List<ComicSearchRefreshQueueEntry> entries) {
    final now = _nowProvider();
    DateTime? nextAvailableAt;
    for (final entry in entries) {
      if (entry.status != ComicSearchRefreshQueueStatus.pending) {
        continue;
      }
      if (nextAvailableAt == null ||
          entry.availableAt.isBefore(nextAvailableAt)) {
        nextAvailableAt = entry.availableAt;
      }
    }
    if (nextAvailableAt == null) {
      return;
    }
    final wait = nextAvailableAt.isAfter(now)
        ? nextAvailableAt.difference(now)
        : Duration.zero;
    _wakeTimer = Timer(wait, _schedulePump);
  }

  void _logQueue(String message) {
    if (kReleaseMode) {
      return;
    }
    debugPrint('[ComicSearchQueue] $message');
  }
}
