import 'package:y300/features/cache/domain/models/forum_image_cache_requests.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_keys.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/image_retention_classifier.dart';

abstract interface class ForumImageRequestResolver {
  ImageCacheRequest? resolveCacheRequest(ForumImageLoadSpec spec);

  ForumImageRenderPolicy resolveRenderPolicy(ForumImageLoadSpec spec);
}

class DefaultForumImageRequestResolver implements ForumImageRequestResolver {
  const DefaultForumImageRequestResolver();

  @override
  ImageCacheRequest? resolveCacheRequest(ForumImageLoadSpec spec) {
    final url = spec.sourceUrl;
    switch (spec.kind) {
      case ForumImageKind.threadInline:
        return ForumImageCacheRequests.threadInline(
          tid: _ownerId(spec),
          url: url,
          imageIndex: spec.imageIndex,
        );
      case ForumImageKind.threadAttachment:
        return ForumImageCacheRequests.threadAttachment(
          tid: _ownerId(spec),
          url: url,
          imageIndex: spec.imageIndex,
        );
      case ForumImageKind.remoteSmiley:
        return ForumImageCacheRequests.remoteSmiley(
          url: url,
          ownerId: _ownerId(spec, fallback: 'yamibo-smiley-v4'),
        );
      case ForumImageKind.avatar:
        return ForumImageCacheRequests.avatar(
          ownerId: _ownerId(spec),
          url: url,
          ownerType: spec.ownerType ?? ImageCacheOwnerType.profile,
        );
      case ForumImageKind.forumHeadImage:
        return ForumImageCacheRequests.forumHeadImage(
          url: url,
          ownerId: _ownerId(spec, fallback: 'home'),
        );
      case ForumImageKind.blogInline:
        return ForumImageCacheRequests.blogInline(
          blogId: _ownerId(spec),
          url: url,
          imageIndex: spec.imageIndex,
        );
      case ForumImageKind.forumIcon:
        return _requestFromSpec(
          spec,
          defaultOwnerType: ImageCacheOwnerType.forumDisplay,
          defaultRole: ImageCacheRole.forumIcon,
          defaultCacheKey: ImageCacheKeys.forumIcon(url),
          defaultOwnerId: 'forum-icon',
        );
      case ForumImageKind.cover:
      case ForumImageKind.favoriteCover:
        return _requestFromSpec(
          spec,
          defaultOwnerType: spec.ownerType ?? ImageCacheOwnerType.comic,
          defaultRole: ImageCacheRole.cover,
          defaultCacheKey: spec.cacheKey,
        );
      case ForumImageKind.customCover:
        return _requestFromSpec(
          spec,
          defaultOwnerType: spec.ownerType ?? ImageCacheOwnerType.comic,
          defaultRole: ImageCacheRole.customCover,
          defaultCacheKey: spec.cacheKey,
          defaultProtected: true,
        );
      case ForumImageKind.comicReaderPage:
        return _requestFromSpec(
          spec,
          defaultOwnerType: ImageCacheOwnerType.comic,
          defaultRole: ImageCacheRole.comicPage,
          defaultCacheKey:
              spec.cacheKey ??
              _comicPageCacheKey(
                ownerId: spec.ownerId,
                episodeId: spec.episodeId,
                imageIndex: spec.imageIndex,
              ),
          defaultRetentionClass: ImageRetentionClass.recentReader,
        );
      case ForumImageKind.externalInline:
        return null;
    }
  }

