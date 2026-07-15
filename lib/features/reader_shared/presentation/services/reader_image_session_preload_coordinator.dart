import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/domain/image_session/reader_image_session.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_capability.dart';
import 'package:y300/features/reader_shared/presentation/services/reader_image_session_store.dart';

export 'package:y300/features/reader_shared/domain/image_session/reader_image_session.dart'
    show ReaderImageSessionPreloadKind;

class ReaderImageSessionPreloadPolicy {
  const ReaderImageSessionPreloadPolicy({
    this.decodedRadius = 1,
    this.diskRadius = 3,
    this.maxConcurrentTasks = 3,
  }) : assert(decodedRadius >= 0),
       assert(diskRadius >= decodedRadius),
       assert(maxConcurrentTasks > 0);

  final int decodedRadius;
  final int diskRadius;
  final int maxConcurrentTasks;

  static const aggressiveReaderSession = ReaderImageSessionPreloadPolicy();
}

class ReaderImageSessionPreloadResult {
  const ReaderImageSessionPreloadResult({
    required this.readerOwnerId,
    required this.itemId,
    required this.imageIndex,
    required this.spec,
    required this.kind,
    required this.result,
    required this.generation,
    required this.applied,
  });

  final String readerOwnerId;
  final String itemId;
  final int imageIndex;
  final ForumImageLoadSpec spec;
  final ReaderImageSessionPreloadKind kind;
  final ForumImagePrecacheResult result;
  final int generation;
  final bool applied;
}

class ReaderImageSessionPreloadScheduled {
  const ReaderImageSessionPreloadScheduled({
    required this.readerOwnerId,
    required this.itemId,
    required this.imageIndex,
    required this.spec,
    required this.kind,
    required this.generation,
  });

  final String readerOwnerId;
  final String itemId;
  final int imageIndex;
  final ForumImageLoadSpec spec;
  final ReaderImageSessionPreloadKind kind;
  final int generation;
}

class ReaderImageSessionPreloadCoordinator {
  ReaderImageSessionPreloadCoordinator({
    ReaderImageSessionPreloadPolicy policy =
        ReaderImageSessionPreloadPolicy.aggressiveReaderSession,
    ReaderImageSessionStore? sessionStore,
    void Function(ReaderImageSessionPreloadScheduled scheduled)? onScheduled,
    void Function(ReaderImageSessionPreloadResult result)? onResult,
  }) : _policy = policy,
       _sessionStore = sessionStore,
       _onScheduled = onScheduled,
       _onResult = onResult;

  final ReaderImageSessionPreloadPolicy _policy;
  final ReaderImageSessionStore? _sessionStore;
  final void Function(ReaderImageSessionPreloadScheduled scheduled)?
  _onScheduled;
  final void Function(ReaderImageSessionPreloadResult result)? _onResult;
  final List<_ReaderImagePreparationTask> _pending =
      <_ReaderImagePreparationTask>[];
  final Set<_ReaderImagePreparationTask> _running =
      <_ReaderImagePreparationTask>{};
  final Map<String, ReaderImageSessionPreloadKind> _finishedByIdentity =
      <String, ReaderImageSessionPreloadKind>{};
  var _generation = 0;
  var _sequence = 0;
  var _disposed = false;

  int get generation => _generation;

  @visibleForTesting
  int get pendingTaskCount => _pending.length;

  @visibleForTesting
  int get runningTaskCount => _running.length;

