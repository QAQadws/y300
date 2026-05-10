import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/protected_cover_cache_maintenance.dart';

void main() {
  test('ProtectedCoverCacheMaintenance deletes orphan and stale protected covers', () async {
    final repository = _MemoryImageCacheRepository();
    final fileStore = _MemoryProtectedCoverFileStore();
    final now = DateTime(2026, 1, 1);
    fileStore.existingPaths.add('/cache/orphan.jpg');
    repository.records['cover/comic/missing-file'] = _record(
      cacheKey: 'cover/comic/missing-file',
      ownerId: 'missing-file',
      localPath: null,
      now: now,
    );
    repository.records['cover/comic/orphan'] = _record(
      cacheKey: 'cover/comic/orphan',
      ownerId: 'orphan',
      localPath: '/cache/orphan.jpg',
      now: now,
    );

    final maintenance = ProtectedCoverCacheMaintenance(
      repository: repository,
      fileStore: fileStore,
    );
    final result = await maintenance.cleanInvalidProtectedCovers(
      ownerExists: (record) => record.ownerId == 'missing-file',
    );

    expect(result.deletedRecords, 2);
    expect(result.staleRecords, 1);
    expect(repository.records, isEmpty);
    expect(fileStore.existingPaths, isEmpty);
  });
}

CachedImageRecord _record({
  required String cacheKey,
  required String ownerId,
  required String? localPath,
  required DateTime now,
}) {
  return CachedImageRecord(
    cacheKey: cacheKey,
    ownerType: ImageCacheOwnerType.comic.dbValue,
    ownerId: ownerId,
    role: ImageCacheRole.cover.dbValue,
    localPath: localPath,
    bytes: 10,
    protected: true,
    createdAt: now,
    updatedAt: now,
  );
}

class _MemoryImageCacheRepository implements ProtectedCoverCacheStore {
  final records = <String, CachedImageRecord>{};

  @override
  Future<void> deleteByKey(String cacheKey) async {
    records.remove(cacheKey);
  }

  @override
  Future<List<CachedImageRecord>> listProtectedCovers() async {
    return records.values.where((record) => record.protected).toList(growable: false);
  }
}

class _MemoryProtectedCoverFileStore implements ProtectedCoverFileStore {
  final existingPaths = <String>{};

  @override
  Future<void> delete(String localPath) async {
    existingPaths.remove(localPath);
  }

  @override
  Future<bool> exists(String localPath) async {
    return existingPaths.contains(localPath);
  }
}
