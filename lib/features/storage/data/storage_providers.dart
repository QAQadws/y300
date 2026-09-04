import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/features/storage/data/default_storage_root_access_gate.dart';
import 'package:y300/features/storage/data/migration_gated_download_storage_service.dart';
import 'package:y300/features/storage/data/storage_location_repository.dart';
import 'package:y300/features/storage/data/storage_root_migration_checkpoint_store.dart';
import 'package:y300/features/storage/data/transactional_storage_root_migration_coordinator.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/storage/domain/storage_root_access_gate.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';

final storageLocationRepositoryProvider = Provider<StorageLocationRepository>((
  ref,
) {
  return StorageLocationRepositoryImpl(
    preferencesStore: ref.watch(preferencesStoreProvider),
  );
});

final _rawDownloadStorageServiceProvider = Provider<DownloadStorageService>((
  ref,
) {
  return DefaultDownloadStorageService(
    locationRepository: ref.watch(storageLocationRepositoryProvider),
  );
});

final downloadStorageServiceProvider = Provider<DownloadStorageService>((ref) {
  return MigrationGatedDownloadStorageService(
    delegate: ref.watch(_rawDownloadStorageServiceProvider),
    accessGate: ref.watch(storageRootAccessGateProvider),
  );
});

final storageRootMigrationCheckpointStoreProvider =
    Provider<StorageRootMigrationCheckpointStore>((ref) {
      return SharedPreferencesStorageRootMigrationCheckpointStore(
        preferencesStore: ref.watch(preferencesStoreProvider),
      );
    });

final storageRootMigrationCoordinatorProvider =
    Provider<StorageRootMigrationCoordinator>((ref) {
      return TransactionalStorageRootMigrationCoordinator(
        locationRepository: ref.watch(storageLocationRepositoryProvider),
        checkpointStore: ref.watch(storageRootMigrationCheckpointStoreProvider),
      );
    });

final storageRootAccessGateProvider = Provider<StorageRootAccessGate>((ref) {
  return DefaultStorageRootAccessGate(
    migrationCoordinator: ref.watch(storageRootMigrationCoordinatorProvider),
  );
});
