import 'package:y300/features/cache/domain/image_cache_models.dart';

abstract class ImageCacheService {
  Future<CachedImageResult> ensureCached(ImageCacheRequest request);

  Future<CachedImageResult?> getCached(String cacheKey);

  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  );

  Future<int> calculateUsageBytes({bool includeProtected = false});

  Future<void> pruneToLimit({required int maxBytes});

  Future<void> clearUnprotected();
}
