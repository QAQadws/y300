import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/preferences/preferences_providers.dart';
import 'package:y300/features/storage/data/storage_location_repository.dart';
import 'package:y300/features/storage/data/storage_root_migration_checkpoint_store.dart';
import 'package:y300/features/storage/data/transactional_storage_root_migration_coordinator.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';
import 'package:y300/features/storage/domain/storage_root_migration.dart';

final storageLocationRepositoryProvider = Provider<StorageLocationRepository>((
  ref,
) {
  return StorageLocationRepositoryImpl(
    preferencesStore: ref.watch(preferencesStoreProvider),
  );
});

final downloadStorageServiceProvider = Provider<DownloadStorageService>((ref) {
  return DefaultDownloadStorageService(
    locationRepository: ref.watch(storageLocationRepositoryProvider),
  );
});

final storageRootMigrationCheckpointStoreProvider =
    Provider<StorageRootMigrationCheckpointStore>((ref) {
      return SharedPreferencesStorageRootMigrationCheckpointStore(
        preferencesStore: ref.watch(preferencesStoreProvider),
      );
    });

/// Dormant until storage access gating is installed by cache migration slice 2.
final storageRootMigrationCoordinatorProvider =
    Provider<StorageRootMigrationCoordinator>((ref) {
      return TransactionalStorageRootMigrationCoordinator(
        locationRepository: ref.watch(storageLocationRepositoryProvider),
        checkpointStore: ref.watch(storageRootMigrationCheckpointStoreProvider),
      );
    });
