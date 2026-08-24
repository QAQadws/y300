import 'package:y300/features/cache/domain/models/image_cache_models.dart';

enum ForumImageKind {
  threadInline,
  threadAttachment,
  remoteSmiley,
  avatar,
  forumHeadImage,
  forumIcon,
  cover,
  customCover,
  favoriteCover,
  comicReaderPage,
  blogInline,
  externalInline,
}

enum ForumImageLayoutMode {
  blockWithKnownAspectRatio,
  blockWithFallbackAspectRatio,
  inlineIntrinsic,
  fixedAvatar,
  fixedCover,
  fixedBanner,
  fixedIcon,
  readerPage,
}

enum ForumImagePrecacheMode {
  none,
  firstViewportLight,
  nearViewportLight,
  listViewportLight,
  readerSessionAggressive,
}

enum ForumImageDownscaleMode {
  none,
  widthBound,
  coverAware,
  readerViewport,
  iconExact,
}

class ForumImageLoadSpec {
  const ForumImageLoadSpec({
    required this.kind,
    required this.url,
    this.referer,
    this.ownerId,
    this.ownerType,
    this.episodeId,
    this.imageIndex,
    this.cacheKey,
    this.retentionClass,
    this.htmlWidth,
    this.htmlHeight,
    this.displayWidth,
    this.displayHeight,
    this.alt,
    this.title,
    this.protected = false,
    this.allowReaderOpen,
  });

  final ForumImageKind kind;
  final Uri url;
  final String? referer;
  final String? ownerId;
  final ImageCacheOwnerType? ownerType;
  final String? episodeId;
  final int? imageIndex;
  final String? cacheKey;
  final ImageRetentionClass? retentionClass;
  final double? htmlWidth;
  final double? htmlHeight;
  final double? displayWidth;
  final double? displayHeight;
  final String? alt;
  final String? title;
  final bool protected;
  final bool? allowReaderOpen;

  String get sourceUrl => url.toString();

  bool get hasHtmlDimensions {
    final width = htmlWidth;
    final height = htmlHeight;
    return width != null &&
        height != null &&
        width.isFinite &&
        height.isFinite &&
        width > 0 &&
        height > 0;
  }
}

class ForumImageRenderPolicy {
  const ForumImageRenderPolicy({
    required this.layoutMode,
    required this.precacheMode,
    required this.allowReaderOpen,
    required this.retentionHint,
    required this.downscaleMode,
  });

  final ForumImageLayoutMode layoutMode;
  final ForumImagePrecacheMode precacheMode;
  final bool allowReaderOpen;
  final ImageRetentionClass retentionHint;
  final ForumImageDownscaleMode downscaleMode;
}
