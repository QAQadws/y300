import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/comic_providers.dart';
import 'package:y300/features/comic/data/comic_search_refresh_queue_repository.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local_comic_search_refresh_queue_repository.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

final comicSearchRefreshQueueRepositoryProvider =
    Provider<ComicSearchRefreshQueueRepository>((ref) {
  return LocalComicSearchRefreshQueueRepository(ComicLocalDb.open());
});

final comicSearchRefreshQueueServiceProvider =
    Provider<ComicSearchRefreshQueueService>((ref) {
  final service = ComicSearchRefreshQueueService(
    queueRepository: ref.watch(comicSearchRefreshQueueRepositoryProvider),
    comicRepository: ref.watch(comicRepositoryProvider),
    refreshService: ref.watch(comicEpisodeRefreshServiceProvider),
    firstEpisodeCoverPromoter: ref.watch(comicFirstEpisodeCoverServiceProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
