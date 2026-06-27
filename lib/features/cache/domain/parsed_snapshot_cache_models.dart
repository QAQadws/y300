import 'package:y300/features/cache/domain/storage_usage_models.dart';

class SnapshotCacheDescriptor {
  const SnapshotCacheDescriptor({
    required this.cacheKey,
    required this.ownerType,
    required this.ownerId,
    required this.snapshotType,
    this.sourceDocumentKey,
  });

  final String cacheKey;
  final CacheOwnerType ownerType;
  final String ownerId;
  final String snapshotType;
  final String? sourceDocumentKey;
}

class SnapshotCachePolicy {
  const SnapshotCachePolicy({
    required this.freshFor,
    required this.keepStaleFor,
  });

  final Duration freshFor;
  final Duration keepStaleFor;
}

abstract class SnapshotCodec<T> {
  String get snapshotType;

  int get codecVersion;

  int get parserVersion;

  Object? encode(T value);

  T decode(Object? json);
}

class CachedSnapshot<T> {
  const CachedSnapshot({
    required this.cacheKey,
    required this.ownerType,
    required this.ownerId,
    required this.snapshotType,
    required this.codecVersion,
    required this.parserVersion,
    this.sourceDocumentKey,
    required this.value,
    required this.createdAt,
    required this.updatedAt,
    this.lastAccessedAt,
    this.staleAt,
    this.expiresAt,
  });

  final String cacheKey;
  final CacheOwnerType ownerType;
  final String ownerId;
  final String snapshotType;
  final int codecVersion;
  final int parserVersion;
  final String? sourceDocumentKey;
  final T value;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastAccessedAt;
  final DateTime? staleAt;
  final DateTime? expiresAt;

  bool isFresh(DateTime now) {
    final staleAt = this.staleAt;
    return staleAt == null || now.isBefore(staleAt);
  }

  bool isExpired(DateTime now) {
    final expiresAt = this.expiresAt;
    return expiresAt != null && !now.isBefore(expiresAt);
  }
}

abstract class ParsedSnapshotCacheService {
  Future<CachedSnapshot<T>?> get<T>(
    SnapshotCacheDescriptor descriptor,
    SnapshotCodec<T> codec,
  );

  Future<void> put<T>(
    SnapshotCacheDescriptor descriptor,
    T value,
    SnapshotCodec<T> codec, {
    required SnapshotCachePolicy policy,
  });

  Future<void> touch(String cacheKey, DateTime accessedAt);

  Future<int> deleteByOwner({
    required CacheOwnerType ownerType,
    required String ownerId,
  });

  Future<StorageUsageSection> calculateUsage();
}
