import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/data/services/app_image_cache_info_repository.dart';
import 'package:y300/features/cache/data/services/image_cache_file_access.dart';
import 'package:y300/features/comic/data/services/custom_cache_file_system.dart';

class ImageCacheManagerFactory {
  const ImageCacheManagerFactory({
    required this.fileService,
    required this.repository,
    required this.fileAccess,
  });

  final FileService fileService;
  final ImageCacheRepository repository;
  final ImageCacheFileAccess fileAccess;

  static const String cacheKey = 'y300_images';

  BaseCacheManager create({required String cacheDirectoryPath}) {
    final defaults = Config(
      cacheKey,
      fileSystem: CustomPathFileSystem(
        basePath: cacheDirectoryPath,
        cacheKey: cacheKey,
      ),
      fileService: fileService,
    );
    late final _Y300ImageCacheManager manager;
    manager = _Y300ImageCacheManager(
      Config(
        cacheKey,
        fileSystem: defaults.fileSystem,
        fileService: defaults.fileService,
        repo: AppImageCacheInfoRepository(
          delegate: defaults.repo,
          imageRepository: repository,
          fileAccess: fileAccess,
          cacheDirectoryPath: p.join(cacheDirectoryPath, cacheKey),
          removeFile: (key) => manager.removeFile(key),
        ),
      ),
    );
    return manager;
  }
}

/// Keeps the shared cache directory while enabling cached_network_image's
/// bounded resize path. The mixin only creates a resized copy when the source
/// pixels exceed the requested target, so smaller images are never upscaled.
final class _Y300ImageCacheManager extends CacheManager with ImageCacheManager {
  _Y300ImageCacheManager(super.config);
}
