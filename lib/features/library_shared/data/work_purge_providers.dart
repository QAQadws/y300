import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/cache/data/image_cache_providers.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_refresh_workflow_providers.dart';
import 'package:y300/features/favorites/data/favorite_providers.dart';
import 'package:y300/features/library_shared/data/default_work_purge_service.dart';
import 'package:y300/features/library_shared/data/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/services/work_purge_service.dart';
import 'package:y300/features/novel/data/novel_providers.dart';
import 'package:y300/features/storage/data/storage_providers.dart';

final workPurgeServiceProvider = Provider<WorkPurgeService>((ref) {
  final comicRepository = ref.watch(comicRepositoryProvider);
  final novelRepository = ref.watch(novelRepositoryProvider);
  final libraryStateRepository = ref.watch(libraryStateRepositoryProvider);
  final favoriteRepository = ref.watch(localFavoriteRepositoryProvider);
  final imageCacheService = ref.watch(imageCacheServiceProvider);
  final downloadStorageService = ref.watch(downloadStorageServiceProvider);
  final comicQueueRepository = ref.watch(comicSearchRefreshQueueRepositoryProvider);

  return DefaultWorkPurgeService(
    purgeComicWork: ({required comicId}) {
      return comicRepository.purgeWork(comicId: comicId);
    },
    purgeNovelWork: ({required novelId}) {
      return novelRepository.purgeWork(novelId: novelId);
    },
    purgeLibraryWorkState: ({
      required moduleKey,
      required workId,
    }) {
      return libraryStateRepository.purgeWorkState(
        moduleKey: moduleKey,
        workId: workId,
      );
    },
    markFavoriteRemovedByWorkId: favoriteRepository.markRemovedByWorkId,
    deleteCacheByOwner: ({
      required ownerType,
      required ownerId,
    }) {
      return imageCacheService.deleteByOwner(
        ownerType: ownerType,
        ownerId: ownerId,
      );
    },
    deleteComicDownloads: ({required workId}) {
      return downloadStorageService.deleteComicDownloads(workId: workId);
    },
    deleteNovelDownloads: ({required novelId}) {
      return downloadStorageService.deleteNovelDownloads(novelId: novelId);
    },
    deleteComicQueueByComicId: comicQueueRepository.deleteByComicId,
  );
});
