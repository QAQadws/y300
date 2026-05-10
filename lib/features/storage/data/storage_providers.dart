import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/features/storage/data/storage_location_repository.dart';
import 'package:y300/features/storage/domain/download_storage_service.dart';

final storageLocationRepositoryProvider = Provider<StorageLocationRepository>((ref) {
  return const StorageLocationRepositoryImpl();
});

final downloadStorageServiceProvider = Provider<DownloadStorageService>((ref) {
  return DefaultDownloadStorageService(
    locationRepository: ref.watch(storageLocationRepositoryProvider),
  );
});
