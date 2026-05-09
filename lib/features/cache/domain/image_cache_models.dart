enum ImageCacheOwnerType {
  comic('comic'),
  novel('novel'),
  thread('thread');

  const ImageCacheOwnerType(this.dbValue);

  final String dbValue;
}

enum ImageCacheRole {
  cover('cover'),
  customCover('custom_cover'),
  comicPage('comic_page'),
  novelInline('novel_inline');

  const ImageCacheRole(this.dbValue);

  final String dbValue;
}

class ImageCacheRequest {
  const ImageCacheRequest({
    required this.cacheKey,
    required this.sourceUrl,
    required this.ownerType,
    required this.ownerId,
    required this.role,
    this.episodeId,
    this.imageIndex,
    this.protected = false,
  });

  final String cacheKey;
  final String sourceUrl;
  final ImageCacheOwnerType ownerType;
  final String ownerId;
  final ImageCacheRole role;
  final String? episodeId;
  final int? imageIndex;
  final bool protected;
}

class ImageCacheLocalCopyRequest {
  const ImageCacheLocalCopyRequest({
    required this.cacheKey,
    required this.sourcePath,
    required this.ownerType,
    required this.ownerId,
    required this.role,
    this.episodeId,
    this.imageIndex,
  });

  final String cacheKey;
  final String sourcePath;
  final ImageCacheOwnerType ownerType;
  final String ownerId;
  final ImageCacheRole role;
  final String? episodeId;
  final int? imageIndex;
}

class CachedImageRecord {
  const CachedImageRecord({
    required this.cacheKey,
    required this.ownerType,
    required this.ownerId,
    this.episodeId,
    this.imageIndex,
    required this.role,
    this.lastSourceUrl,
    this.localPath,
    required this.bytes,
    this.mimeType,
    required this.protected,
    required this.createdAt,
    required this.updatedAt,
    this.lastAccessedAt,
  });

  final String cacheKey;
  final String ownerType;
  final String ownerId;
  final String? episodeId;
  final int? imageIndex;
  final String role;
  final String? lastSourceUrl;
  final String? localPath;
  final int bytes;
  final String? mimeType;
  final bool protected;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastAccessedAt;

  CachedImageRecord copyWith({
    String? lastSourceUrl,
    String? localPath,
    int? bytes,
    String? mimeType,
    bool? protected,
    DateTime? updatedAt,
    DateTime? lastAccessedAt,
  }) {
    return CachedImageRecord(
      cacheKey: cacheKey,
      ownerType: ownerType,
      ownerId: ownerId,
      episodeId: episodeId,
      imageIndex: imageIndex,
      role: role,
      lastSourceUrl: lastSourceUrl ?? this.lastSourceUrl,
      localPath: localPath ?? this.localPath,
      bytes: bytes ?? this.bytes,
      mimeType: mimeType ?? this.mimeType,
      protected: protected ?? this.protected,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    );
  }
}

class CachedImageResult {
  const CachedImageResult({
    required this.success,
    this.cacheKey,
    this.localPath,
    this.bytes = 0,
    this.fromCache = false,
  });

  final bool success;
  final String? cacheKey;
  final String? localPath;
  final int bytes;
  final bool fromCache;

  static const CachedImageResult failed = CachedImageResult(success: false);
}
