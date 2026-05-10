import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart' as image_cache;
import 'package:y300/features/comic/data/comic_cache_directory_provider.dart';
import 'package:y300/features/comic/data/comic_cache_manager_factory.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local_comic_repository.dart';

final comicRepositoryProvider = Provider<ComicRepository>((ref) {
  return LocalComicRepository(
    ComicLocalDb.open(),
  );
});

final comicCoverCacheWriterProvider = Provider<ComicCoverCacheWriter?>((ref) {
  final repository = ref.watch(comicRepositoryProvider);
  return repository is ComicCoverCacheWriter
      ? repository as ComicCoverCacheWriter
      : null;
});

final comicCacheDirectoryResolverProvider = Provider<ComicCacheDirectoryResolver>((ref) {
  return const ComicCacheDirectoryResolver();
});

final comicCacheManagerFactoryProvider = Provider<ComicCacheManagerFactory>((ref) {
  return const ComicCacheManagerFactory();
});

final comicCacheManagerProvider = FutureProvider<BaseCacheManager>((ref) async {
  // Compatibility provider kept for older comic code/tests.  The actual stage
  // 04 image cache service now owns cache key policy and metadata persistence.
  return ref.watch(image_cache.imageCacheManagerProvider.future);
});
