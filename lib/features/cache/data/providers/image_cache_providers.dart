import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/core/config/app_config.dart';
import 'package:y300/core/media/encoded_image_dimension_probe.dart';
import 'package:y300/core/network/yamibo_forum_transport_providers.dart';
import 'package:y300/features/cache/data/services/cache_diagnostic_export_service.dart';
import 'package:y300/features/cache/data/services/cache_budget_coordinator.dart';
import 'package:y300/features/cache/data/services/cache_mutation_bus.dart';
import 'package:y300/features/cache/data/services/cache_maintenance_service.dart';
import 'package:y300/features/cache/data/services/default_image_cache_service.dart';
import 'package:y300/features/cache/data/services/document_cache_service.dart';
import 'package:y300/features/cache/data/providers/image_cache_directory_provider.dart';
import 'package:y300/features/cache/data/services/image_cache_manager_factory.dart';
import 'package:y300/features/cache/data/services/image_cache_diagnostic_recorder.dart';
import 'package:y300/features/cache/data/services/y300_forum_resource_file_service.dart';
import 'package:y300/features/cache/data/repositories/image_cache_repository.dart';
import 'package:y300/features/cache/data/services/parsed_snapshot_cache_service.dart';
import 'package:y300/features/cache/data/services/protected_cover_file_store.dart';
import 'package:y300/features/cache/data/services/storage_accounting_service.dart';
import 'package:y300/features/cache/data/services/storage_usage_adapters.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';
import 'package:y300/features/cache/domain/models/cache_maintenance_models.dart';
import 'package:y300/features/cache/domain/models/cache_diagnostic_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/domain/services/native_page_cache_invalidation_service.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/services/protected_cover_cache_maintenance.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/composer_shared/data/providers/composer_draft_providers.dart';
import 'package:y300/features/history/data/providers/history_providers.dart';
import 'package:y300/features/cache/presentation/services/default_forum_image_precache_service.dart';
import 'package:y300/features/comic/data/local/comic_local_db.dart';
import 'package:y300/features/storage/data/storage_providers.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_providers.dart';

final imageCacheDirectoryResolverProvider =
    Provider<ImageCacheDirectoryResolver>((ref) {
      return const ImageCacheDirectoryResolver();
    });

final imageCacheManagerFactoryProvider = Provider<ImageCacheManagerFactory>((
  ref,
) {
  return ImageCacheManagerFactory(
    fileService: Y300ForumResourceFileService(
      client: ref.watch(yamiboForumResourceClientProvider),
      siteOrigin: Uri.parse(AppConfig.siteBaseUrl),
    ),
  );
});

final imageCacheManagerProvider = FutureProvider<BaseCacheManager>((ref) async {
  final resolver = ref.read(imageCacheDirectoryResolverProvider);
  final root = await resolver.resolveImageCacheRoot();
  return ref
      .read(imageCacheManagerFactoryProvider)
      .create(cacheDirectoryPath: root);
});

final imageCacheRepositoryProvider = Provider<ImageCacheRepository>((ref) {
  return LocalImageCacheRepository.lazy(() => ComicLocalDb.open());
});

final imageCacheDiagnosticRecorderProvider =
    Provider<ImageCacheDiagnosticRecorder>((ref) {
      if (!kDebugMode) {
        return const NoopImageCacheDiagnosticRecorder();
      }
      return LoggerImageCacheDiagnosticRecorder(ref.watch(loggerProvider));
    });

final encodedImageDimensionProbeProvider = Provider<EncodedImageDimensionProbe>(
  (ref) {
    return SerialEncodedImageDimensionProbe();
  },
);

final cacheMutationBusProvider = Provider<CacheMutationBus>((ref) {
  final bus = CacheMutationBus();
  ref.onDispose(() => unawaited(bus.dispose()));
  return bus;
});

