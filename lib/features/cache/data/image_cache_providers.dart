import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/network/network_providers.dart';
import 'package:y300/features/cache/data/cache_diagnostic_export_service.dart';
import 'package:y300/features/cache/data/cache_diagnostic_recorder.dart';
import 'package:y300/features/cache/data/cache_maintenance_service.dart';
import 'package:y300/features/cache/data/default_image_cache_service.dart';
import 'package:y300/features/cache/data/document_cache_service.dart';
import 'package:y300/features/cache/data/image_cache_directory_provider.dart';
import 'package:y300/features/cache/data/image_cache_manager_factory.dart';
import 'package:y300/features/cache/data/image_cache_repository.dart';
import 'package:y300/features/cache/data/parsed_snapshot_cache_service.dart';
import 'package:y300/features/cache/data/protected_cover_file_store.dart';
import 'package:y300/features/cache/data/storage_accounting_service.dart';
import 'package:y300/features/cache/data/storage_usage_adapters.dart';
import 'package:y300/features/cache/domain/document_cache_models.dart';
import 'package:y300/features/cache/domain/cache_maintenance_models.dart';
import 'package:y300/features/cache/domain/cache_diagnostic_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/cache/domain/native_page_cache_invalidation_service.dart';
import 'package:y300/features/cache/domain/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/protected_cover_cache_maintenance.dart';
import 'package:y300/features/cache/domain/storage_usage_models.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/library_shared/data/sync_diagnostic_providers.dart';
import 'package:y300/features/storage/data/storage_providers.dart';

final imageCacheDirectoryResolverProvider =
    Provider<ImageCacheDirectoryResolver>((ref) {
      return const ImageCacheDirectoryResolver();
    });

final imageCacheManagerFactoryProvider = Provider<ImageCacheManagerFactory>((
  ref,
) {
  return const ImageCacheManagerFactory();
});

final imageCacheManagerProvider = FutureProvider<BaseCacheManager>((ref) async {
  final resolver = ref.read(imageCacheDirectoryResolverProvider);
  final root = await resolver.resolveImageCacheRoot();
  return ref
      .read(imageCacheManagerFactoryProvider)
      .create(cacheDirectoryPath: root);
});

final imageCacheRepositoryProvider = Provider<ImageCacheRepository>((ref) {
  return LocalImageCacheRepository(ComicLocalDb.open());
});

final documentCacheServiceProvider = Provider<DocumentCacheService>((ref) {
  return LocalDocumentCacheService(
    ComicLocalDb.open(),
    diagnosticRecorder: ref.watch(cacheDiagnosticRecorderProvider),
  );
});

final parsedSnapshotCacheServiceProvider = Provider<ParsedSnapshotCacheService>(
  (ref) {
    return LocalParsedSnapshotCacheService(
      ComicLocalDb.open(),
      diagnosticRecorder: ref.watch(cacheDiagnosticRecorderProvider),
    );
  },
);

final nativePageCacheInvalidationServiceProvider =
    Provider<NativePageCacheInvalidationService>((ref) {
      return DefaultNativePageCacheInvalidationService(
        documentCache: ref.watch(documentCacheServiceProvider),
        snapshotCache: ref.watch(parsedSnapshotCacheServiceProvider),
      );
    });

final protectedCoverFileStoreProvider = Provider<ProtectedCoverFileStore>((
  ref,
) {
  return const LocalProtectedCoverFileStore();
});

final protectedCoverCacheMaintenanceProvider =
    Provider<ProtectedCoverCacheMaintenance>((ref) {
      return ProtectedCoverCacheMaintenance(
        repository: ref.watch(imageCacheRepositoryProvider),
        fileStore: ref.watch(protectedCoverFileStoreProvider),
      );
    });

final imageCacheServiceProvider = Provider<ImageCacheService>((ref) {
  return DefaultImageCacheService(
    repository: ref.watch(imageCacheRepositoryProvider),
    cacheManagerFuture: ref.watch(imageCacheManagerProvider.future),
    directoryResolver: ref.watch(imageCacheDirectoryResolverProvider),
    headerBuilder: ref.watch(imageRequestHeaderBuilderProvider),
    diagnosticRecorder: ref.watch(cacheDiagnosticRecorderProvider),
  );
});

final cacheDiagnosticRecorderProvider = Provider<CacheDiagnosticRecorder>((
  ref,
) {
  return SyncCacheDiagnosticRecorder(ref.watch(syncDiagnosticRecorderProvider));
});

final cacheDiagnosticExportServiceProvider =
    Provider<CacheDiagnosticExportService>((ref) {
      return JsonCacheDiagnosticExportService(
        storageService: ref.watch(downloadStorageServiceProvider),
      );
    });

final cacheMaintenanceServiceProvider = Provider<CacheMaintenanceService>((
  ref,
) {
  return DefaultCacheMaintenanceService(
    imageCacheService: ref.watch(imageCacheServiceProvider),
    documentCacheService: ref.watch(documentCacheServiceProvider),
    snapshotCacheService: ref.watch(parsedSnapshotCacheServiceProvider),
    storageAccountingService: ref.watch(storageAccountingServiceProvider),
    protectedCoverMaintenance: ref.watch(
      protectedCoverCacheMaintenanceProvider,
    ),
    protectedCoverOwnerExists: (_) => true,
    diagnosticRecorder: ref.watch(cacheDiagnosticRecorderProvider),
  );
});

final storageAccountingServiceProvider = Provider<StorageAccountingService>((
  ref,
) {
  final imageCacheRepository = ref.watch(imageCacheRepositoryProvider);
  return DefaultStorageAccountingService(
    adapters: <StorageAccountingAdapter>[
      ImageCacheStorageAccountingAdapter(repository: imageCacheRepository),
      PageCacheStorageAccountingAdapter(
        documentCacheService: ref.watch(documentCacheServiceProvider),
        snapshotCacheService: ref.watch(parsedSnapshotCacheServiceProvider),
      ),
      const ComposerDraftStorageAccountingAdapter(),
      DownloadStorageAccountingAdapter(
        storageService: ref.watch(downloadStorageServiceProvider),
      ),
      const LibraryMetadataStorageAccountingAdapter(),
    ],
  );
});
