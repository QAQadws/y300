import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/data/comic_search_refresh_queue_repository.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/library_shared/domain/models/library_models.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/search/data/forum_search_scheduler.dart';

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
  });
}

/// Background worker for comics that missed catalog refresh and must use
/// search/current-only fallback.
///
/// The worker deliberately knows nothing about favorite/detail pages.  It
/// persists queue state, delegates actual search throttling to
/// [ForumSearchScheduler] through [ComicEpisodeRefreshService], and emits a
/// shared shelf refresh signal after local data changes.
class ComicSearchRefreshQueueService implements ComicSearchRefreshQueueEnqueuer {
  ComicSearchRefreshQueueService({
    required ComicSearchRefreshQueueRepository queueRepository,
    required ComicRepository comicRepository,
    required ComicEpisodeRefreshService refreshService,
    required ComicFirstEpisodeCoverPromoter firstEpisodeCoverPromoter,
    required LibraryShelfRefreshBus shelfRefreshBus,
    this.cadence = ForumSearchScheduler.defaultInterval,
    ComicSearchRefreshRetryPolicy retryPolicy =
        const ComicSearchRefreshRetryPolicy(),
    DateTime Function()? nowProvider,
  })  : _queueRepository = queueRepository,
        _comicRepository = comicRepository,
        _refreshService = refreshService,
        _firstEpisodeCoverPromoter = firstEpisodeCoverPromoter,
        _shelfRefreshBus = shelfRefreshBus,
        _retryPolicy = retryPolicy,
        _nowProvider = nowProvider ?? DateTime.now,
        _snapshot = ValueNotifier<ComicSearchRefreshQueueSnapshot>(
          ComicSearchRefreshQueueSnapshot(
            entries: const <ComicSearchRefreshQueueEntry>[],
            cadence: cadence,
          ),
        );

  final ComicSearchRefreshQueueRepository _queueRepository;
  final ComicRepository _comicRepository;
  final ComicEpisodeRefreshService _refreshService;
  final ComicFirstEpisodeCoverPromoter _firstEpisodeCoverPromoter;
  final LibraryShelfRefreshBus _shelfRefreshBus;
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

  ValueListenable<ComicSearchRefreshQueueSnapshot> get snapshot => _snapshot;

  @override
  Future<ComicSearchRefreshEnqueueResult> enqueue({
    required ComicEpisodeRefreshRequest request,
    required String title,
    required ComicSearchRefreshOrigin origin,
  }) async {
    final comicId = request.comicId?.trim();
    if (comicId == null || comicId.isEmpty) {
      throw ArgumentError('Comic search refresh queue requires request.comicId');
    }

    final result = await _queueRepository.enqueue(
      ComicSearchRefreshQueueDraft(
        title: title,
        request: request,
        origin: origin,
      ),
      now: _nowProvider(),
    );
    final entries = await _refreshSnapshot();
    final position = _positionOf(result.entry, entries);
    if (!_started) {
      unawaited(start());
    } else {
      _schedulePump();
    }
    return ComicSearchRefreshEnqueueResult(
      entry: result.entry,
      position: position,
      estimatedDuration: Duration(milliseconds: cadence.inMilliseconds * position),
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
    _wakeTimer?.cancel();
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
        final task = await _queueRepository.claimNextPending(now: _nowProvider());
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
          unawaited(Future<void>.microtask(() {
            _schedulePump();
          }));
        } else {
          _scheduleWakeFor(_snapshot.value.entries);
        }
      }
    }
  }

  Future<void> _runTask(ComicSearchRefreshQueueEntry task) async {
    try {
      final outcome = await _refreshService.fetchSearchAndCurrentOnly(task.request);
      if (outcome.hasLinks) {
        await _comicRepository.mergeEpisodesFromLinks(
          comicId: task.comicId,
          episodeLinks: outcome.links,
          fallbackSourceTid: task.request.sourceTid,
        );
        await _firstEpisodeCoverPromoter.promoteIfPossible(comicId: task.comicId);
        _shelfRefreshBus.notify(
          modules: const <LibraryModuleKey>{
            LibraryModuleKey.comic,
            LibraryModuleKey.favorite,
          },
          reason: 'comic_search_refresh_completed',
        );
      }
      await _queueRepository.markCompleted(
        id: task.id,
        now: _nowProvider(),
      );
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
      await _queueRepository.markFailed(
        id: task.id,
        attempts: attempts,
        lastError: message,
        now: now,
      );
      return;
    }
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
      if (nextAvailableAt == null || entry.availableAt.isBefore(nextAvailableAt)) {
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
}
