import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/services/comic_favorite_auto_refresh_coordinator.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/repositories/comic_search_refresh_queue_repository.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/local_comic_search_refresh_queue_repository.dart';
import 'package:y300/features/comic/domain/services/comic_refresh_outcome_applier.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_search_refresh_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_services_impl.dart';
import 'package:y300/features/library_shared/data/providers/sync_diagnostic_providers.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';

final comicRefreshOutcomeApplierProvider =
    Provider<ComicRefreshOutcomeApplier>((ref) {
  return DefaultComicRefreshOutcomeApplier(
    repository: ref.watch(comicRepositoryProvider),
    firstEpisodeCoverPromoter: ref.watch(comicFirstEpisodeCoverServiceProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
  );
});

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
    diagnosticRecorder: ref.watch(syncDiagnosticRecorderProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final comicSearchRefreshQueueSnapshotProvider =
    Provider<ValueListenable<ComicSearchRefreshQueueSnapshot>>((ref) {
  return ref.watch(comicSearchRefreshQueueServiceProvider).snapshot;
});

final comicFavoriteAutoRefreshCoordinatorProvider =
    Provider<ComicFavoriteAutoRefreshCoordinator>((ref) {
  return ComicFavoriteAutoRefreshCoordinator(
    refreshService: ref.watch(comicEpisodeRefreshServiceProvider),
    searchQueue: ref.watch(comicSearchRefreshQueueServiceProvider),
    refreshOutcomeApplier: ref.watch(comicRefreshOutcomeApplierProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
    catalogMissPolicy: ref.watch(comicCatalogMissPolicyProvider),
    titleAnalyzer: ref.watch(comicTitleAnalyzerProvider),
    diagnosticRecorder: ref.watch(syncDiagnosticRecorderProvider),
    catalogUrlUpdater: ref.watch(comicRepositoryProvider),
  );
});
