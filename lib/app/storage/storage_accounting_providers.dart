import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:y300/app/storage/storage_accounting_composition.dart';
import 'package:y300/features/cache/data/providers/image_cache_providers.dart';
import 'package:y300/features/cache/data/services/cache_maintenance_service.dart';
import 'package:y300/features/cache/data/services/storage_accounting_service.dart';
import 'package:y300/features/cache/data/services/storage_usage_adapters.dart';
import 'package:y300/features/cache/domain/models/cache_maintenance_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';
import 'package:y300/features/composer_shared/data/providers/composer_draft_providers.dart';
import 'package:y300/features/history/data/providers/history_providers.dart';
import 'package:y300/features/history/data/services/history_storage_accounting_adapter.dart';
import 'package:y300/features/library_shared/data/providers/library_cover_providers.dart';
import 'package:y300/features/library_shared/data/services/library_cover_storage_accounting_adapter.dart';
import 'package:y300/features/profile/data/providers/blog_draft_providers.dart';
import 'package:y300/features/storage/data/download_storage_accounting_adapter.dart';
import 'package:y300/features/storage/data/storage_providers.dart';

final storageAccountingServiceProvider = Provider<StorageAccountingService>((
  ref,
) {
  return DefaultStorageAccountingService(
    adapters: <StorageAccountingAdapter>[
      ImageCacheStorageAccountingAdapter(
        repository: ref.watch(imageCacheRepositoryProvider),
      ),
      LibraryCoverStorageAccountingAdapter(
        thumbnails: ref.watch(libraryCoverThumbnailStoreProvider),
        store: ref.watch(libraryCoverStoreProvider),
      ),
      PageCacheStorageAccountingAdapter(
        documentCacheService: ref.watch(documentCacheServiceProvider),
        snapshotCacheService: ref.watch(parsedSnapshotCacheServiceProvider),
      ),
      composeComposerDraftStorageAccountingAdapter(
        databaseProvider: ref.watch(composerDraftDatabaseManagerProvider).open,
        blogDraftRepository: ref.watch(blogDraftRepositoryProvider),
      ),
      DownloadStorageAccountingAdapter(
        storageService: ref.watch(downloadStorageServiceProvider),
        storageRootAccessGate: ref.watch(storageRootAccessGateProvider),
      ),
      composeLibraryMetadataStorageAccountingAdapter(),
      HistoryStorageAccountingAdapter(
        databaseProvider: ref.watch(historyDatabaseManagerProvider).open,
      ),
    ],
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
