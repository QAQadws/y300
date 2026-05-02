import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/comic_cache_directory_provider.dart';
import 'package:y300/features/comic/data/comic_cache_manager_factory.dart';
import 'package:y300/features/comic/data/comic_repository.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local_comic_repository.dart';

final comicRepositoryProvider = Provider<ComicRepository>((ref) {
  return LocalComicRepository(ComicLocalDb.open());
});

final comicCacheDirectoryResolverProvider = Provider<ComicCacheDirectoryResolver>((ref) {
  return const ComicCacheDirectoryResolver();
});

final comicCacheManagerFactoryProvider = Provider<ComicCacheManagerFactory>((ref) {
  return const ComicCacheManagerFactory();
});

final comicCacheManagerProvider = FutureProvider<BaseCacheManager>((ref) async {
  final resolver = ref.read(comicCacheDirectoryResolverProvider);
  final cacheDirectoryPath = await resolver.resolve();
  final factory = ref.read(comicCacheManagerFactoryProvider);
  return factory.create(cacheDirectoryPath: cacheDirectoryPath);
});
