import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';

typedef ImageCacheServiceResolver = ImageCacheService? Function();

/// Shared cover cache policy for shelf/detail adapters.
///
/// UI widgets only render a preferred local path. This service keeps the
/// "remote cover -> protected local file" decision in the library domain so
/// favorites, comic and novel shelves can share one small policy surface.
class LibraryCoverCacheService {
  const LibraryCoverCacheService(ImageCacheService? imageCacheService)
      : _imageCacheServiceResolver = null,
        _imageCacheService = imageCacheService;

  const LibraryCoverCacheService.lazy(this._imageCacheServiceResolver)
      : _imageCacheService = null;

  final ImageCacheService? _imageCacheService;
  final ImageCacheServiceResolver? _imageCacheServiceResolver;

  Future<CachedImageResult?> ensureProtectedCover({
    required String cacheKey,
    required String sourceUrl,
    required ImageCacheOwnerType ownerType,
    required String ownerId,
    ImageCacheRole role = ImageCacheRole.cover,
  }) async {
    final service = _imageCacheService ?? _imageCacheServiceResolver?.call();
    final normalizedSource = sourceUrl.trim();
    if (service == null || normalizedSource.isEmpty) {
      return null;
    }
    final result = await service.ensureCached(
      ImageCacheRequest(
        cacheKey: cacheKey,
        sourceUrl: normalizedSource,
        ownerType: ownerType,
        ownerId: ownerId,
        role: role,
        protected: true,
      ),
    );
    return result.success ? result : null;
  }
}
