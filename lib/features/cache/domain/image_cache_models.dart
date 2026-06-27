enum ImageCacheOwnerType {
  forum('forum'),
  forumDisplay('forum_display'),
  comic('comic'),
  novel('novel'),
  thread('thread'),
  tag('tag'),
  profile('profile'),
  blog('blog'),
  sticker('sticker'),
  favorite('favorite'),
  composer('composer');

  const ImageCacheOwnerType(this.dbValue);

  final String dbValue;
}

enum ImageCacheRole {
  cover('cover'),
  customCover('custom_cover'),
  comicPage('comic_page'),
  novelInline('novel_inline'),
  forumHeadImage('forum_head_image'),
  forumIcon('forum_icon'),
  threadInline('thread_inline'),
  threadAttachment('thread_attachment'),
  avatar('avatar'),
  remoteSmiley('remote_smiley'),
  blogInline('blog_inline');

  const ImageCacheRole(this.dbValue);

  final String dbValue;
}

enum ImageRetentionClass {
  ephemeral('ephemeral'),
  recentReader('recent_reader'),
  sticky('sticky'),
  protected('protected'),
  downloaded('downloaded');

  const ImageRetentionClass(this.dbValue);

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
    this.retentionClass,
  });

  final String cacheKey;
  final String sourceUrl;
  final ImageCacheOwnerType ownerType;
  final String ownerId;
  final ImageCacheRole role;
  final String? episodeId;
  final int? imageIndex;
  final bool protected;
  final ImageRetentionClass? retentionClass;

  ImageRetentionClass get effectiveRetentionClass {
    return retentionClass ??
        (protected
            ? ImageRetentionClass.protected
            : ImageRetentionClass.ephemeral);
  }
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
    this.retentionClass = ImageRetentionClass.protected,
  });

  final String cacheKey;
  final String sourcePath;
  final ImageCacheOwnerType ownerType;
  final String ownerId;
  final ImageCacheRole role;
  final String? episodeId;
  final int? imageIndex;
  final ImageRetentionClass retentionClass;
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
    this.width,
    this.height,
    required this.protected,
    this.retentionClass = ImageRetentionClass.ephemeral,
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
  final int? width;
  final int? height;
  final bool protected;
  final ImageRetentionClass retentionClass;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastAccessedAt;

  CachedImageRecord copyWith({
    String? lastSourceUrl,
    String? localPath,
    int? bytes,
    String? mimeType,
    int? width,
    int? height,
    bool? protected,
    ImageRetentionClass? retentionClass,
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
      width: width ?? this.width,
      height: height ?? this.height,
      protected: protected ?? this.protected,
      retentionClass: retentionClass ?? this.retentionClass,
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
    this.width,
    this.height,
  });

  final bool success;
  final String? cacheKey;
  final String? localPath;
  final int bytes;
  final bool fromCache;
  final int? width;
  final int? height;

  static const CachedImageResult failed = CachedImageResult(success: false);
}

class ImageCacheUsageGroup {
  const ImageCacheUsageGroup({
    required this.ownerType,
    required this.role,
    required this.retentionClass,
    required this.protected,
    required this.bytes,
  });

  final String ownerType;
  final String role;
  final String retentionClass;
  final bool protected;
  final int bytes;

  String get id {
    final protection = protected ? 'protected' : 'clearable';
    return '$ownerType:$role:$retentionClass:$protection';
  }
}
