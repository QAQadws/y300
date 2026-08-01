import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:y300/features/comic/data/services/custom_cache_file_system.dart';

class ImageCacheManagerFactory {
  const ImageCacheManagerFactory();

  static const String cacheKey = 'y300_images';

  BaseCacheManager create({required String cacheDirectoryPath}) {
    return _Y300ImageCacheManager(
      Config(
        cacheKey,
        fileSystem: CustomPathFileSystem(
          basePath: cacheDirectoryPath,
          cacheKey: cacheKey,
        ),
      ),
    );
  }
}

/// Keeps the shared cache directory while enabling cached_network_image's
/// bounded resize path. The mixin only creates a resized copy when the source
/// pixels exceed the requested target, so smaller images are never upscaled.
final class _Y300ImageCacheManager extends CacheManager with ImageCacheManager {
  _Y300ImageCacheManager(super.config);
}
