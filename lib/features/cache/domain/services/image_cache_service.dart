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

/// Optional cache capability for recovering layout hints by business owner.
/// Keeping it separate avoids expanding every image-cache test double and
/// consumer that only needs the basic download/cache contract.
abstract interface class ImageCacheOwnerDimensionLookup {
  Future<Size?> getLastKnownDimensions({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
    required ImageCacheRole role,
    String? preferredCacheKey,
  });
}

abstract class ImageCacheDimensionRecorder {
  Future<void> recordResolvedDimensions({
    required String cacheKey,
    required Size size,
  });
}

/// Optional presentation-to-cache diagnostic hook for local decode failures.
///
/// It deliberately accepts the original cache request instead of a file path,
/// keeping filesystem identity out of diagnostic events.
abstract interface class ImageCacheDecodeFailureReporter {
  void reportDecodeFailure({
    required ImageCacheRequest request,
    required Object error,
    StackTrace? stackTrace,
  });
}
