import 'dart:ui';

import 'package:y300/features/cache/domain/models/image_cache_models.dart';

abstract class ImageCacheService {
  Future<CachedImageResult> ensureCached(ImageCacheRequest request);

  Future<CachedImageResult?> getCached(String cacheKey);

  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  );

  /// 删除同一 owner 下的全部缓存记录，包含保护与非保护资源。
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) {
    throw UnimplementedError('deleteByOwner(${ownerType.dbValue}, $ownerId)');
  }

  Future<int> calculateUsageBytes({bool includeProtected = false});

  Future<void> pruneToLimit({required int maxBytes});

  Future<void> clearUnprotected();

  /// 删除指定 role 下的非保护缓存记录，受保护资源（封面/已下载等）不会被删除。
  Future<int> clearUnprotectedByRoles({required List<ImageCacheRole> roles}) {
    throw UnimplementedError('clearUnprotectedByRoles($roles)');
  }
}

abstract class ImageCacheDimensionRecorder {
  Future<void> recordResolvedDimensions({
    required String cacheKey,
    required Size size,
  });
}
