import 'dart:async';

import 'package:y300/features/comic/domain/services/comic_services_impl.dart';

enum ComicReaderPreloadPriority {
  retry,
  visible,
  jumpTarget,
  adjacentForward,
  adjacentBackward,
  nextChapter,
}

class ComicReaderPreloadTask {
  const ComicReaderPreloadTask({
    required this.episodeId,
    required this.imageUrl,
    required this.imageIndex,
    required this.cacheKey,
    required this.priority,
    String? storageImageUrl,
    this.ownerId,
    this.lastSourceUrl,
  }) : storageImageUrl = storageImageUrl ?? imageUrl;

  final String episodeId;
  /// URL used for downloading. It may be `lastSourceUrl` when a page source
  /// has changed while the stable database row still keeps the original URL.
  final String imageUrl;
  /// URL used to find the `episode_images` row during metadata writes.
  final String storageImageUrl;
  final int imageIndex;
  final String cacheKey;
  final ComicReaderPreloadPriority priority;
  final String? ownerId;
  final String? lastSourceUrl;

  String get dedupeKey => '$episodeId:$imageIndex';

  ComicReaderPreloadTask copyWith({
    ComicReaderPreloadPriority? priority,
  }) {
    return ComicReaderPreloadTask(
      episodeId: episodeId,
      imageUrl: imageUrl,
      imageIndex: imageIndex,
      cacheKey: cacheKey,
      priority: priority ?? this.priority,
      storageImageUrl: storageImageUrl,
      ownerId: ownerId,
      lastSourceUrl: lastSourceUrl,
    );
  }
}

class ComicReaderPreloadResult {
  const ComicReaderPreloadResult({
    required this.task,
    required this.cacheResult,
  });

  final ComicReaderPreloadTask task;
  final ComicImageCacheResult cacheResult;
}

class ComicReaderPreloadQueueSnapshot {
  const ComicReaderPreloadQueueSnapshot({
    required this.pendingCount,
    required this.runningCount,
    required this.successCount,
    required this.failureCount,
    required this.cancelledCount,
  });

  final int pendingCount;
  final int runningCount;
  final int successCount;
  final int failureCount;
  final int cancelledCount;
}

typedef ComicReaderPreloadRunner = Future<ComicImageCacheResult> Function(
  ComicReaderPreloadTask task,
);
typedef ComicReaderPreloadTaskHandler = Future<void> Function(
  ComicReaderPreloadTask task,
);
typedef ComicReaderPreloadResultHandler = Future<void> Function(
  ComicReaderPreloadResult result,
);
typedef ComicReaderPreloadSnapshotHandler = void Function(
  ComicReaderPreloadQueueSnapshot snapshot,
);

/// Small prioritized preload queue for reader page images.
///
/// The queue deliberately owns only scheduling concerns: priority, dedupe,
/// cancellation and concurrency.  The caller still owns cache implementation,
/// repository metadata writes and UI patching through callbacks.
class ComicReaderPreloadQueue {
  ComicReaderPreloadQueue({
    required ComicReaderPreloadRunner runner,
    ComicReaderPreloadTaskHandler? onStart,
    ComicReaderPreloadResultHandler? onResult,
    ComicReaderPreloadSnapshotHandler? onSnapshot,
    int maxConcurrent = 2,
  })  : _runner = runner,
        _onStart = onStart,
        _onResult = onResult,
        _onSnapshot = onSnapshot,
        _maxConcurrent = maxConcurrent.clamp(1, 4).toInt();

  final ComicReaderPreloadRunner _runner;
  final ComicReaderPreloadTaskHandler? _onStart;
  final ComicReaderPreloadResultHandler? _onResult;
  final ComicReaderPreloadSnapshotHandler? _onSnapshot;
  final int _maxConcurrent;

  final Map<String, ComicReaderPreloadTask> _pendingByKey =
      <String, ComicReaderPreloadTask>{};
  final Map<String, int> _runningByKey = <String, int>{};
  final Set<int> _cancelledRunIds = <int>{};
  bool _disposed = false;
  bool _pumpScheduled = false;
  int _nextRunId = 0;
  int _successCount = 0;
  int _failureCount = 0;
  int _cancelledCount = 0;

  int get _activeRunningCount {
    return _runningByKey.values
        .where((runId) => !_cancelledRunIds.contains(runId))
        .length;
  }

  ComicReaderPreloadQueueSnapshot get snapshot => ComicReaderPreloadQueueSnapshot(
        pendingCount: _pendingByKey.length,
        runningCount: _activeRunningCount,
        successCount: _successCount,
        failureCount: _failureCount,
        cancelledCount: _cancelledCount,
      );

  List<ComicReaderPreloadTask> enqueueAll(
    Iterable<ComicReaderPreloadTask> tasks, {
    bool schedule = true,
  }) {
    if (_disposed) {
      return const <ComicReaderPreloadTask>[];
    }
    final acceptedByKey = <String, ComicReaderPreloadTask>{};
    for (final task in tasks) {
      if (enqueue(task, schedule: false)) {
        acceptedByKey[task.dedupeKey] = task;
      }
    }
    final accepted = acceptedByKey.values.toList(growable: false);
    if (accepted.isNotEmpty) {
      if (schedule) {
        _emitSnapshot();
        _schedulePump();
      }
    }
    return accepted;
  }

