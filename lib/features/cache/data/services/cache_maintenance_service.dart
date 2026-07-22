import 'package:y300/features/cache/domain/models/cache_maintenance_models.dart';
import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';
import 'package:y300/features/cache/data/services/cache_budget_coordinator.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/services/protected_cover_cache_maintenance.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

class DefaultCacheMaintenanceService implements CacheMaintenanceService {
  DefaultCacheMaintenanceService({
    required ImageCacheService imageCacheService,
    required DocumentCacheService documentCacheService,
    required ParsedSnapshotCacheService snapshotCacheService,
    required StorageAccountingService storageAccountingService,
    required CacheBudgetCoordinator cacheBudgetCoordinator,
    ProtectedCoverCacheMaintenance? protectedCoverMaintenance,
    bool Function(CachedImageRecord record)? protectedCoverOwnerExists,
    DateTime Function()? now,
  }) : _imageCacheService = imageCacheService,
       _documentCacheService = documentCacheService,
       _snapshotCacheService = snapshotCacheService,
       _storageAccountingService = storageAccountingService,
       _cacheBudgetCoordinator = cacheBudgetCoordinator,
       _protectedCoverMaintenance = protectedCoverMaintenance,
       _protectedCoverOwnerExists = protectedCoverOwnerExists,
       _now = now ?? DateTime.now;

  final ImageCacheService _imageCacheService;
  final DocumentCacheService _documentCacheService;
  final ParsedSnapshotCacheService _snapshotCacheService;
  final StorageAccountingService _storageAccountingService;
  final CacheBudgetCoordinator _cacheBudgetCoordinator;
  final ProtectedCoverCacheMaintenance? _protectedCoverMaintenance;
  final bool Function(CachedImageRecord record)? _protectedCoverOwnerExists;
  final DateTime Function() _now;

  @override
  Future<CacheClearResult> clear(CacheClearRequest request) async {
    var imageCacheCleared = false;
    var deletedDocuments = 0;
    var deletedSnapshots = 0;
    var deletedProtectedCoverRecords = 0;
    var deletedImagesByRole = 0;
    var deletedRegularEntries = 0;
    var deletedBytes = 0;
    var failedParticipantIds = const <String>[];

    switch (request.scope) {
      case CacheClearScope.defaultCache:
        final budget = await _cacheBudgetCoordinator.clearRegular();
        imageCacheCleared = true;
        deletedRegularEntries = budget.deletedEntries;
        deletedBytes = budget.deletedBytes;
        failedParticipantIds = budget.failedParticipantIds;
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
      case CacheClearScope.userCleanup:
        final budget = await _cacheBudgetCoordinator.clearRegular();
        imageCacheCleared = true;
        deletedRegularEntries = budget.deletedEntries;
        deletedBytes = budget.deletedBytes;
        failedParticipantIds = budget.failedParticipantIds;
        break;
    }

    return CacheClearResult(
      imageCacheCleared: imageCacheCleared,
      deletedDocuments: deletedDocuments,
      deletedSnapshots: deletedSnapshots,
      deletedProtectedCoverRecords: deletedProtectedCoverRecords,
      deletedImagesByRole: deletedImagesByRole,
      deletedRegularEntries: deletedRegularEntries,
      deletedBytes: deletedBytes,
      failedParticipantIds: failedParticipantIds,
    );
  }

  @override
  Future<CachePruneResult> prune(CachePruneRequest request) async {
    final now = _now();
    final deletedDocuments = await _documentCacheService.deleteOlderThan(
      now.subtract(request.documentMaxAge),
    );
    final deletedSnapshots = await _snapshotCacheService.deleteExpired(now);
    final deletedProtectedCoverRecords = request.runProtectedCoverMaintenance
        ? await _runProtectedCoverMaintenanceIfConfigured()
        : 0;
    final budget = await _cacheBudgetCoordinator.pruneToLimit(
      maxBytes: request.maxCacheBytes,
    );
    return CachePruneResult(
      deletedDocuments: deletedDocuments,
      deletedSnapshots: deletedSnapshots,
      deletedProtectedCoverRecords: deletedProtectedCoverRecords,
      deletedCacheEntries: budget.deletedEntries,
      deletedBytes: budget.deletedBytes,
      failedParticipantIds: budget.failedParticipantIds,
    );
  }

  @override
  Future<StorageUsageReport> usageAfterMaintenance() {
    return _storageAccountingService.loadUsageReport();
  }

  @override
  Future<CacheCapacityReport> loadCapacityReport() {
    return _cacheBudgetCoordinator.loadReport();
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