  void resetSession({
    String? readerOwnerId,
    Iterable<ContinuousImageItem> items = const <ContinuousImageItem>[],
  }) {
    if (_disposed) {
      return;
    }
    _generation += 1;
    _cancelPendingTasks();
    _finishedByIdentity.clear();
    if (readerOwnerId != null) {
      _sessionStore?.startSession(
        readerOwnerId: readerOwnerId,
        generation: _generation,
        items: items,
      );
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _generation += 1;
    _cancelPendingTasks();
    _finishedByIdentity.clear();
  }

  List<ReaderImageSessionPreloadRequest> buildRequests({
    required ReaderContent content,
    required int focusIndex,
    required ContinuousImageScrollDirection scrollDirection,
    required ReaderCapability capability,
  }) {
    if (_disposed || content.items.isEmpty) {
      return const <ReaderImageSessionPreloadRequest>[];
    }
    final clampedFocus = focusIndex.clamp(0, content.items.length - 1).toInt();
    final indices = _orderedIndices(
      focusIndex: clampedFocus,
      itemCount: content.items.length,
      scrollDirection: scrollDirection,
    );
    final requests = <ReaderImageSessionPreloadRequest>[];
    for (final index in indices) {
      final item = content.items[index];
      final spec = capability.imageLoadSpecFor(item);
      if (spec == null) {
        continue;
      }
      final distance = (index - clampedFocus).abs();
      requests.add(
        ReaderImageSessionPreloadRequest(
          readerOwnerId: content.ownerId,
          itemId: item.id,
          index: index,
          spec: spec,
          kind: distance <= _policy.decodedRadius
              ? ReaderImageSessionPreloadKind.decoded
              : ReaderImageSessionPreloadKind.disk,
        ),
      );
    }
    return requests;
  }

  void submitWindow({
    required BuildContext context,
    required ReaderContent content,
    required int focusIndex,
    required ContinuousImageScrollDirection scrollDirection,
    required ReaderCapability capability,
    required ForumImagePrecacheService precacheService,
    Size? expectedDisplaySize,
  }) {
    if (_disposed || content.items.isEmpty) {
      return;
    }
    final generation = _generation;
    _sessionStore?.startSession(
      readerOwnerId: content.ownerId,
      generation: generation,
      items: content.items,
    );
    _removePendingWhere(
      (task) =>
          task.generation == generation &&
          task.role == _ReaderImagePreparationRole.window,
    );
    final requests = buildRequests(
      content: content,
      focusIndex: focusIndex,
      scrollDirection: scrollDirection,
      capability: capability,
    );
    for (final request in requests) {
      _enqueue(
        _ReaderImagePreparationTask(
          request: request,
          generation: generation,
          role: _ReaderImagePreparationRole.window,
          priority: request.kind == ReaderImageSessionPreloadKind.decoded
              ? _ReaderImagePreparationPriority.windowDecoded
              : _ReaderImagePreparationPriority.windowDisk,
          sequence: _sequence++,
          context: context,
          precacheService: precacheService,
          expectedDisplaySize: expectedDisplaySize,
          preparationSink: capability.imagePreparationSink,
        ),
      );
    }
    _pump();
  }

  /// Promotes the latest explicit seek target ahead of ordinary window work.
  /// A newer pending seek supersedes an older one; already-running work remains
  /// bounded by [ReaderImageSessionPreloadPolicy.maxConcurrentTasks].
  void promoteSeekTarget({
    required BuildContext context,
    required ReaderContent content,
    required int index,
    required ReaderCapability capability,
    required ForumImagePrecacheService precacheService,
    Size? expectedDisplaySize,
  }) {
    if (_disposed || content.items.isEmpty) {
      return;
    }
    final generation = _generation;
    _removePendingWhere(
      (task) =>
          task.generation == generation &&
          task.role == _ReaderImagePreparationRole.seek,
    );
    final request = _requestForIndex(
      content: content,
      index: index,
      capability: capability,
    );
    if (request == null) {
      return;
    }
    _enqueue(
      _ReaderImagePreparationTask(
        request: request,
        generation: generation,
        role: _ReaderImagePreparationRole.seek,
        priority: _ReaderImagePreparationPriority.seek,
        sequence: _sequence++,
        context: context,
        precacheService: precacheService,
        expectedDisplaySize: expectedDisplaySize,
        preparationSink: capability.imagePreparationSink,
      ),
    );
    _pump();
  }

  /// Prepares one decoded image inside the active owner session.
  ///
  /// [force] bypasses the session's completed-task dedupe and is intended for
  /// an explicit user retry. Results still pass through the generation-safe
  /// session store and the optional business metadata sink.
  Future<ReaderImageSessionPreloadResult?> prepareOne({
    required BuildContext context,
    required ReaderContent content,
    required int index,
    required ReaderCapability capability,
    required ForumImagePrecacheService precacheService,
    Size? expectedDisplaySize,
    bool force = false,
  }) {
    if (_disposed || content.items.isEmpty) {
      return Future<ReaderImageSessionPreloadResult?>.value();
    }
    final request = _requestForIndex(
      content: content,
      index: index,
      capability: capability,
    );
    if (request == null) {
      return Future<ReaderImageSessionPreloadResult?>.value();
    }
    final completer = Completer<ReaderImageSessionPreloadResult?>();
    final task = _ReaderImagePreparationTask(
      request: request,
      generation: _generation,
      role: _ReaderImagePreparationRole.retry,
      priority: _ReaderImagePreparationPriority.retry,
      sequence: _sequence++,
      context: context,
      precacheService: precacheService,
      expectedDisplaySize: expectedDisplaySize,
      preparationSink: capability.imagePreparationSink,
      force: force,
      completer: completer,
    );
    if (force) {
      final identity = _scheduleIdentity(request);
      _finishedByIdentity.remove(identity);
      _removePendingWhere(
        (pending) =>
            pending.generation == task.generation &&
            _scheduleIdentity(pending.request) == identity,
      );
    }
    if (!_enqueue(task)) {
      if (!completer.isCompleted) {
        completer.complete();
      }
      return completer.future;
    }
    _pump();
    return completer.future;
  }

  ReaderImageSessionPreloadRequest? _requestForIndex({
    required ReaderContent content,
    required int index,
    required ReaderCapability capability,
  }) {
    if (index < 0 || index >= content.items.length) {
      return null;
    }
    final item = content.items[index];
    final spec = capability.imageLoadSpecFor(item);
    if (spec == null) {
      return null;
    }
    return ReaderImageSessionPreloadRequest(
      readerOwnerId: content.ownerId,
      itemId: item.id,
      index: index,
      spec: spec,
      kind: ReaderImageSessionPreloadKind.decoded,
    );
  }

  bool _enqueue(_ReaderImagePreparationTask task) {
    if (_disposed || task.generation != _generation) {
      return false;
    }
    final identity = _scheduleIdentity(task.request);
    if (!task.force &&
        _kindSatisfies(_finishedByIdentity[identity], task.request.kind)) {
      return false;
    }
    final running = _running.where(
      (candidate) =>
          candidate.generation == task.generation &&
          _scheduleIdentity(candidate.request) == identity,
    );
    if (!task.force &&
        running.any(
          (candidate) =>
              _kindSatisfies(candidate.request.kind, task.request.kind),
        )) {
      return false;
    }
    final pendingIndex = _pending.indexWhere(
      (candidate) =>
          candidate.generation == task.generation &&
          _scheduleIdentity(candidate.request) == identity,
    );
    if (pendingIndex >= 0) {
      final existing = _pending[pendingIndex];
      if (!task.force &&
          _kindSatisfies(existing.request.kind, task.request.kind) &&
          existing.priority.index <= task.priority.index) {
        return false;
      }
      _pending.removeAt(pendingIndex);
      _completeCancelled(existing);
    }
    _pending.add(task);
    return true;
  }

  void _pump() {
    if (_disposed) {
      return;
    }
    while (_running.length < _policy.maxConcurrentTasks &&
        _pending.isNotEmpty) {
      _pending.sort(_compareTasks);
      final task = _pending.removeAt(0);
      if (task.generation != _generation) {
        _completeCancelled(task);
        continue;
      }
      _running.add(task);
      _notifyScheduled(request: task.request, generation: task.generation);
      unawaited(_runTask(task));
    }
  }

  Future<void> _runTask(_ReaderImagePreparationTask task) async {
    ForumImagePrecacheResult result;
    try {
      switch (task.request.kind) {
        case ReaderImageSessionPreloadKind.decoded:
          result = await task.precacheService.precacheDecoded(
            context: task.context,
            spec: task.request.spec,
            expectedDisplaySize: task.expectedDisplaySize,
          );
        case ReaderImageSessionPreloadKind.disk:
          result = await task.precacheService.ensureDiskCached(
            task.request.spec,
          );
      }
    } catch (error) {
      result = ForumImagePrecacheResult.failed(error);
    }
    if (!_disposed && task.generation == _generation) {
      final identity = _scheduleIdentity(task.request);
      final previous = _finishedByIdentity[identity];
      if (!_kindSatisfies(previous, task.request.kind)) {
        _finishedByIdentity[identity] = task.request.kind;
      }
    }
    final event = _notifyResult(
      request: task.request,
      generation: task.generation,
      result: result,
      preparationSink: task.preparationSink,
    );
    if (task.completer case final completer? when !completer.isCompleted) {
      completer.complete(event);
    }
    _running.remove(task);
    _pump();
  }

  void _notifyScheduled({
    required ReaderImageSessionPreloadRequest request,
    required int generation,
  }) {
    try {
      _onScheduled?.call(
        ReaderImageSessionPreloadScheduled(
          readerOwnerId: request.readerOwnerId,
          itemId: request.itemId,
          imageIndex: request.index,
          spec: request.spec,
          kind: request.kind,
          generation: generation,
        ),
      );
    } catch (_) {
      // Observability callbacks must not prevent the preload from starting.
    }
  }

  ReaderImageSessionPreloadResult _notifyResult({
    required ReaderImageSessionPreloadRequest request,
    required int generation,
    required ForumImagePrecacheResult result,
    required ReaderImagePreparationSink? preparationSink,
  }) {
    final currentGeneration = !_disposed && generation == _generation;
    final applied =
        currentGeneration &&
        (_sessionStore?.applyPreloadResult(
              readerOwnerId: request.readerOwnerId,
              itemId: request.itemId,
              generation: generation,
              sourceUrl: request.spec.sourceUrl,
              cacheKey: request.spec.cacheKey,
              kind: request.kind,
              result: result,
            ) ??
            true);
    final event = ReaderImageSessionPreloadResult(
      readerOwnerId: request.readerOwnerId,
      itemId: request.itemId,
      imageIndex: request.index,
      spec: request.spec,
      kind: request.kind,
      result: result,
      generation: generation,
      applied: applied,
    );
    try {
      _onResult?.call(event);
    } catch (_) {
      // Diagnostics must not alter image preparation or display.
    }
    final localPath = result.localPath?.trim();
    if (applied &&
        result.success &&
        preparationSink != null &&
        localPath != null &&
        localPath.isNotEmpty) {
      unawaited(
        preparationSink
            .record(
              ReaderImagePreparationRecord(
                readerOwnerId: request.readerOwnerId,
                itemId: request.itemId,
                imageIndex: request.index,
                sourceUrl: request.spec.sourceUrl,
                cacheKey: result.cacheKey ?? request.spec.cacheKey,
                localPath: localPath,
                generation: generation,
                decoded: result.decoded,
              ),
            )
            .catchError((_) {
              // Business metadata is best-effort and never blocks the reader.
            }),
      );
    }
    return event;
  }

  List<int> _orderedIndices({
    required int focusIndex,
    required int itemCount,
    required ContinuousImageScrollDirection scrollDirection,
  }) {
    final indices = <int>[focusIndex];
    void addForward() {
      for (var distance = 1; distance <= _policy.diskRadius; distance++) {
        final index = focusIndex + distance;
        if (index >= 0 && index < itemCount) {
          indices.add(index);
        }
      }
    }

    void addBackward() {
      for (var distance = 1; distance <= _policy.diskRadius; distance++) {
        final index = focusIndex - distance;
        if (index >= 0 && index < itemCount) {
          indices.add(index);
        }
      }
    }

    if (scrollDirection == ContinuousImageScrollDirection.reverse) {
      addBackward();
      addForward();
    } else {
      addForward();
      addBackward();
    }
    return indices.toSet().toList(growable: false);
  }

  int _compareTasks(
    _ReaderImagePreparationTask left,
    _ReaderImagePreparationTask right,
  ) {
    final priority = left.priority.index.compareTo(right.priority.index);
    return priority != 0 ? priority : left.sequence.compareTo(right.sequence);
  }

  bool _kindSatisfies(
    ReaderImageSessionPreloadKind? prepared,
    ReaderImageSessionPreloadKind requested,
  ) {
    if (prepared == null) {
      return false;
    }
    return prepared == ReaderImageSessionPreloadKind.decoded ||
        prepared == requested;
  }

  String _scheduleIdentity(ReaderImageSessionPreloadRequest request) {
    final cacheKey = request.spec.cacheKey?.trim();
    final identity = cacheKey == null || cacheKey.isEmpty
        ? request.spec.sourceUrl
        : cacheKey;
    return '$identity:${request.spec.sourceUrl}';
  }

  void _removePendingWhere(
    bool Function(_ReaderImagePreparationTask task) predicate,
  ) {
    final removed = _pending.where(predicate).toList(growable: false);
    _pending.removeWhere(predicate);
    for (final task in removed) {
      _completeCancelled(task);
    }
  }

  void _cancelPendingTasks() {
    final pending = List<_ReaderImagePreparationTask>.of(_pending);
    _pending.clear();
    for (final task in pending) {
      _completeCancelled(task);
    }
  }

  void _completeCancelled(_ReaderImagePreparationTask task) {
    final completer = task.completer;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}

class ReaderImageSessionPreloadRequest {
  const ReaderImageSessionPreloadRequest({
    required this.readerOwnerId,
    required this.itemId,
    required this.index,
    required this.spec,
    required this.kind,
  });

  final String readerOwnerId;
  final String itemId;
  final int index;
  final ForumImageLoadSpec spec;
  final ReaderImageSessionPreloadKind kind;
}

enum _ReaderImagePreparationRole { window, seek, retry }

enum _ReaderImagePreparationPriority { retry, seek, windowDecoded, windowDisk }

class _ReaderImagePreparationTask {
  const _ReaderImagePreparationTask({
    required this.request,
    required this.generation,
    required this.role,
    required this.priority,
    required this.sequence,
    required this.context,
    required this.precacheService,
    required this.expectedDisplaySize,
    required this.preparationSink,
    this.force = false,
    this.completer,
  });

  final ReaderImageSessionPreloadRequest request;
  final int generation;
  final _ReaderImagePreparationRole role;
  final _ReaderImagePreparationPriority priority;
  final int sequence;
  final BuildContext context;
  final ForumImagePrecacheService precacheService;
  final Size? expectedDisplaySize;
  final ReaderImagePreparationSink? preparationSink;
  final bool force;
  final Completer<ReaderImageSessionPreloadResult?>? completer;
}