  bool enqueue(ComicReaderPreloadTask task, {bool schedule = true}) {
    if (_disposed) {
      return false;
    }
    final key = task.dedupeKey;
    final runningRunId = _runningByKey[key];
    if (runningRunId != null && !_cancelledRunIds.contains(runningRunId)) {
      return false;
    }
    final existing = _pendingByKey[key];
    if (existing != null &&
        _priorityRank(existing.priority) <= _priorityRank(task.priority)) {
      return false;
    }
    _pendingByKey[key] = task;
    if (schedule) {
      _emitSnapshot();
      _schedulePump();
    }
    return true;
  }

  void cancelExcept(Set<String> keepKeys) {
    if (_disposed) {
      return;
    }
    final before = _pendingByKey.length;
    _pendingByKey.removeWhere((key, _) => !keepKeys.contains(key));
    _cancelledCount += before - _pendingByKey.length;
    // Running futures cannot be force-stopped.  Mark only the outdated
    // run ids as cancelled so a kept visible/jump task may still update UI.
    for (final entry in _runningByKey.entries) {
      if (!keepKeys.contains(entry.key) && _cancelledRunIds.add(entry.value)) {
        _cancelledCount++;
      }
    }
    _emitSnapshot();
    _schedulePump();
  }

  void clear() {
    if (_disposed) {
      return;
    }
    _cancelledCount += _pendingByKey.length;
    for (final runId in _runningByKey.values) {
      if (_cancelledRunIds.add(runId)) {
        _cancelledCount++;
      }
    }
    _pendingByKey.clear();
    _emitSnapshot();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    clear();
    _disposed = true;
  }

  void schedule() {
    if (_disposed) {
      return;
    }
    _emitSnapshot();
    _schedulePump();
  }

  void _schedulePump() {
    if (_pumpScheduled || _disposed) {
      return;
    }
    _pumpScheduled = true;
    scheduleMicrotask(() {
      _pumpScheduled = false;
      _pump();
    });
  }

  void _pump() {
    if (_disposed) {
      return;
    }
    while (_activeRunningCount < _maxConcurrent && _pendingByKey.isNotEmpty) {
      final task = _takeNextTask();
      if (task == null) {
        return;
      }
      final key = task.dedupeKey;
      final runId = _nextRunId++;
      _runningByKey[key] = runId;
      _emitSnapshot();
      unawaited(_runTask(task, runId));
    }
  }

  Future<void> _notifyTaskStarted(ComicReaderPreloadTask task) async {
    try {
      await _onStart?.call(task);
    } catch (_) {
      // Preload callbacks are best effort; a UI/database patch must not stop
      // the queue from continuing with later tasks.
    }
  }

  ComicReaderPreloadTask? _takeNextTask() {
    if (_pendingByKey.isEmpty) {
      return null;
    }
    final tasks = _pendingByKey.values.toList(growable: false)
      ..sort(_compareTask);
    final task = tasks.first;
    _pendingByKey.remove(task.dedupeKey);
    return task;
  }

  Future<void> _runTask(
    ComicReaderPreloadTask task,
    int runId,
  ) async {
    if (_finishIfCancelled(task, runId)) {
      return;
    }
    await _notifyTaskStarted(task);
    if (_finishIfCancelled(task, runId)) {
      return;
    }
    ComicImageCacheResult result;
    try {
      result = await _runner(task);
    } catch (_) {
      result = const ComicImageCacheResult(success: false);
    }
    if (_disposed) {
      return;
    }
    final key = task.dedupeKey;
    if (_runningByKey[key] == runId) {
      _runningByKey.remove(key);
    }
    if (_cancelledRunIds.remove(runId)) {
      _emitSnapshot();
      _schedulePump();
      return;
    }

    if (result.success) {
      _successCount++;
    } else {
      _failureCount++;
    }
    try {
      await _onResult?.call(
        ComicReaderPreloadResult(task: task, cacheResult: result),
      );
    } catch (_) {
      // Result callbacks update UI/database metadata and are intentionally
      // isolated from queue scheduling.
    }
    _emitSnapshot();
    _pump();
  }

  bool _finishIfCancelled(ComicReaderPreloadTask task, int runId) {
    if (!_cancelledRunIds.remove(runId)) {
      return false;
    }
    final key = task.dedupeKey;
    if (_runningByKey[key] == runId) {
      _runningByKey.remove(key);
    }
    _emitSnapshot();
    _schedulePump();
    return true;
  }

  void _emitSnapshot() {
    _onSnapshot?.call(snapshot);
  }

  int _compareTask(
    ComicReaderPreloadTask a,
    ComicReaderPreloadTask b,
  ) {
    final priority = _priorityRank(a.priority).compareTo(
      _priorityRank(b.priority),
    );
    if (priority != 0) {
      return priority;
    }
    return a.imageIndex.compareTo(b.imageIndex);
  }

  int _priorityRank(ComicReaderPreloadPriority priority) {
    switch (priority) {
      case ComicReaderPreloadPriority.retry:
        return 0;
      case ComicReaderPreloadPriority.visible:
        return 1;
      case ComicReaderPreloadPriority.jumpTarget:
        return 2;
      case ComicReaderPreloadPriority.adjacentForward:
        return 3;
      case ComicReaderPreloadPriority.adjacentBackward:
        return 4;
      case ComicReaderPreloadPriority.nextChapter:
        return 5;
    }
  }
}
