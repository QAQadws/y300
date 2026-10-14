import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

import '../thread_detail_prepared_body.dart';

/// One page shares a preparation across its mounted misses for the same input.
/// Completed consumers keep only their requested chunk; the full document is
/// transient even when the active chunks exceed the pure-value cache capacity.
final class ThreadBodyChunkPreparation extends ChangeNotifier {
  ThreadBodyChunkPreparation(
    this.store, {
    ForumHtmlPreparationExecutor? executor,
  }) : _executor = executor;

  final ThreadDetailPreparedBodyStore store;
  final ForumHtmlPreparationExecutor? _executor;
  final _demands = HashMap<Object, _ChunkDemand>.identity();
  final _jobs = <String, _ChunkPreparationJob>{};
  bool _closed = false;
  bool _notificationScheduled = false;
  int _notificationGeneration = 0;

  /// [consumer] belongs to a single mounted chunk and must be released on exit.
  /// Failures remain retryable without changing the manifest or list entries.
  ThreadDetailPreparedChunk? resolve(
    Object consumer,
    ThreadDetailBodyManifest manifest,
    int ordinal,
  ) {
    if (_closed) throw StateError('Chunk preparation is closed');
    retainCurrent();
    final previous = _demands[consumer];
    if (previous != null &&
        (!identical(previous.manifest, manifest) ||
            previous.ordinal != ordinal)) {
      release(consumer);
    }
    if (!store.isCurrent(manifest)) {
      release(consumer);
      return null;
    }
    RangeError.checkValidIndex(ordinal, manifest.chunks, 'ordinal');
    final demand = _demands.putIfAbsent(
      consumer,
      () => _ChunkDemand(manifest, ordinal),
    );
    final chunk = demand.chunk ?? store.chunkFor(manifest, ordinal);
    if (chunk != null) {
      demand.chunk = chunk;
      _detach(demand);
      return chunk;
    }

    final job = _join(demand);
    _poll(job);
    if (job.error != null) {
      Error.throwWithStackTrace(job.error!, job.stack!);
    }
    return demand.chunk;
  }

  Object? errorFor(Object consumer) => _demands[consumer]?.job?.error;
  bool hasError(Object consumer) => errorFor(consumer) != null;

  /// Retrying one failed chunk restarts its manifest's shared active misses.
  void retry(ThreadDetailBodyManifest manifest) {
    if (_closed || !store.isCurrent(manifest)) return;
    final pending = _demands.values
        .where(
          (demand) =>
              identical(demand.manifest, manifest) && demand.chunk == null,
        )
        .toList();
    if (pending.isEmpty) return;
    final old = _jobs[manifest.request.sourceId];
    if (old != null && identical(old.manifest, manifest)) _retire(old);
    for (final demand in pending) {
      _join(demand);
    }
    _poll(_jobs[manifest.request.sourceId]!);
    _notifyLater();
  }

  void release(Object consumer) {
    final demand = _demands.remove(consumer);
    if (demand != null) _detach(demand);
  }

  /// Input replacement retires leases by manifest object, including A -> B -> A.
  void retainCurrent() {
    for (final consumer in _demands.keys.toList()) {
      if (!store.isCurrent(_demands[consumer]!.manifest)) release(consumer);
    }
  }

  /// Reusable for a new page owner; [dispose] permanently closes this service.
  void clear() {
    _notificationGeneration++;
    _notificationScheduled = false;
    _demands.clear();
    for (final job in _jobs.values.toList()) {
      _retire(job);
    }
  }

  _ChunkPreparationJob _join(_ChunkDemand demand) {
    var job = _jobs[demand.manifest.request.sourceId];
    if (job != null && !identical(job.manifest, demand.manifest)) {
      _retire(job);
      job = null;
    }
    job ??= _jobs[demand.manifest.request.sourceId] = _ChunkPreparationJob(
      demand.manifest,
    );
    demand.job = job;
    job.demands.add(demand);
    return job;
  }

