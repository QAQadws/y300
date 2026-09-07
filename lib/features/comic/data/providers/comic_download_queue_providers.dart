import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/comic/data/repositories/comic_download_queue_repository.dart';
import 'package:y300/features/comic/data/repositories/local_comic_download_queue_repository.dart';
import 'package:y300/features/comic/data/services/comic_download_service.dart';
import 'package:y300/features/comic/domain/models/comic_download_queue_models.dart';
import 'package:y300/features/comic/domain/services/comic_download_queue_service.dart';
import 'package:y300/features/comic/domain/services/comic_download_queue.dart';
import 'package:y300/features/library_shared/data/providers/library_state_providers.dart';
import 'package:y300/features/library_shared/domain/services/library_shelf_refresh_bus.dart';
import 'package:y300/features/storage/data/storage_providers.dart';

final comicDownloadQueueRepositoryProvider =
    Provider<ComicDownloadQueueRepository>((ref) {
      return LocalComicDownloadQueueRepository.lazy(() => ComicLocalDb.open());
    });

final _comicDownloadQueueSnapshotNotifierProvider =
    Provider<ValueNotifier<ComicDownloadQueueSnapshot>>((ref) {
      final notifier = ValueNotifier<ComicDownloadQueueSnapshot>(
        ComicDownloadQueueSnapshot.empty,
      );
      ref.onDispose(notifier.dispose);
      return notifier;
    });

final comicDownloadQueueServiceProvider = Provider<ComicDownloadQueueService>((
  ref,
) {
  final service = ComicDownloadQueueService(
    queueRepository: ref.watch(comicDownloadQueueRepositoryProvider),
    downloadService: ref.watch(comicDownloadServiceProvider),
    libraryStateRepository: ref.watch(libraryStateRepositoryProvider),
    shelfRefreshBus: ref.watch(libraryShelfRefreshBusProvider),
    storageRootAccessGate: ref.watch(storageRootAccessGateProvider),
    snapshotNotifier: ref.watch(_comicDownloadQueueSnapshotNotifierProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final comicDownloadQueueProvider = Provider<ComicDownloadQueue>((ref) {
  return ref.watch(comicDownloadQueueServiceProvider);
});

final comicDownloadQueueSnapshotProvider =
    Provider<ValueListenable<ComicDownloadQueueSnapshot>>((ref) {
      return ref.watch(_comicDownloadQueueSnapshotNotifierProvider);
    });
