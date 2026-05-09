import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:y300/features/comic/data/custom_cache_file_system.dart';

class ImageCacheManagerFactory {
  const ImageCacheManagerFactory();

  static const String cacheKey = 'y300_images';

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
