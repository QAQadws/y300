import 'package:y300/features/cache/domain/image_cache_keys.dart';
import 'package:y300/features/cache/domain/image_cache_models.dart';

abstract final class ForumImageCacheRequests {
  static ImageCacheRequest forumHeadImage({
    required String url,
    String ownerId = 'home',
  }) {
    return ImageCacheRequest(
      cacheKey: ImageCacheKeys.forumHeadImage(url),
      sourceUrl: url,
      ownerType: ImageCacheOwnerType.forum,
      ownerId: ownerId,
      role: ImageCacheRole.forumHeadImage,
      retentionClass: ImageRetentionClass.ephemeral,
    );
  }

  static ImageCacheRequest threadInline({
    required String tid,
    required String url,
    int? imageIndex,
  }) {
    return ImageCacheRequest(
      cacheKey: ImageCacheKeys.threadInline(url),
      sourceUrl: url,
      ownerType: ImageCacheOwnerType.thread,
      ownerId: tid.trim().isEmpty ? 'unknown' : tid.trim(),
      role: ImageCacheRole.threadInline,
      imageIndex: imageIndex,
      retentionClass: ImageRetentionClass.ephemeral,
    );
  }

  static ImageCacheRequest threadAttachment({
    required String tid,
    required String url,
    int? imageIndex,
  }) {
    return ImageCacheRequest(
      cacheKey: ImageCacheKeys.threadAttachment(url),
      sourceUrl: url,
      ownerType: ImageCacheOwnerType.thread,
      ownerId: tid.trim().isEmpty ? 'unknown' : tid.trim(),
      role: ImageCacheRole.threadAttachment,
      imageIndex: imageIndex,
      retentionClass: ImageRetentionClass.ephemeral,
    );
  }

  static ImageCacheRequest avatar({
    required String ownerId,
    required String url,
    ImageCacheOwnerType ownerType = ImageCacheOwnerType.profile,
  }) {
    return ImageCacheRequest(
      cacheKey: ImageCacheKeys.avatar(url),
      sourceUrl: url,
      ownerType: ownerType,
      ownerId: ownerId.trim().isEmpty ? 'unknown' : ownerId.trim(),
      role: ImageCacheRole.avatar,
      retentionClass: ImageRetentionClass.ephemeral,
    );
  }

  static ImageCacheRequest remoteSmiley({
    required String url,
    String ownerId = 'yamibo-smiley-v4',
  }) {
    return ImageCacheRequest(
      cacheKey: ImageCacheKeys.remoteSmiley(url),
      sourceUrl: url,
      ownerType: ImageCacheOwnerType.sticker,
      ownerId: ownerId,
      role: ImageCacheRole.remoteSmiley,
      retentionClass: ImageRetentionClass.sticky,
    );
  }

  static ImageCacheRequest blogInline({
    required String blogId,
    required String url,
    int? imageIndex,
  }) {
    return ImageCacheRequest(
      cacheKey: ImageCacheKeys.blogInline(url),
      sourceUrl: url,
      ownerType: ImageCacheOwnerType.blog,
      ownerId: blogId.trim().isEmpty ? 'unknown' : blogId.trim(),
      role: ImageCacheRole.blogInline,
      imageIndex: imageIndex,
      retentionClass: ImageRetentionClass.ephemeral,
    );
  }
}
