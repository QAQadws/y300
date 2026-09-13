import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/comic/data/providers/comic_providers.dart';
import 'package:y300/features/comic/data/services/comic_download_cover_maintenance.dart';
import 'package:y300/features/comic/data/services/comic_download_metadata_store.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_migration_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_providers.dart';
import 'package:y300/features/storage/data/storage_providers.dart';

final comicDownloadMetadataStoreProvider = Provider<ComicDownloadMetadataStore>(
  (ref) => ComicDownloadMetadataStore(),
);
final comicDownloadCoverMaintenanceProvider =
    Provider<ComicDownloadCoverMaintenance>((ref) {
      final service = ComicDownloadCoverMaintenance(
        repository: ref.watch(comicRepositoryProvider),
        storage: ref.watch(downloadStorageServiceProvider),
        accessGate: ref.watch(storageRootAccessGateProvider),
        migrator: ref.watch(libraryCoverLegacyMigratorProvider),
        covers: ref.watch(libraryCoverStoreProvider),
        metadata: ref.watch(comicDownloadMetadataStoreProvider),
      );
      ref.onDispose(service.dispose);
      return service;
    });
