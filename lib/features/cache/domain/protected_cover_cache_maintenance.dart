import 'package:y300/features/cache/domain/image_cache_models.dart';

abstract class ProtectedCoverCacheStore {
  Future<List<CachedImageRecord>> listProtectedCovers();

  Future<void> deleteByKey(String cacheKey);
}

abstract class ProtectedCoverFileStore {
  Future<bool> exists(String localPath);

  Future<void> delete(String localPath);
}

class ProtectedCoverMaintenanceResult {
  const ProtectedCoverMaintenanceResult({
    required this.deletedRecords,
    required this.staleRecords,
  });

  final int deletedRecords;
  final int staleRecords;
}

/// Small maintenance policy for protected shelf covers.
///
/// It deliberately depends on a tiny store contract, not ImageCacheService, so
/// existing cache service callers and tests do not need to implement more
/// methods. File access is injected as another tiny port to keep this domain
/// policy independent from dart:io and easier to review in tests.
class ProtectedCoverCacheMaintenance {
  const ProtectedCoverCacheMaintenance({
    required ProtectedCoverCacheStore repository,
    required ProtectedCoverFileStore fileStore,
  })  : _repository = repository,
        _fileStore = fileStore;

  final ProtectedCoverCacheStore _repository;
  final ProtectedCoverFileStore _fileStore;

  Future<ProtectedCoverMaintenanceResult> cleanInvalidProtectedCovers({
    required bool Function(CachedImageRecord record) ownerExists,
  }) async {
    final records = await _repository.listProtectedCovers();
    var deleted = 0;
    var stale = 0;
    for (final record in records) {
      final localPath = record.localPath?.trim();
      final missingFile = localPath == null || localPath.isEmpty || !await _fileStore.exists(localPath);
      if (!ownerExists(record) || missingFile) {
        await _deleteLocalFile(localPath);
        await _repository.deleteByKey(record.cacheKey);
        deleted += 1;
        if (missingFile) {
          stale += 1;
        }
      }
    }
    return ProtectedCoverMaintenanceResult(
      deletedRecords: deleted,
      staleRecords: stale,
    );
  }

  Future<void> _deleteLocalFile(String? localPath) async {
    final path = localPath?.trim();
    if (path == null || path.isEmpty) {
      return;
    }
    if (await _fileStore.exists(path)) {
      await _fileStore.delete(path);
    }
  }
}
