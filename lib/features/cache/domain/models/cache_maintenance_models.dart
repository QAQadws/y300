import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

enum CacheClearScope { defaultCache, imageCache, pageCache }

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
  });

  final bool imageCacheCleared;
  final int deletedDocuments;
  final int deletedSnapshots;
  final int deletedProtectedCoverRecords;

  int get deletedEntries =>
      deletedDocuments + deletedSnapshots + deletedProtectedCoverRecords;
}

class CachePruneRequest {
  const CachePruneRequest({
    required this.imageCacheMaxBytes,
    this.documentMaxAge = const Duration(days: 30),
    this.runProtectedCoverMaintenance = true,
  });

  final int imageCacheMaxBytes;
  final Duration documentMaxAge;
  final bool runProtectedCoverMaintenance;
}

class CachePruneResult {
  const CachePruneResult({
    required this.deletedDocuments,
    required this.deletedSnapshots,
    required this.deletedProtectedCoverRecords,
  });

  final int deletedDocuments;
  final int deletedSnapshots;
  final int deletedProtectedCoverRecords;

  int get deletedEntries =>
      deletedDocuments + deletedSnapshots + deletedProtectedCoverRecords;
}

abstract class CacheMaintenanceService {
  Future<CacheClearResult> clear(CacheClearRequest request);

  Future<CachePruneResult> prune(CachePruneRequest request);

  Future<StorageUsageReport> usageAfterMaintenance();
}
