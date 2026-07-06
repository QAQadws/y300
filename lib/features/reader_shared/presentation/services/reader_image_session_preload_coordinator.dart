import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/reader_shared/presentation/engine/reader_capability.dart';

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

enum ReaderImageSessionPreloadKind { decoded, disk }

class ReaderImageSessionPreloadResult {
  const ReaderImageSessionPreloadResult({
    required this.spec,
    required this.kind,
    required this.result,
    required this.generation,
    required this.applied,
  });

  final ForumImageLoadSpec spec;
  final ReaderImageSessionPreloadKind kind;
  final ForumImagePrecacheResult result;
  final int generation;
  final bool applied;
}

class ReaderImageSessionPreloadCoordinator {
  ReaderImageSessionPreloadCoordinator({
    ReaderImageSessionPreloadPolicy policy =
        ReaderImageSessionPreloadPolicy.aggressiveReaderSession,
    void Function(ReaderImageSessionPreloadResult result)? onResult,
  }) : _policy = policy,
       _onResult = onResult;

  final ReaderImageSessionPreloadPolicy _policy;
  final void Function(ReaderImageSessionPreloadResult result)? _onResult;
  final Map<String, ReaderImageSessionPreloadKind> _scheduledByIdentity =
      <String, ReaderImageSessionPreloadKind>{};
  var _generation = 0;
  var _disposed = false;

  int get generation => _generation;

  void resetSession() {
    if (_disposed) {
      return;
    }
    _generation += 1;
    _scheduledByIdentity.clear();
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
      switch (request.kind) {
        case ReaderImageSessionPreloadKind.decoded:
          unawaited(
            _runDecoded(
              context: context,
              request: request,
              generation: generation,
              precacheService: precacheService,
              expectedDisplaySize: expectedDisplaySize,
            ),
          );
        case ReaderImageSessionPreloadKind.disk:
          unawaited(
            _runDisk(
              request: request,
              generation: generation,
              precacheService: precacheService,
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
    _notifyResult(request: request, generation: generation, result: result);
  }

  Future<void> _runDisk({
    required ReaderImageSessionPreloadRequest request,
    required int generation,
    required ForumImagePrecacheService precacheService,
  }) async {
    ForumImagePrecacheResult result;
    try {
      result = await precacheService.ensureDiskCached(request.spec);
    } catch (error) {
      result = ForumImagePrecacheResult.failed(error);
    }
    _notifyResult(request: request, generation: generation, result: result);
  }

  void _notifyResult({
    required ReaderImageSessionPreloadRequest request,
    required int generation,
    required ForumImagePrecacheResult result,
  }) {
    _onResult?.call(
      ReaderImageSessionPreloadResult(
        spec: request.spec,
        kind: request.kind,
        result: result,
        generation: generation,
        applied: !_disposed && generation == _generation,
      ),
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
    required this.index,
    required this.spec,
    required this.kind,
  });

  final int index;
  final ForumImageLoadSpec spec;
  final ReaderImageSessionPreloadKind kind;
}
