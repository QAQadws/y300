import 'package:flutter_test/flutter_test.dart';
import 'package:y300/features/cache/domain/document_cache_models.dart';
import 'package:y300/features/cache/domain/native_page_cache_invalidation_service.dart';
import 'package:y300/features/cache/domain/parsed_snapshot_cache_models.dart';
import 'package:y300/features/cache/domain/storage_usage_models.dart';

void main() {
  test(
    'invalidateThread deletes document and snapshot variants by tid prefix',
    () async {
      final documents = _RecordingDocumentCacheService();
      final snapshots = _RecordingParsedSnapshotCacheService();
      final service = DefaultNativePageCacheInvalidationService(
        documentCache: documents,
        snapshotCache: snapshots,
      );

      await service.invalidateThread('560713');

      expect(documents.deletedPrefixes, <_OwnerPrefixCall>[
        const _OwnerPrefixCall(CacheOwnerType.thread, 'tid=560713'),
      ]);
      expect(snapshots.deletedPrefixes, <_OwnerPrefixCall>[
        const _OwnerPrefixCall(CacheOwnerType.thread, 'tid=560713'),
      ]);
      expect(documents.deletedOwners, isEmpty);
      expect(snapshots.deletedOwners, isEmpty);
    },
  );

  test('invalidateForumHome deletes exact home owner', () async {
    final documents = _RecordingDocumentCacheService();
    final snapshots = _RecordingParsedSnapshotCacheService();
    final service = DefaultNativePageCacheInvalidationService(
      documentCache: documents,
      snapshotCache: snapshots,
    );

    await service.invalidateForumHome();

    expect(documents.deletedOwners, <_OwnerCall>[
      const _OwnerCall(CacheOwnerType.forum, 'home'),
    ]);
    expect(snapshots.deletedOwners, <_OwnerCall>[
      const _OwnerCall(CacheOwnerType.forum, 'home'),
    ]);
  });

  test(
    'invalidateForumDisplay deletes document and snapshot variants by fid prefix',
    () async {
      final documents = _RecordingDocumentCacheService();
      final snapshots = _RecordingParsedSnapshotCacheService();
      final service = DefaultNativePageCacheInvalidationService(
        documentCache: documents,
        snapshotCache: snapshots,
      );

      await service.invalidateForumDisplay('33');

      expect(documents.deletedPrefixes, <_OwnerPrefixCall>[
        const _OwnerPrefixCall(CacheOwnerType.forumDisplay, 'fid=33'),
      ]);
      expect(snapshots.deletedPrefixes, <_OwnerPrefixCall>[
        const _OwnerPrefixCall(CacheOwnerType.forumDisplay, 'fid=33'),
      ]);
    },
  );
}

class _RecordingDocumentCacheService implements DocumentCacheService {
  final deletedOwners = <_OwnerCall>[];
  final deletedPrefixes = <_OwnerPrefixCall>[];

  @override
  Future<CachedDocument?> getByKey(String cacheKey) async => null;

  @override
  Future<void> put(CachedDocument document) async {}

  @override
  Future<void> touch(String cacheKey, DateTime accessedAt) async {}

  @override
  Future<int> deleteByOwner({
    required CacheOwnerType ownerType,
    required String ownerId,
  }) async {
    deletedOwners.add(_OwnerCall(ownerType, ownerId));
    return 0;
  }

  @override
  Future<int> deleteByOwnerPrefix({
    required CacheOwnerType ownerType,
    required String ownerIdPrefix,
  }) async {
    deletedPrefixes.add(_OwnerPrefixCall(ownerType, ownerIdPrefix));
    return 0;
  }

  @override
  Future<StorageUsageSection> calculateUsage() async {
    return const StorageUsageSection(
      bucket: StorageBucket.pageCache,
      label: '页面缓存',
      bytes: 0,
      clearable: false,
    );
  }
}

class _RecordingParsedSnapshotCacheService
    implements ParsedSnapshotCacheService {
  final deletedOwners = <_OwnerCall>[];
  final deletedPrefixes = <_OwnerPrefixCall>[];

  @override
  Future<CachedSnapshot<T>?> get<T>(
    SnapshotCacheDescriptor descriptor,
    SnapshotCodec<T> codec,
  ) async {
    return null;
  }

  @override
  Future<void> put<T>(
    SnapshotCacheDescriptor descriptor,
    T value,
    SnapshotCodec<T> codec, {
    required SnapshotCachePolicy policy,
  }) async {}

  @override
  Future<void> touch(String cacheKey, DateTime accessedAt) async {}

  @override
  Future<int> deleteByOwner({
    required CacheOwnerType ownerType,
    required String ownerId,
  }) async {
    deletedOwners.add(_OwnerCall(ownerType, ownerId));
    return 0;
  }

  @override
  Future<int> deleteByOwnerPrefix({
    required CacheOwnerType ownerType,
    required String ownerIdPrefix,
  }) async {
    deletedPrefixes.add(_OwnerPrefixCall(ownerType, ownerIdPrefix));
    return 0;
  }

  @override
  Future<StorageUsageSection> calculateUsage() async {
    return const StorageUsageSection(
      bucket: StorageBucket.pageCache,
      label: '页面缓存',
      bytes: 0,
      clearable: false,
    );
  }
}

class _OwnerCall {
  const _OwnerCall(this.ownerType, this.ownerId);

  final CacheOwnerType ownerType;
  final String ownerId;

  @override
  bool operator ==(Object other) {
    return other is _OwnerCall &&
        other.ownerType == ownerType &&
        other.ownerId == ownerId;
  }

  @override
  int get hashCode => Object.hash(ownerType, ownerId);

  @override
  String toString() => '$ownerType:$ownerId';
}

class _OwnerPrefixCall {
  const _OwnerPrefixCall(this.ownerType, this.ownerIdPrefix);

  final CacheOwnerType ownerType;
  final String ownerIdPrefix;

  @override
  bool operator ==(Object other) {
    return other is _OwnerPrefixCall &&
        other.ownerType == ownerType &&
        other.ownerIdPrefix == ownerIdPrefix;
  }

  @override
  int get hashCode => Object.hash(ownerType, ownerIdPrefix);

  @override
  String toString() => '$ownerType:$ownerIdPrefix';
}
