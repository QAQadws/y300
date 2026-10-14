import 'dart:async';
import 'dart:ui';

import 'package:y300/features/cache/domain/models/forum_image_dimensions.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';

abstract interface class ForumImageDimensionIndex {
  Future<ForumImageDimensions?> getBySpec(ForumImageLoadSpec spec);

  Future<ForumImageDimensions?> getLastKnownBySpec(ForumImageLoadSpec spec);

  Future<void> recordDecodedDimensions({
    required ForumImageLoadSpec spec,
    required Size size,
  });
}

enum ForumImageDimensionLookupPriority { background, nearby, visible }

/// Optional queue admission and promotion; pending reads share the resolved
/// cache key, while completed hints are still revalidated on the next request.
abstract interface class PrioritizedForumImageDimensionIndex {
  Future<ForumImageDimensions?> getBySpecWithPriority(
    ForumImageLoadSpec spec, {
    required ForumImageDimensionLookupPriority priority,
  });
}

/// Shares only pending validated reads within this index instance.
/// Urgent hints may replace lower-priority waiting work within the same budget;
/// other additional keys return no optional layout hint.
/// successful reads and misses are checked again by calls after completion.
class CacheRecordForumImageDimensionIndex
    implements ForumImageDimensionIndex, PrioritizedForumImageDimensionIndex {
  CacheRecordForumImageDimensionIndex({
    required ImageCacheService imageCacheService,
    required ForumImageRequestResolver imageRequestResolver,
    int maxConcurrentLookups = 4,
    int maxPendingLookups = 64,
  }) : _imageCacheService = imageCacheService,
       _imageRequestResolver = imageRequestResolver,
       _lookups = _DimensionLookupQueue(
         maxConcurrent: maxConcurrentLookups,
         maxPending: maxPendingLookups,
       );

  final ImageCacheService _imageCacheService;
  final ForumImageRequestResolver _imageRequestResolver;
  final _DimensionLookupQueue _lookups;

  @override
  Future<ForumImageDimensions?> getBySpec(ForumImageLoadSpec spec) =>
      getBySpecWithPriority(
        spec,
        priority: ForumImageDimensionLookupPriority.background,
      );

  @override
  Future<ForumImageDimensions?> getBySpecWithPriority(
    ForumImageLoadSpec spec, {
    required ForumImageDimensionLookupPriority priority,
  }) async {
    final request = _imageRequestResolver.resolveCacheRequest(spec);
    final cacheKey = request?.cacheKey.trim();
    if (cacheKey == null || cacheKey.isEmpty) {
      return null;
    }
    // The resolved key is the complete input of this service's metadata lookup.
    // Display indices, owner hints and referers do not change the cached file.
    return _lookups.lookup(cacheKey, () => _readDimensions(cacheKey), priority);
  }

  Future<ForumImageDimensions?> _readDimensions(String cacheKey) async {
    final cacheService = _imageCacheService;
    final result = cacheService is ImageCacheMetadataLookup
        ? await (cacheService as ImageCacheMetadataLookup).peekCached(cacheKey)
        : await cacheService.getCached(cacheKey);
    if (result == null || !result.success) {
      return null;
    }
    return ForumImageDimensions.fromCacheMetadata(
      width: result.width,
      height: result.height,
    );
  }

  @override
  Future<ForumImageDimensions?> getLastKnownBySpec(
    ForumImageLoadSpec spec,
  ) async {
    final request = _imageRequestResolver.resolveCacheRequest(spec);
    if (request == null) {
      return null;
    }
    final cacheService = _imageCacheService;
    if (cacheService is! ImageCacheOwnerDimensionLookup) {
      return getBySpec(spec);
    }
    final lookup = cacheService as ImageCacheOwnerDimensionLookup;
    final size = await lookup.getLastKnownDimensions(
      ownerType: request.ownerType,
      ownerId: request.ownerId,
      role: request.role,
      preferredCacheKey: request.cacheKey,
    );
    return ForumImageDimensions.fromValues(
      width: size?.width,
      height: size?.height,
      source: ForumImageDimensionSource.cacheMetadata,
    );
  }

  @override
  Future<void> recordDecodedDimensions({
    required ForumImageLoadSpec spec,
    required Size size,
  }) async {
    if (_imageCacheService is! ImageCacheDimensionRecorder) {
      return;
    }
    final request = _imageRequestResolver.resolveCacheRequest(spec);
    final cacheKey = request?.cacheKey.trim();
    if (cacheKey == null || cacheKey.isEmpty) {
      return;
    }
    try {
      final recorder = _imageCacheService as ImageCacheDimensionRecorder;
      await recorder.recordResolvedDimensions(cacheKey: cacheKey, size: size);
    } catch (_) {
      // Dimension hints improve future layouts only; callers should never fail
      // because metadata persistence failed.
    } finally {
      // A lookup that started before decode persistence may contain old hints.
      // Its callers can finish, but a subsequent read must validate again.
      _lookups.invalidate(cacheKey);
    }
  }
}

