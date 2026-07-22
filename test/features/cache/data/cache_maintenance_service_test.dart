import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/data/services/cache_maintenance_service.dart';
import 'package:y300/features/cache/data/services/cache_budget_coordinator.dart';
import 'package:y300/features/cache/domain/models/cache_capacity_models.dart';
import 'package:y300/features/cache/domain/models/cache_maintenance_models.dart';
import 'package:y300/features/cache/domain/models/document_cache_models.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_cache_service.dart';
import 'package:y300/features/cache/domain/models/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/models/storage_usage_models.dart';

void main() {
  test('clear default cache clears only ordinary cache domains', () async {
    final imageCache = _FakeImageCacheService();
    final documentCache = _FakeDocumentCacheService(deleteOlderThanResult: 2);
    final snapshotCache = _FakeSnapshotCacheService(deleteExpiredResult: 3);
    final participant = _FakeBudgetParticipant(bytes: 128, entryCount: 3);
    final service = DefaultCacheMaintenanceService(
      imageCacheService: imageCache,
      documentCacheService: documentCache,
      snapshotCacheService: snapshotCache,
      storageAccountingService: const _FakeStorageAccountingService(),
      cacheBudgetCoordinator: CacheBudgetCoordinator(
        participants: <CacheBudgetParticipant>[participant],
      ),
      now: () => DateTime(2026, 6, 27),
    );

    final result = await service.clear(const CacheClearRequest());

    expect(imageCache.clearUnprotectedCalls, 0);
    expect(result.imageCacheCleared, isTrue);
    expect(result.deletedDocuments, 0);
    expect(result.deletedSnapshots, 0);
    expect(result.deletedRegularEntries, 3);
    expect(result.deletedBytes, 128);
    expect(result.deletedProtectedCoverRecords, 0);
  });

  test(
    'clear userCleanup delegates to all regular cache participants',
    () async {
      final imageCache = _FakeImageCacheService();
      final documentCache = _FakeDocumentCacheService(deleteOlderThanResult: 4);
      final snapshotCache = _FakeSnapshotCacheService(deleteExpiredResult: 5);
      final participant = _FakeBudgetParticipant(bytes: 512, entryCount: 7);
      final service = DefaultCacheMaintenanceService(
        imageCacheService: imageCache,
        documentCacheService: documentCache,
        snapshotCacheService: snapshotCache,
        storageAccountingService: const _FakeStorageAccountingService(),
        cacheBudgetCoordinator: CacheBudgetCoordinator(
          participants: <CacheBudgetParticipant>[participant],
        ),
        now: () => DateTime(2026, 6, 27),
      );

      final result = await service.clear(
        const CacheClearRequest(scope: CacheClearScope.userCleanup),
      );

      expect(documentCache.lastDeleteOlderThan, isNull);
      expect(snapshotCache.lastDeleteExpiredAt, isNull);
      expect(result.deletedDocuments, 0);
      expect(result.deletedSnapshots, 0);
      expect(imageCache.clearUnprotectedCalls, 0);
      expect(imageCache.clearUnprotectedByRolesCalls, 0);
      expect(result.imageCacheCleared, isTrue);
      expect(result.deletedRegularEntries, 7);
      expect(result.deletedBytes, 512);
    },
  );

  test(
    'prune applies unified limit, document age and expired snapshot cleanup',
    () async {
      final imageCache = _FakeImageCacheService();
      final documentCache = _FakeDocumentCacheService(deleteOlderThanResult: 4);
      final snapshotCache = _FakeSnapshotCacheService(deleteExpiredResult: 5);
      final now = DateTime(2026, 6, 27, 12);
      final participant = _FakeBudgetParticipant(bytes: 2048, entryCount: 2);
      final service = DefaultCacheMaintenanceService(
        imageCacheService: imageCache,
        documentCacheService: documentCache,
        snapshotCacheService: snapshotCache,
        storageAccountingService: const _FakeStorageAccountingService(),
        cacheBudgetCoordinator: CacheBudgetCoordinator(
          participants: <CacheBudgetParticipant>[participant],
        ),
        now: () => now,
      );

      final result = await service.prune(
        const CachePruneRequest(
          maxCacheBytes: 1024,
          documentMaxAge: Duration(days: 7),
        ),
      );

      expect(imageCache.lastPruneMaxBytes, isNull);
      expect(
        documentCache.lastDeleteOlderThan,
        now.subtract(const Duration(days: 7)),
      );
      expect(snapshotCache.lastDeleteExpiredAt, now);
      expect(result.deletedDocuments, 4);
      expect(result.deletedSnapshots, 5);
      expect(result.deletedCacheEntries, 2);
      expect(result.deletedBytes, 2048);
    },
  );
}

class _FakeBudgetParticipant implements CacheBudgetParticipant {
  _FakeBudgetParticipant({required this.bytes, required this.entryCount});

  int bytes;
  final int entryCount;

  @override
  String get participantId => 'fake';

  @override
  Future<CacheParticipantUsage> loadUsage() async {
    return CacheParticipantUsage(clearableBytes: bytes, budgetedBytes: bytes);
  }

  @override
  Future<List<CacheEvictionCandidate>> loadEvictionCandidates() async {
    if (bytes <= 0) {
      return const <CacheEvictionCandidate>[];
    }
    final each = bytes ~/ entryCount;
    return List<CacheEvictionCandidate>.generate(entryCount, (index) {
      final candidateBytes = index == entryCount - 1
          ? bytes - (each * index)
          : each;
      return CacheEvictionCandidate(
        participantId: participantId,
        cacheKey: 'fake-$index',
        bytes: candidateBytes,
        lastAccessedAt: DateTime(2026, 1, index + 1),
        priority: CacheEvictionPriority.regularImage,
      );
    });
  }

  @override
  Future<bool> deleteCandidate(CacheEvictionCandidate candidate) async {
    bytes -= candidate.bytes;
    return true;
  }

  @override
  Future<CacheParticipantClearResult> clearRegular() async {
    final deletedBytes = bytes;
    bytes = 0;
    return CacheParticipantClearResult(
      deletedEntries: entryCount,
      deletedBytes: deletedBytes,
    );
  }
}

class _FakeImageCacheService implements ImageCacheService {
  int clearUnprotectedCalls = 0;
  int clearUnprotectedByRolesCalls = 0;
  List<ImageCacheRole>? lastClearedRoles;
  int clearUnprotectedByRolesResult = 0;
  int? lastPruneMaxBytes;

  @override
  Future<int> calculateUsageBytes({bool includeProtected = false}) async => 0;

  @override
  Future<void> clearUnprotected() async {
    clearUnprotectedCalls += 1;
  }

  @override
  Future<int> clearUnprotectedByRoles({
    required List<ImageCacheRole> roles,
  }) async {
    clearUnprotectedByRolesCalls += 1;
    lastClearedRoles = List<ImageCacheRole>.of(roles);
    return clearUnprotectedByRolesResult;
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
