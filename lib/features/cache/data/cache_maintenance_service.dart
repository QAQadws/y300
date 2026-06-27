import 'package:y300/features/cache/domain/cache_maintenance_models.dart';
import 'package:y300/features/cache/domain/document_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/cache/domain/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/protected_cover_cache_maintenance.dart';
import 'package:y300/features/cache/domain/storage_usage_models.dart';

class DefaultCacheMaintenanceService implements CacheMaintenanceService {
  const DefaultCacheMaintenanceService({
    required ImageCacheService imageCacheService,
    required DocumentCacheService documentCacheService,
    required ParsedSnapshotCacheService snapshotCacheService,
    required StorageAccountingService storageAccountingService,
    ProtectedCoverCacheMaintenance? protectedCoverMaintenance,
    bool Function(CachedImageRecord record)? protectedCoverOwnerExists,
    DateTime Function()? now,
  }) : _imageCacheService = imageCacheService,
       _documentCacheService = documentCacheService,
       _snapshotCacheService = snapshotCacheService,
       _storageAccountingService = storageAccountingService,
       _protectedCoverMaintenance = protectedCoverMaintenance,
       _protectedCoverOwnerExists = protectedCoverOwnerExists,
       _now = now ?? DateTime.now;

  final ImageCacheService _imageCacheService;
  final DocumentCacheService _documentCacheService;
  final ParsedSnapshotCacheService _snapshotCacheService;
  final StorageAccountingService _storageAccountingService;
  final ProtectedCoverCacheMaintenance? _protectedCoverMaintenance;
  final bool Function(CachedImageRecord record)? _protectedCoverOwnerExists;
  final DateTime Function() _now;

  @override
  Future<CacheClearResult> clear(CacheClearRequest request) async {
    var imageCacheCleared = false;
    var deletedDocuments = 0;
    var deletedSnapshots = 0;
    var deletedProtectedCoverRecords = 0;

    switch (request.scope) {
      case CacheClearScope.defaultCache:
        await _imageCacheService.clearUnprotected();
        imageCacheCleared = true;
        deletedDocuments = await _documentCacheService.deleteOlderThan(
          _clearAllCutoff,
        );
        deletedSnapshots = await _snapshotCacheService.deleteExpired(_now());
        deletedProtectedCoverRecords =
            await _runProtectedCoverMaintenanceIfConfigured();
        break;
      case CacheClearScope.imageCache:
        await _imageCacheService.clearUnprotected();
        imageCacheCleared = true;
        break;
      case CacheClearScope.pageCache:
        deletedDocuments = await _documentCacheService.deleteOlderThan(
          _clearAllCutoff,
        );
        deletedSnapshots = await _snapshotCacheService.deleteExpired(
          _clearAllCutoff,
        );
        break;
    }

    return CacheClearResult(
      imageCacheCleared: imageCacheCleared,
      deletedDocuments: deletedDocuments,
      deletedSnapshots: deletedSnapshots,
      deletedProtectedCoverRecords: deletedProtectedCoverRecords,
    );
  }

  @override
  Future<CachePruneResult> prune(CachePruneRequest request) async {
    await _imageCacheService.pruneToLimit(maxBytes: request.imageCacheMaxBytes);
    final now = _now();
    final deletedDocuments = await _documentCacheService.deleteOlderThan(
      now.subtract(request.documentMaxAge),
    );
    final deletedSnapshots = await _snapshotCacheService.deleteExpired(now);
    final deletedProtectedCoverRecords = request.runProtectedCoverMaintenance
        ? await _runProtectedCoverMaintenanceIfConfigured()
        : 0;
    return CachePruneResult(
      deletedDocuments: deletedDocuments,
      deletedSnapshots: deletedSnapshots,
      deletedProtectedCoverRecords: deletedProtectedCoverRecords,
    );
  }

  @override
  Future<StorageUsageReport> usageAfterMaintenance() {
    return _storageAccountingService.loadUsageReport();
  }

  Future<int> _runProtectedCoverMaintenanceIfConfigured() async {
    final maintenance = _protectedCoverMaintenance;
    final ownerExists = _protectedCoverOwnerExists;
    if (maintenance == null || ownerExists == null) {
      return 0;
    }
    final result = await maintenance.cleanInvalidProtectedCovers(
      ownerExists: ownerExists,
    );
    return result.deletedRecords;
  }

  DateTime get _clearAllCutoff => DateTime(9999, 12, 31);
}