// Only in-flight work is shared. Completed hints are never retained: later
// calls still inspect current cache metadata and the real file's existence.
final class _DimensionLookupQueue {
  _DimensionLookupQueue({
    required this.maxConcurrent,
    required this.maxPending,
  }) {
    if (maxConcurrent <= 0 || maxPending < 0) {
      throw ArgumentError('Invalid dimension lookup limits');
    }
  }

  final int maxConcurrent;
  final int maxPending;
  final _inFlight = <String, _DimensionLookup>{};
  final _pending = <_DimensionLookup>[];
  int _running = 0;

  Future<ForumImageDimensions?> lookup(
    String identity,
    Future<ForumImageDimensions?> Function() read,
    ForumImageDimensionLookupPriority priority,
  ) {
    final existing = _inFlight[identity];
    if (existing != null) {
      if (priority.index > existing.priority.index) {
        existing.priority = priority;
      }
      return existing.result.future;
    }
    if (_running >= maxConcurrent && _pending.length >= maxPending) {
      // Retire only a lower-priority waiting hint, never active file I/O. Pick
      // the newest among equal-priority hints so the remaining backlog is FIFO.
      _DimensionLookup? displaced;
      for (final lookup in _pending.reversed) {
        if (lookup.priority.index < priority.index &&
            (displaced == null ||
                lookup.priority.index < displaced.priority.index)) {
          displaced = lookup;
        }
      }
      if (displaced == null) return Future<ForumImageDimensions?>.value();
      _pending.remove(displaced);
      if (identical(_inFlight[displaced.identity], displaced)) {
        _inFlight.remove(displaced.identity);
      }
      displaced.result.complete(null);
    }
    final lookup = _DimensionLookup(identity, read, priority);
    _inFlight[identity] = lookup;
    if (_running < maxConcurrent) {
      _start(lookup);
    } else {
      _pending.add(lookup);
    }
    return lookup.result.future;
  }

  void invalidate(String cacheKey) {
    _inFlight.remove(cacheKey);
  }

  void _start(_DimensionLookup lookup) {
    _running++;
    unawaited(_run(lookup));
  }

  Future<void> _run(_DimensionLookup lookup) async {
    try {
      lookup.result.complete(await lookup.read());
    } catch (error, stackTrace) {
      lookup.result.completeError(error, stackTrace);
    } finally {
      if (identical(_inFlight[lookup.identity], lookup)) {
        _inFlight.remove(lookup.identity);
      }
      _running--;
      if (_pending.isNotEmpty) {
        var next = _pending.first;
        for (final candidate in _pending.skip(1)) {
          if (candidate.priority.index > next.priority.index) next = candidate;
        }
        _pending.remove(next);
        _start(next);
      }
    }
  }
}

final class _DimensionLookup {
  _DimensionLookup(this.identity, this.read, this.priority);

  final String identity;
  final Future<ForumImageDimensions?> Function() read;
  ForumImageDimensionLookupPriority priority;
  final result = Completer<ForumImageDimensions?>();
}
