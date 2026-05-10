import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/default_image_cache_service.dart';
import 'package:y300/features/cache/data/image_cache_directory_provider.dart';
import 'package:y300/features/cache/data/image_cache_manager_factory.dart';
import 'package:y300/features/cache/data/image_cache_repository.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';

final imageCacheDirectoryResolverProvider = Provider<ImageCacheDirectoryResolver>((ref) {
  return const ImageCacheDirectoryResolver();
});

final imageCacheManagerFactoryProvider = Provider<ImageCacheManagerFactory>((ref) {
  return const ImageCacheManagerFactory();
});

final imageCacheManagerProvider = FutureProvider<BaseCacheManager>((ref) async {
  final resolver = ref.read(imageCacheDirectoryResolverProvider);
  final root = await resolver.resolveImageCacheRoot();
  return ref.read(imageCacheManagerFactoryProvider).create(cacheDirectoryPath: root);
});

final imageCacheRepositoryProvider = Provider<ImageCacheRepository>((ref) {
  return LocalImageCacheRepository(ComicLocalDb.open());
});

final imageCacheServiceProvider = Provider<ImageCacheService>((ref) {
  return DefaultImageCacheService(
    repository: ref.watch(imageCacheRepositoryProvider),
    cacheManagerFuture: ref.watch(imageCacheManagerProvider.future),
    directoryResolver: ref.watch(imageCacheDirectoryResolverProvider),
    headerBuilder: ref.watch(imageRequestHeaderBuilderProvider),
  );
});