final documentCacheServiceProvider = Provider<DocumentCacheService>((ref) {
  return LocalDocumentCacheService.lazy(
    // The thread repository can be created by a widget test before the
    // platform database factory is installed. Open the database on first use.
    // The service memoizes the resulting Future, so this remains one DB
    // session rather than a new open attempt per cache operation.
    () => ComicLocalDb.open(),
    mutationReporter: ref.watch(cacheMutationBusProvider),
  );
});

final parsedSnapshotCacheServiceProvider = Provider<ParsedSnapshotCacheService>(
  (ref) {
    return LocalParsedSnapshotCacheService.lazy(
      () => ComicLocalDb.open(),
      mutationReporter: ref.watch(cacheMutationBusProvider),
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
    mutationReporter: ref.watch(cacheMutationBusProvider),
    diagnosticRecorder: ref.watch(imageCacheDiagnosticRecorderProvider),
  );
});

final forumImageRequestResolverProvider = Provider<ForumImageRequestResolver>((
  ref,
) {
  return const DefaultForumImageRequestResolver();
});

final forumImageDimensionIndexProvider = Provider<ForumImageDimensionIndex>((
  ref,
) {
  return CacheRecordForumImageDimensionIndex(
    imageCacheService: ref.watch(imageCacheServiceProvider),
    imageRequestResolver: ref.watch(forumImageRequestResolverProvider),
  );
});

final forumImagePrecacheServiceProvider = Provider<ForumImagePrecacheService>((
  ref,
) {
  return DefaultForumImagePrecacheService(
    imageCacheService: ref.watch(imageCacheServiceProvider),
    imageRequestResolver: ref.watch(forumImageRequestResolverProvider),
  );
});

final cacheDiagnosticExportServiceProvider =
    Provider<CacheDiagnosticExportService>((ref) {
      return JsonCacheDiagnosticExportService(
        storageService: ref.watch(downloadStorageServiceProvider),
        storageRootAccessGate: ref.watch(storageRootAccessGateProvider),
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
    cacheBudgetCoordinator: ref.watch(cacheBudgetCoordinatorProvider),
    protectedCoverMaintenance: ref.watch(
      protectedCoverCacheMaintenanceProvider,
    ),
    protectedCoverOwnerExists: (_) => true,
  );
});

final cacheBudgetCoordinatorProvider = Provider<CacheBudgetCoordinator>((ref) {
  final services = <Object>[
    ref.watch(imageCacheServiceProvider),
    ref.watch(documentCacheServiceProvider),
    ref.watch(parsedSnapshotCacheServiceProvider),
  ];
  return CacheBudgetCoordinator(
    participants: services.whereType<CacheBudgetParticipant>().toList(
      growable: false,
    ),
  );
});

final storageAccountingServiceProvider = Provider<StorageAccountingService>((
  ref,
) {
  final imageCacheRepository = ref.watch(imageCacheRepositoryProvider);
  return DefaultStorageAccountingService(
    adapters: <StorageAccountingAdapter>[
      ImageCacheStorageAccountingAdapter(repository: imageCacheRepository),
      LibraryCoverStorageAccountingAdapter(
        store: ref.watch(libraryCoverStoreProvider),
      ),
      PageCacheStorageAccountingAdapter(
        documentCacheService: ref.watch(documentCacheServiceProvider),
        snapshotCacheService: ref.watch(parsedSnapshotCacheServiceProvider),
      ),
      ComposerDraftStorageAccountingAdapter(
        databaseProvider: ref.watch(composerDraftDatabaseManagerProvider).open,
      ),
      DownloadStorageAccountingAdapter(
        storageService: ref.watch(downloadStorageServiceProvider),
        storageRootAccessGate: ref.watch(storageRootAccessGateProvider),
      ),
      const LibraryMetadataStorageAccountingAdapter(),
      HistoryStorageAccountingAdapter(
        databaseProvider: ref.watch(historyDatabaseManagerProvider).open,
      ),
    ],
  );
});
