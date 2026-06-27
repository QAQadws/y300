import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/cache_maintenance_service.dart';
import 'package:y300/features/cache/domain/cache_maintenance_models.dart';
import 'package:y300/features/cache/domain/document_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';
import 'package:y300/features/cache/domain/image_cache_service.dart';
import 'package:y300/features/cache/domain/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/storage_usage_models.dart';

void main() {
  test('clear default cache clears only ordinary cache domains', () async {
    final imageCache = _FakeImageCacheService();
    final documentCache = _FakeDocumentCacheService(deleteOlderThanResult: 2);
    final snapshotCache = _FakeSnapshotCacheService(deleteExpiredResult: 3);
    final service = DefaultCacheMaintenanceService(
      imageCacheService: imageCache,
      documentCacheService: documentCache,
      snapshotCacheService: snapshotCache,
      storageAccountingService: const _FakeStorageAccountingService(),
      now: () => DateTime(2026, 6, 27),
    );

    final result = await service.clear(const CacheClearRequest());

    expect(imageCache.clearUnprotectedCalls, 1);
    expect(result.imageCacheCleared, isTrue);
    expect(result.deletedDocuments, 2);
    expect(result.deletedSnapshots, 3);
    expect(result.deletedProtectedCoverRecords, 0);
  });

  test(
    'prune applies image limit, document age and expired snapshot cleanup',
    () async {
      final imageCache = _FakeImageCacheService();
      final documentCache = _FakeDocumentCacheService(deleteOlderThanResult: 4);
      final snapshotCache = _FakeSnapshotCacheService(deleteExpiredResult: 5);
      final now = DateTime(2026, 6, 27, 12);
      final service = DefaultCacheMaintenanceService(
        imageCacheService: imageCache,
        documentCacheService: documentCache,
        snapshotCacheService: snapshotCache,
        storageAccountingService: const _FakeStorageAccountingService(),
        now: () => now,
      );

      final result = await service.prune(
        const CachePruneRequest(
          imageCacheMaxBytes: 1024,
          documentMaxAge: Duration(days: 7),
        ),
      );

      expect(imageCache.lastPruneMaxBytes, 1024);
      expect(
        documentCache.lastDeleteOlderThan,
        now.subtract(const Duration(days: 7)),
      );
      expect(snapshotCache.lastDeleteExpiredAt, now);
      expect(result.deletedDocuments, 4);
      expect(result.deletedSnapshots, 5);
    },
  );
}

class _FakeImageCacheService implements ImageCacheService {
  int clearUnprotectedCalls = 0;
  int? lastPruneMaxBytes;

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> clearUnprotected() async {
    clearUnprotectedCalls += 1;
  }

  @override
  Future<CachedImageResult> copyProtectedLocalFile(
    ImageCacheLocalCopyRequest request,
  ) async {
    return CachedImageResult.failed;
  }

  @override
  Future<int> deleteByOwner({
    required ImageCacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<CachedImageResult> ensureCached(ImageCacheRequest request) async {
    return CachedImageResult.failed;
  }

  @override
  Future<CachedImageResult?> getCached(String cacheKey) async => null;

  @override
  Future<void> pruneToLimit({required int maxBytes}) async {
    lastPruneMaxBytes = maxBytes;
  }
}

class _FakeDocumentCacheService implements DocumentCacheService {
  _FakeDocumentCacheService({required this.deleteOlderThanResult});

  final int deleteOlderThanResult;
  DateTime? lastDeleteOlderThan;

  @override
  Future<int> deleteOlderThan(DateTime cutoff) async {
    lastDeleteOlderThan = cutoff;
    return deleteOlderThanResult;
  }

  @override
  Future<int> deleteByOwner({
    required CacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<int> deleteByOwnerPrefix({
    required CacheOwnerType ownerType,
    required String ownerIdPrefix,
  }) async => 0;

  @override
  Future<StorageUsageSection> calculateUsage() async {
    return const StorageUsageSection(
      bucket: StorageBucket.pageCache,
      label: '页面缓存',
      bytes: 0,
      clearable: true,
    );
  }

  @override
  Future<CachedDocument?> getByKey(String cacheKey) async => null;

  @override
  Future<void> put(CachedDocument document) async {}

  @override
  Future<void> touch(String cacheKey, DateTime accessedAt) async {}
}

class _FakeSnapshotCacheService implements ParsedSnapshotCacheService {
  _FakeSnapshotCacheService({required this.deleteExpiredResult});

  final int deleteExpiredResult;
  DateTime? lastDeleteExpiredAt;

  @override
  Future<int> deleteExpired(DateTime now) async {
    lastDeleteExpiredAt = now;
    return deleteExpiredResult;
  }

  @override
  Future<int> deleteByOwner({
    required CacheOwnerType ownerType,
    required String ownerId,
  }) async => 0;

  @override
  Future<int> deleteByOwnerPrefix({
    required CacheOwnerType ownerType,
    required String ownerIdPrefix,
  }) async => 0;

  @override
  Future<CachedSnapshot<T>?> get<T>(
    SnapshotCacheDescriptor descriptor,
    SnapshotCodec<T> codec,
  ) async => null;

  @override
  Future<void> put<T>(
    SnapshotCacheDescriptor descriptor,
    T value,
    SnapshotCodec<T> codec, {
    required SnapshotCachePolicy policy,
  }) async {}

  @override
  Future<StorageUsageSection> calculateUsage() async {
    return const StorageUsageSection(
      bucket: StorageBucket.pageCache,
      label: '页面缓存',
      bytes: 0,
      clearable: true,
    );
  }

  @override
  Future<void> touch(String cacheKey, DateTime accessedAt) async {}
}

class _FakeStorageAccountingService implements StorageAccountingService {
  const _FakeStorageAccountingService();

  @override
  Future<StorageUsageReport> loadUsageReport() async {
    return StorageUsageReport.fromSections(
      sections: const <StorageUsageSection>[],
      calculatedAt: DateTime(2026, 6, 27),
    );
  }
}