  @override
  ForumImageRenderPolicy resolveRenderPolicy(ForumImageLoadSpec spec) {
    switch (spec.kind) {
      case ForumImageKind.threadInline:
      case ForumImageKind.threadAttachment:
      case ForumImageKind.blogInline:
      case ForumImageKind.externalInline:
        return ForumImageRenderPolicy(
          layoutMode: spec.hasHtmlDimensions
              ? ForumImageLayoutMode.blockWithKnownAspectRatio
              : ForumImageLayoutMode.blockWithFallbackAspectRatio,
          precacheMode: ForumImagePrecacheMode.firstViewportLight,
          allowReaderOpen: spec.allowReaderOpen ?? true,
          retentionHint: _retentionFor(spec, ImageCacheRole.threadInline),
          downscaleMode: ForumImageDownscaleMode.widthBound,
        );
      case ForumImageKind.remoteSmiley:
        return ForumImageRenderPolicy(
          layoutMode: ForumImageLayoutMode.inlineIntrinsic,
          precacheMode: ForumImagePrecacheMode.none,
          allowReaderOpen: spec.allowReaderOpen ?? false,
          retentionHint: _retentionFor(spec, ImageCacheRole.remoteSmiley),
          downscaleMode: ForumImageDownscaleMode.none,
        );
      case ForumImageKind.avatar:
        return ForumImageRenderPolicy(
          layoutMode: ForumImageLayoutMode.fixedAvatar,
          precacheMode: ForumImagePrecacheMode.listViewportLight,
          allowReaderOpen: spec.allowReaderOpen ?? false,
          retentionHint: _retentionFor(spec, ImageCacheRole.avatar),
          downscaleMode: ForumImageDownscaleMode.iconExact,
        );
      case ForumImageKind.forumHeadImage:
        return ForumImageRenderPolicy(
          layoutMode: ForumImageLayoutMode.fixedBanner,
          precacheMode: ForumImagePrecacheMode.nearViewportLight,
          allowReaderOpen: spec.allowReaderOpen ?? false,
          retentionHint: _retentionFor(spec, ImageCacheRole.forumHeadImage),
          downscaleMode: ForumImageDownscaleMode.coverAware,
        );
      case ForumImageKind.forumIcon:
        return ForumImageRenderPolicy(
          layoutMode: ForumImageLayoutMode.fixedIcon,
          precacheMode: ForumImagePrecacheMode.listViewportLight,
          allowReaderOpen: spec.allowReaderOpen ?? false,
          retentionHint: _retentionFor(spec, ImageCacheRole.forumIcon),
          downscaleMode: ForumImageDownscaleMode.iconExact,
        );
      case ForumImageKind.cover:
      case ForumImageKind.customCover:
      case ForumImageKind.favoriteCover:
        return ForumImageRenderPolicy(
          layoutMode: ForumImageLayoutMode.fixedCover,
          precacheMode: ForumImagePrecacheMode.listViewportLight,
          allowReaderOpen: spec.allowReaderOpen ?? false,
          retentionHint: spec.kind == ForumImageKind.customCover
              ? _retentionFor(spec, ImageCacheRole.customCover)
              : _retentionFor(spec, ImageCacheRole.cover),
          downscaleMode: ForumImageDownscaleMode.coverAware,
        );
      case ForumImageKind.comicReaderPage:
        return ForumImageRenderPolicy(
          layoutMode: ForumImageLayoutMode.readerPage,
          precacheMode: ForumImagePrecacheMode.readerSessionAggressive,
          allowReaderOpen: spec.allowReaderOpen ?? true,
          retentionHint:
              spec.retentionClass ?? ImageRetentionClass.recentReader,
          downscaleMode: ForumImageDownscaleMode.readerViewport,
        );
    }
  }

  ImageCacheRequest? _requestFromSpec(
    ForumImageLoadSpec spec, {
    required ImageCacheOwnerType defaultOwnerType,
    required ImageCacheRole defaultRole,
    String? defaultCacheKey,
    String defaultOwnerId = 'unknown',
    bool defaultProtected = false,
    ImageRetentionClass? defaultRetentionClass,
  }) {
    final cacheKey = (spec.cacheKey ?? defaultCacheKey)?.trim();
    if (cacheKey == null || cacheKey.isEmpty) {
      return null;
    }
    return ImageCacheRequest(
      cacheKey: cacheKey,
      sourceUrl: spec.sourceUrl,
      ownerType: spec.ownerType ?? defaultOwnerType,
      ownerId: _ownerId(spec, fallback: defaultOwnerId),
      role: defaultRole,
      episodeId: spec.episodeId,
      imageIndex: spec.imageIndex,
      protected: spec.protected || defaultProtected,
      retentionClass:
          spec.retentionClass ??
          defaultRetentionClass ??
          ImageRetentionClassifier.defaultFor(defaultRole),
    );
  }

  ImageRetentionClass _retentionFor(
    ForumImageLoadSpec spec,
    ImageCacheRole role,
  ) {
    return spec.retentionClass ?? ImageRetentionClassifier.defaultFor(role);
  }

  String _ownerId(ForumImageLoadSpec spec, {String fallback = 'unknown'}) {
    final owner = spec.ownerId?.trim();
    return owner == null || owner.isEmpty ? fallback : owner;
  }

  String? _comicPageCacheKey({
    required String? ownerId,
    required String? episodeId,
    required int? imageIndex,
  }) {
    final comicId = ownerId?.trim();
    final episode = episodeId?.trim();
    final index = imageIndex;
    if (comicId == null ||
        comicId.isEmpty ||
        episode == null ||
        episode.isEmpty ||
        index == null) {
      return null;
    }
    return ImageCacheKeys.comicPage(
      comicId: comicId,
      episodeId: episode,
      imageIndex: index,
    );
  }
}
