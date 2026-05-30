import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/comic_refresh_outcome_providers.dart';
import 'package:y300/features/comic/data/comic_search_refresh_queue_repository.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/local_comic_search_refresh_queue_repository.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';

final comicSearchRefreshQueueRepositoryProvider =
    Provider<ComicSearchRefreshQueueRepository>((ref) {
  return LocalComicSearchRefreshQueueRepository.lazy(() => ComicLocalDb.open());
});

final comicSearchRefreshQueueServiceProvider =
    Provider<ComicSearchRefreshQueueService>((ref) {
  final service = ComicSearchRefreshQueueService(
    queueRepository: ref.watch(comicSearchRefreshQueueRepositoryProvider),
    refreshService: ref.watch(comicEpisodeRefreshServiceProvider),
    refreshOutcomeApplier: ref.watch(comicRefreshOutcomeApplierProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final comicSearchRefreshQueueSnapshotProvider =
    Provider<ValueListenable<ComicSearchRefreshQueueSnapshot>>((ref) {
  return ref.watch(comicSearchRefreshQueueServiceProvider).snapshot;
});
