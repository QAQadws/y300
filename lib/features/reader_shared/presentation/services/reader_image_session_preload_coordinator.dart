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
  }) : assert(decodedRadius >= 0),
       assert(diskRadius >= decodedRadius);

  final int decodedRadius;
  final int diskRadius;

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
  final Map<String, ReaderImageSessionPreloadKind> _scheduledByIdentity =
      <String, ReaderImageSessionPreloadKind>{};
  var _generation = 0;
  var _disposed = false;

  int get generation => _generation;

  void resetSession({
    String? readerOwnerId,
    Iterable<ContinuousImageItem> items = const <ContinuousImageItem>[],
  }) {
    if (_disposed) {
      return;
    }
    _generation += 1;
    _scheduledByIdentity.clear();
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
    _scheduledByIdentity.clear();
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
    final requests = buildRequests(
      content: content,
      focusIndex: focusIndex,
      scrollDirection: scrollDirection,
      capability: capability,
    );
    for (final request in requests) {
      if (!_markScheduled(request)) {
        continue;
      }
      _notifyScheduled(request: request, generation: generation);
      switch (request.kind) {
        case ReaderImageSessionPreloadKind.decoded:
          unawaited(
            _runDecoded(
              context: context,
              request: request,
              generation: generation,
              precacheService: precacheService,
              expectedDisplaySize: expectedDisplaySize,
              preparationSink: capability.imagePreparationSink,
            ),
          );
        case ReaderImageSessionPreloadKind.disk:
          unawaited(
            _runDisk(
              request: request,
              generation: generation,
              precacheService: precacheService,
              preparationSink: capability.imagePreparationSink,
            ),
          );
      }
    }
  }

  Future<void> _runDecoded({
    required BuildContext context,
    required ReaderImageSessionPreloadRequest request,
    required int generation,
    required ForumImagePrecacheService precacheService,
    required Size? expectedDisplaySize,
    required ReaderImagePreparationSink? preparationSink,
  }) async {
    ForumImagePrecacheResult result;
    try {
      result = await precacheService.precacheDecoded(
        context: context,
        spec: request.spec,
        expectedDisplaySize: expectedDisplaySize,
      );
    } catch (error) {
      result = ForumImagePrecacheResult.failed(error);
    }
    _notifyResult(
      request: request,
      generation: generation,
      result: result,
      preparationSink: preparationSink,
    );
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

  Future<void> _runDisk({
    required ReaderImageSessionPreloadRequest request,
    required int generation,
    required ForumImagePrecacheService precacheService,
    required ReaderImagePreparationSink? preparationSink,
  }) async {
    ForumImagePrecacheResult result;
    try {
      result = await precacheService.ensureDiskCached(request.spec);
    } catch (error) {
      result = ForumImagePrecacheResult.failed(error);
    }
    _notifyResult(
      request: request,
      generation: generation,
      result: result,
      preparationSink: preparationSink,
    );
  }

  void _notifyResult({
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
    if (!applied ||
        !result.success ||
        preparationSink == null ||
        localPath == null ||
        localPath.isEmpty) {
      return;
    }
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

  bool _markScheduled(ReaderImageSessionPreloadRequest request) {
    final identity = _scheduleIdentity(request);
    final existing = _scheduledByIdentity[identity];
    if (existing == ReaderImageSessionPreloadKind.decoded) {
      return false;
    }
    if (existing == ReaderImageSessionPreloadKind.disk &&
        request.kind == ReaderImageSessionPreloadKind.disk) {
      return false;
    }
    _scheduledByIdentity[identity] = request.kind;
    return true;
  }

  String _scheduleIdentity(ReaderImageSessionPreloadRequest request) {
    final cacheKey = request.spec.cacheKey?.trim();
    final identity = cacheKey == null || cacheKey.isEmpty
        ? request.spec.sourceUrl
        : cacheKey;
    return '$identity:${request.spec.sourceUrl}';
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
