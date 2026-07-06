import 'dart:ui';

import 'package:y300/features/cache/domain/models/forum_image_dimensions.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';

abstract interface class ForumImageDimensionIndex {
  Future<ForumImageDimensions?> getBySpec(ForumImageLoadSpec spec);

  Future<void> recordDecodedDimensions({
    required ForumImageLoadSpec spec,
    required Size size,
  });
}

class CacheRecordForumImageDimensionIndex implements ForumImageDimensionIndex {
  const CacheRecordForumImageDimensionIndex({
    required ImageCacheService imageCacheService,
    required ForumImageRequestResolver imageRequestResolver,
  }) : _imageCacheService = imageCacheService,
       _imageRequestResolver = imageRequestResolver;

  final ImageCacheService _imageCacheService;
  final ForumImageRequestResolver _imageRequestResolver;

  @override
  Future<ForumImageDimensions?> getBySpec(ForumImageLoadSpec spec) async {
    final request = _imageRequestResolver.resolveCacheRequest(spec);
    final cacheKey = request?.cacheKey.trim();
    if (cacheKey == null || cacheKey.isEmpty) {
      return null;
    }
    final result = await _imageCacheService.getCached(cacheKey);
    if (result == null || !result.success) {
      return null;
    }
    return ForumImageDimensions.fromCacheMetadata(
      width: result.width,
      height: result.height,
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
    }
  }
}
