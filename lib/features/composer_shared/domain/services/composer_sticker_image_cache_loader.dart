import 'dart:async';

import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';

/// Cache-first sticker image loader for composer surfaces.
///
/// Reply and posting can show many stickers at once.  Cache misses are funneled
/// through one shared queue so opening the picker cannot burst small image
/// requests at the forum.
class ComposerStickerImageCacheLoader {
  ComposerStickerImageCacheLoader({
    required ImageCacheService imageCacheService,
    this.networkGap = const Duration(milliseconds: 500),
    DateTime Function()? now,
    Future<void> Function(Duration duration)? delay,
  }) : _imageCacheService = imageCacheService,
       _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  final ImageCacheService _imageCacheService;
  final Duration networkGap;
  final DateTime Function() _now;
  final Future<void> Function(Duration duration) _delay;
  final Map<String, Future<CachedImageResult>> _inFlight =
      <String, Future<CachedImageResult>>{};

  Future<void> _tail = Future<void>.value();
  DateTime? _lastNetworkStart;

  Future<CachedImageResult?> getCached(String cacheKey) {
    return _imageCacheService.getCached(cacheKey);
  }

  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    final cacheKey = request.cacheKey.trim();
    if (cacheKey.isEmpty) {
      return CachedImageResult.failed;
    }
    final cached = await _imageCacheService.getCached(cacheKey);
    if (cached != null && cached.success) {
      return cached;
    }

    final inFlight = _inFlight[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _enqueueNetworkLoad(request);
    _inFlight[cacheKey] = future;
    future.whenComplete(() {
      if (identical(_inFlight[cacheKey], future)) {
        _inFlight.remove(cacheKey);
      }
    });
    return future;
  }

  Future<CachedImageResult> _enqueueNetworkLoad(ImageCacheRequest request) {
    final completer = Completer<CachedImageResult>();
    _tail = _tail.then((_) async {
      try {
        await _waitForNetworkGap();
        final result = await _imageCacheService.ensureCached(request);
        completer.complete(result);
      } catch (_) {
        completer.complete(CachedImageResult.failed);
      }
    });
    return completer.future;
  }

  Future<void> _waitForNetworkGap() async {
    final lastStart = _lastNetworkStart;
    final now = _now();
    if (lastStart != null) {
      final elapsed = now.difference(lastStart);
      if (elapsed < networkGap) {
        await _delay(networkGap - elapsed);
      }
    }
    _lastNetworkStart = _now();
  }
}
