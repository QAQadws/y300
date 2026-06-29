import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

enum CacheClearScope { defaultCache, imageCache, pageCache, userCleanup }

class CacheClearRequest {
  const CacheClearRequest({
    this.scope = CacheClearScope.defaultCache,
    this.imageCacheRoles = const <ImageCacheRole>[],
  });

  final CacheClearScope scope;

  /// 仅 [CacheClearScope.userCleanup] 使用：指定要清理的非保护图片 role。
  /// 为空时由 service 用默认集合（漫画页 / 帖子图片 / 帖子附件图）。
  final List<ImageCacheRole> imageCacheRoles;
}

class CacheClearResult {
  const CacheClearResult({
    required this.imageCacheCleared,
    required this.deletedDocuments,
    required this.deletedSnapshots,
    required this.deletedProtectedCoverRecords,
    this.deletedImagesByRole = 0,
  });

  final bool imageCacheCleared;
  final int deletedDocuments;
  final int deletedSnapshots;
  final int deletedProtectedCoverRecords;

  /// [CacheClearScope.userCleanup] 按 role 清理的图片条数。
  final int deletedImagesByRole;

  int get deletedEntries =>
      deletedDocuments +
      deletedSnapshots +
      deletedProtectedCoverRecords +
      deletedImagesByRole;
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
