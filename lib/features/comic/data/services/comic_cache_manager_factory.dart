import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:y300/features/comic/data/services/custom_cache_file_system.dart';

/// Builds cache manager instances for comic images.
///
/// This keeps cache manager wiring and file-system decisions out of providers
/// and service implementation, improving testability and maintainability.
class ComicCacheManagerFactory {
  const ComicCacheManagerFactory();

  static const String cacheKey = 'y300_comic_images';

  BaseCacheManager create({required String cacheDirectoryPath}) {
    return CacheManager(
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

