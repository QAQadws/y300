import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yamibo_forum_client/yamibo_forum_client_contracts.dart';
import 'package:y300/core/network/yamibo_forum_client_provider.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/services/network_comic_reader_service.dart';
import 'package:y300/features/comic/domain/services/comic_first_episode_cover_service.dart';
import 'package:y300/features/comic/domain/services/comic_reader_service.dart';

final comicEpisodeCatalogRepositoryProvider =
    Provider<ComicEpisodeCatalogRepository>((ref) {
      return ref.watch(yamiboForumClientProvider).comicEpisodeCatalog!;
    });

final comicReaderServiceProvider = FutureProvider<ComicReaderService>((
  ref,
) async {
  return NetworkComicReaderService(
    episodeCatalogRepository: ref.read(comicEpisodeCatalogRepositoryProvider),
    imageCacheService: ref.read(imageCacheServiceProvider),
    cacheManager: await ref.read(comicCacheManagerProvider.future),
    imageReferer: ref.read(forumImageRefererProvider),
  );
});

final comicFirstEpisodeCoverServiceProvider =
    Provider<ComicFirstEpisodeCoverService>((ref) {
      return ComicFirstEpisodeCoverService(
        repository: ref.watch(comicRepositoryProvider),
        fetchEpisodeImages: (tid) async {
          final readerService = await ref.read(
            comicReaderServiceProvider.future,
          );
          return readerService.fetchEpisodeImages(tid);
        },
      );
    });
