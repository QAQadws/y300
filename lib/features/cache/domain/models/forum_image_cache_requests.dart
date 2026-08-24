import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_retention_classifier.dart';

/// 论坛/帖子/头像/表情等原生图片的缓存请求构造器。
///
/// 保留等级统一交由 [ImageRetentionClassifier] 按 role 推断（单一来源），
/// 避免各处手写导致同类图片分类不一致。
abstract final class ForumImageCacheRequests {
  static ImageCacheRequest forumHeadImage({
    required String url,
    String? referer,
    String ownerId = 'home',
  }) {
    return ImageCacheRequest(
      cacheKey: ImageCacheKeys.forumHeadImage(url),
      sourceUrl: url,
      referer: referer,
      ownerType: ImageCacheOwnerType.forum,
      ownerId: ownerId,
      role: ImageCacheRole.forumHeadImage,
      retentionClass: ImageRetentionClassifier.defaultFor(
        ImageCacheRole.forumHeadImage,
      ),
    );
  }

  static ImageCacheRequest threadInline({
    required String tid,
    required String url,
    String? referer,
    int? imageIndex,
  }) {
    return ImageCacheRequest(
      cacheKey: ImageCacheKeys.threadInline(url),
      sourceUrl: url,
      referer: referer,
      ownerType: ImageCacheOwnerType.thread,
      ownerId: tid.trim().isEmpty ? 'unknown' : tid.trim(),
      role: ImageCacheRole.threadInline,
      imageIndex: imageIndex,
      retentionClass: ImageRetentionClassifier.defaultFor(
        ImageCacheRole.threadInline,
      ),
    );
  }

  static ImageCacheRequest threadAttachment({
    required String tid,
    required String url,
    String? referer,
    int? imageIndex,
  }) {
    return ImageCacheRequest(
      cacheKey: ImageCacheKeys.threadAttachment(url),
      sourceUrl: url,
      referer: referer,
      ownerType: ImageCacheOwnerType.thread,
      ownerId: tid.trim().isEmpty ? 'unknown' : tid.trim(),
      role: ImageCacheRole.threadAttachment,
      imageIndex: imageIndex,
      retentionClass: ImageRetentionClassifier.defaultFor(
        ImageCacheRole.threadAttachment,
      ),
    );
  }

  static ImageCacheRequest avatar({
    required String ownerId,
    required String url,
    String? referer,
    ImageCacheOwnerType ownerType = ImageCacheOwnerType.profile,
  }) {
    return ImageCacheRequest(
      cacheKey: ImageCacheKeys.avatar(url),
      sourceUrl: url,
      referer: referer,
      ownerType: ownerType,
      ownerId: ownerId.trim().isEmpty ? 'unknown' : ownerId.trim(),
      role: ImageCacheRole.avatar,
      retentionClass: ImageRetentionClassifier.defaultFor(
        ImageCacheRole.avatar,
      ),
    );
  }

  static ImageCacheRequest remoteSmiley({
    required String url,
    String? referer,
    String ownerId = 'yamibo-smiley-v4',
  }) {
    return ImageCacheRequest(
      cacheKey: ImageCacheKeys.remoteSmiley(url),
      sourceUrl: url,
      referer: referer,
      ownerType: ImageCacheOwnerType.sticker,
      ownerId: ownerId,
      role: ImageCacheRole.remoteSmiley,
      retentionClass: ImageRetentionClassifier.defaultFor(
        ImageCacheRole.remoteSmiley,
      ),
    );
  }

  static ImageCacheRequest blogInline({
    required String blogId,
    required String url,
    String? referer,
    int? imageIndex,
  }) {
    return ImageCacheRequest(
      cacheKey: ImageCacheKeys.blogInline(url),
      sourceUrl: url,
      referer: referer,
      ownerType: ImageCacheOwnerType.blog,
      ownerId: blogId.trim().isEmpty ? 'unknown' : blogId.trim(),
      role: ImageCacheRole.blogInline,
      imageIndex: imageIndex,
      retentionClass: ImageRetentionClassifier.defaultFor(
        ImageCacheRole.blogInline,
      ),
    );
  }

  static ImageCacheRequest composerUnusedAttachment({
    required String aid,
    required String url,
    String? referer,
  }) {
    final normalizedAid = aid.trim().isEmpty ? 'unknown' : aid.trim();
    return ImageCacheRequest(
      cacheKey: ImageCacheKeys.composerUnusedAttachment(normalizedAid),
      sourceUrl: url,
      referer: referer,
      ownerType: ImageCacheOwnerType.composer,
      ownerId: normalizedAid,
      role: ImageCacheRole.composerUnusedAttachment,
      retentionClass: ImageRetentionClassifier.defaultFor(
        ImageCacheRole.composerUnusedAttachment,
      ),
    );
  }
}
