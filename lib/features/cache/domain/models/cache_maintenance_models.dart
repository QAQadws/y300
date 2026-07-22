import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

enum CacheClearScope { defaultCache, imageCache, pageCache, userCleanup }

class CacheClearRequest {
  const CacheClearRequest({this.scope = CacheClearScope.defaultCache});

  final CacheClearScope scope;
}

class CacheClearResult {
  const CacheClearResult({
    required this.imageCacheCleared,
    required this.deletedDocuments,
    required this.deletedSnapshots,
    required this.deletedProtectedCoverRecords,
    this.deletedImagesByRole = 0,
    this.deletedRegularEntries = 0,
    this.deletedBytes = 0,
    this.failedParticipantIds = const <String>[],
  });

  final bool imageCacheCleared;
  final int deletedDocuments;
  final int deletedSnapshots;
  final int deletedProtectedCoverRecords;

  /// [CacheClearScope.userCleanup] 按 role 清理的图片条数。
  final int deletedImagesByRole;
  final int deletedRegularEntries;
  final int deletedBytes;
  final List<String> failedParticipantIds;

  bool get isPartial => failedParticipantIds.isNotEmpty;

  int get deletedEntries =>
      deletedDocuments +
      deletedSnapshots +
      deletedProtectedCoverRecords +
      deletedImagesByRole +
      deletedRegularEntries;
}

class CachePruneRequest {
  const CachePruneRequest({
    required this.maxCacheBytes,
    this.documentMaxAge = const Duration(days: 30),
    this.runProtectedCoverMaintenance = true,
  });

  final int maxCacheBytes;
  final Duration documentMaxAge;
  final bool runProtectedCoverMaintenance;
}

class CachePruneResult {
  const CachePruneResult({
    required this.deletedDocuments,
    required this.deletedSnapshots,
    required this.deletedProtectedCoverRecords,
    this.deletedCacheEntries = 0,
    this.deletedBytes = 0,
    this.failedParticipantIds = const <String>[],
  });

  final int deletedDocuments;
  final int deletedSnapshots;
  final int deletedProtectedCoverRecords;
  final int deletedCacheEntries;
  final int deletedBytes;
  final List<String> failedParticipantIds;

  bool get isPartial => failedParticipantIds.isNotEmpty;

  int get deletedEntries =>
      deletedDocuments +
      deletedSnapshots +
      deletedProtectedCoverRecords +
      deletedCacheEntries;
}

abstract class CacheMaintenanceService {
  Future<CacheClearResult> clear(CacheClearRequest request);

  Future<CachePruneResult> prune(CachePruneRequest request);

  Future<StorageUsageReport> usageAfterMaintenance();

  Future<CacheCapacityReport> loadCapacityReport();
}