  bool _isCurrent(_ChunkPreparationJob job) =>
      !_closed &&
      !job.retired &&
      identical(_jobs[job.manifest.request.sourceId], job) &&
      store.isCurrent(job.manifest) &&
      job.demands.isNotEmpty;

  void _poll(_ChunkPreparationJob job) {
    if (!_isCurrent(job)) {
      _retire(job);
      return;
    }
    if (job.error != null) return;
    var controller = job.controller;
    if (controller == null) {
      controller = ForumHtmlPreparationController(executor: _executor);
      job.controller = controller;
      job.changed = () => _poll(job);
      controller.addListener(job.changed!);
    }
    try {
      final document = controller.resolve(job.manifest.request);
      if (document == null) return;
      final prepared = ThreadDetailPreparedBody(
        request: job.manifest.request,
        document: document,
      );
      if (!store.rememberPrepared(
        job.manifest,
        prepared,
        seedOrdinal: job.demands.first.ordinal,
      )) {
        throw StateError('Prepared chunks no longer match their manifest');
      }
      // Validate the entire output once, then hand every active consumer its
      // chunk directly. A small LRU must not cause active misses to chase it.
      final chunks = document.safeDisplayPlan!.chunks;
      for (final demand in job.demands) {
        final chunk = chunks[demand.ordinal];
        demand.chunk = ThreadDetailPreparedChunk(
          document: document.copyWith(
            preparedHtml: chunk.html,
            clearSafeDisplayPlan: true,
          ),
          ordinal: chunk.ordinal,
          hasTrailingContent: chunk.hasTrailingContent,
        );
      }
      _retire(job);
    } catch (error, stack) {
      if (!_isCurrent(job)) {
        _retire(job);
        return;
      }
      job.error = error;
      job.stack = stack;
      _releaseController(job);
    }
    _notifyLater();
  }

  void _detach(_ChunkDemand demand) {
    final job = demand.job;
    demand.job = null;
    if (job == null) return;
    job.demands.remove(demand);
    if (job.demands.isEmpty) _retire(job);
  }

  void _retire(_ChunkPreparationJob job) {
    if (job.retired) return;
    job.retired = true;
    if (identical(_jobs[job.manifest.request.sourceId], job)) {
      _jobs.remove(job.manifest.request.sourceId);
    }
    for (final demand in job.demands) {
      if (identical(demand.job, job)) demand.job = null;
    }
    job.demands.clear();
    _releaseController(job);
  }

  void _releaseController(_ChunkPreparationJob job) {
    final controller = job.controller;
    job.controller = null;
    if (controller == null) return;
    controller.removeListener(job.changed!);
    job.changed = null;
    // Reset releases the worker lease and full document immediately. Disposal
    // waits until a possible ChangeNotifier notification has finished unwinding.
    controller.reset();
    scheduleMicrotask(controller.dispose);
  }

  void _notifyLater() {
    if (_closed || _notificationScheduled) return;
    _notificationScheduled = true;
    final generation = _notificationGeneration;
    scheduleMicrotask(() {
      if (generation != _notificationGeneration) return;
      _notificationScheduled = false;
      if (!_closed) notifyListeners();
    });
  }

  @override
  void dispose() {
    if (_closed) return;
    clear();
    _closed = true;
    super.dispose();
  }
}

final class _ChunkDemand {
  _ChunkDemand(this.manifest, this.ordinal);
  final ThreadDetailBodyManifest manifest;
  final int ordinal;
  ThreadDetailPreparedChunk? chunk;
  _ChunkPreparationJob? job;
}

final class _ChunkPreparationJob {
  _ChunkPreparationJob(this.manifest);
  final ThreadDetailBodyManifest manifest;
  final demands = HashSet<_ChunkDemand>.identity();
  ForumHtmlPreparationController? controller;
  VoidCallback? changed;
  Object? error;
  StackTrace? stack;
  bool retired = false;
}
