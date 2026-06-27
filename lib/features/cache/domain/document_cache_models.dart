import 'package:y300/features/cache/domain/storage_usage_models.dart';

enum DocumentRequestProfile {
  anonymous('anonymous'),
  loggedIn('logged_in');

  const DocumentRequestProfile(this.id);

  final String id;
}

class DocumentCacheDescriptor {
  const DocumentCacheDescriptor({
    required this.cacheKey,
    required this.ownerType,
    required this.ownerId,
    required this.sourceUrl,
    required this.requestProfile,
  });

  final String cacheKey;
  final CacheOwnerType ownerType;
  final String ownerId;
  final String sourceUrl;
  final DocumentRequestProfile requestProfile;
}

class CachedDocument {
  const CachedDocument({
    required this.cacheKey,
    this.namespace = CacheNamespace.document,
    required this.ownerType,
    required this.ownerId,
    required this.sourceUrl,
    this.requestProfile = DocumentRequestProfile.loggedIn,
    required this.body,
    this.contentType,
    this.statusCode,
    required this.fetchedAt,
    required this.updatedAt,
    this.lastAccessedAt,
  });

  final String cacheKey;
  final CacheNamespace namespace;
  final CacheOwnerType ownerType;
  final String ownerId;
  final String sourceUrl;
  final DocumentRequestProfile requestProfile;
  final String body;
  final String? contentType;
  final int? statusCode;
  final DateTime fetchedAt;
  final DateTime updatedAt;
  final DateTime? lastAccessedAt;

  CachedDocument copyWith({DateTime? updatedAt, DateTime? lastAccessedAt}) {
    return CachedDocument(
      cacheKey: cacheKey,
      namespace: namespace,
      ownerType: ownerType,
      ownerId: ownerId,
      sourceUrl: sourceUrl,
      requestProfile: requestProfile,
      body: body,
      contentType: contentType,
      statusCode: statusCode,
      fetchedAt: fetchedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    );
  }
}

abstract class DocumentCacheService {
  Future<CachedDocument?> getByKey(String cacheKey);

  Future<void> put(CachedDocument document);

  Future<void> touch(String cacheKey, DateTime accessedAt);

  Future<int> deleteByOwner({
    required CacheOwnerType ownerType,
    required String ownerId,
  });

  Future<StorageUsageSection> calculateUsage();
}
