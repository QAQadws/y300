import 'package:flutter/material.dart';
import 'package:y300/features/cache/domain/models/forum_image_load_spec.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/domain/services/forum_image_layout_hint_resolver.dart';
import 'package:y300/features/cache/domain/services/forum_image_precache_service.dart';
import 'package:y300/features/cache/domain/services/forum_image_request_resolver.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/cache/presentation/widgets/image_retry_placeholder.dart';
import 'package:y300/features/content_rendering_shared/application/host/cache_forum_html_display_image.dart';
import 'package:forum_content_renderer/forum_content_renderer.dart';

final class CacheForumHtmlImageHost implements ForumHtmlImageHost {
  const CacheForumHtmlImageHost({
    required ForumImageDimensionIndex dimensionIndex,
  }) : this._(dimensionIndex: dimensionIndex);

  /// Non-network HTML must stay usable without initializing cache providers.
  const CacheForumHtmlImageHost.lazy({
    required ForumImageDimensionIndex Function() dimensionIndexFor,
  }) : this._(dimensionIndexFor: dimensionIndexFor);

  const CacheForumHtmlImageHost._({
    ForumImageDimensionIndex? dimensionIndex,
    ForumImageDimensionIndex Function()? dimensionIndexFor,
    this.threadId = '',
    this.imageCacheOwnerId,
    this.contentImageKind = ForumImageKind.threadInline,
    this.imageRequestResolver = const DefaultForumImageRequestResolver(),
    this.layoutHintResolver = const ForumImageLayoutHintResolver(),
    this.imageReferer,
    this.imagePrecacheService,
    this.fallbackAspectRatioFor,
    void Function(
      ForumImageLoadSpec spec,
      ImageCacheRequest request,
      Size size,
    )?
    onBlockImageResolved,
  }) : _dimensionIndex = dimensionIndex,
       _dimensionIndexFor = dimensionIndexFor,
       _onBlockImageResolved = onBlockImageResolved;

  final ForumImageDimensionIndex? _dimensionIndex;
  final ForumImageDimensionIndex Function()? _dimensionIndexFor;
  ForumImageDimensionIndex get dimensionIndex =>
      _dimensionIndex ?? _dimensionIndexFor!();
  final String threadId;
  final String? imageCacheOwnerId;
  final ForumImageKind contentImageKind;
  final ForumImageRequestResolver imageRequestResolver;
  final ForumImageLayoutHintResolver layoutHintResolver;
  final String? imageReferer;
  final ForumImagePrecacheService? imagePrecacheService;
  final double? Function(ForumImageLoadSpec spec, ImageCacheRequest request)?
  fallbackAspectRatioFor;
  final void Function(
    ForumImageLoadSpec spec,
    ImageCacheRequest request,
    Size size,
  )?
  _onBlockImageResolved;

  /// Keeps App cache configuration outside the renderer's display contract.
  CacheForumHtmlImageHost forContent({
    required String threadId,
    String? imageCacheOwnerId,
    ForumImageKind contentImageKind = ForumImageKind.threadInline,
    ForumImageRequestResolver? imageRequestResolver,
    ForumImageDimensionIndex? imageDimensionIndex,
    ForumImageLayoutHintResolver? layoutHintResolver,
    double? Function(ForumImageLoadSpec spec, ImageCacheRequest request)?
    fallbackAspectRatioFor,
    void Function(
      ForumImageLoadSpec spec,
      ImageCacheRequest request,
      Size size,
    )?
    onBlockImageResolved,
    ForumImagePrecacheService? imagePrecacheService,
    String? imageReferer,
  }) => CacheForumHtmlImageHost._(
    dimensionIndex: imageDimensionIndex ?? _dimensionIndex,
    dimensionIndexFor: _dimensionIndexFor,
    threadId: threadId,
    imageCacheOwnerId: imageCacheOwnerId,
    contentImageKind: contentImageKind,
    imageRequestResolver:
        imageRequestResolver ?? const DefaultForumImageRequestResolver(),
    layoutHintResolver:
        layoutHintResolver ?? const ForumImageLayoutHintResolver(),
    fallbackAspectRatioFor: fallbackAspectRatioFor,
    onBlockImageResolved: onBlockImageResolved,
    imagePrecacheService: imagePrecacheService,
    imageReferer: imageReferer,
  );

  @override
  CacheForumHtmlDisplayImage? resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => CacheForumHtmlDisplayImage.fromSpec(
    ForumImageLoadSpec(
      kind: isSticker ? ForumImageKind.remoteSmiley : contentImageKind,
      url: url,
      ownerId: isSticker ? null : _cacheOwnerId(),
      imageIndex: isSticker ? null : imageIndex,
      htmlWidth: htmlSize?.width,
      htmlHeight: htmlSize?.height,
    ),
    isSticker: isSticker,
    imageRequestResolver: imageRequestResolver,
    layoutHintResolver: layoutHintResolver,
    fallbackAspectRatioFor: fallbackAspectRatioFor,
  );

  @override
  Future<({Size size, ForumHtmlImageLayout layout})?> loadDimensions(
    ForumHtmlDisplayImage image,
  ) async {
    final cachedImage = image as CacheForumHtmlDisplayImage;
    final dimensions = await dimensionIndex.getBySpec(cachedImage.spec);
    if (dimensions == null) return null;
    return (
      size: dimensions.size,
      layout: cachedImage.layoutForCacheDimensions(dimensions),
    );
  }

  @override
  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size) {
    final cachedImage = image as CacheForumHtmlDisplayImage;
    if (cachedImage.isSticker) return;
    _onBlockImageResolved?.call(cachedImage.spec, cachedImage.request, size);
  }

  @override
  Future<void> prefetchDisk(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageWorkScope scope,
  }) async {
    final service = imagePrecacheService;
    if (service == null || !scope.isActive) return;
    final cachedImage = image as CacheForumHtmlDisplayImage;
    if (service case final ScopedForumImagePrecacheService scoped) {
      await scoped.ensureDiskCachedScoped(
        cachedImage.spec,
        scope: _CacheImageWorkScope(scope),
      );
    } else {
      await service.ensureDiskCached(cachedImage.spec);
    }
  }

  @override
  Widget buildImage({
    required ForumHtmlDisplayImage image,
    required BoxFit fit,
    required Widget placeholder,
    double? width,
    double? height,
    Widget? errorPlaceholder,
    VoidCallback? onRetry,
    ValueChanged<Size>? onImageResolved,
    VoidCallback? onImageFailed,
    VoidCallback? onFirstFrameRendered,
    bool showDelayedLoadingIndicator = false,
    bool waitForCacheWrite = false,
    int retryToken = 0,
  }) => CachedLibraryImage(
    request: (image as CacheForumHtmlDisplayImage).request,
    fit: fit,
    placeholder: placeholder,
    width: width,
    height: height,
    errorPlaceholder:
        errorPlaceholder ??
        (onRetry == null
            ? null
            : _ForumHtmlImageErrorPlaceholder(
                cacheKey: image.cacheKey,
                onRetry: onRetry,
              )),
    referer: imageReferer,
    onImageResolved: onImageResolved,
    onImageFailed: onImageFailed,
    onFirstFrameRendered: onFirstFrameRendered == null
        ? null
        : (_) => onFirstFrameRendered(),
    showDelayedLoadingIndicator: showDelayedLoadingIndicator,
    remoteDisplayPolicy: waitForCacheWrite
        ? CachedImageRemoteDisplayPolicy.afterCacheWrite
        : CachedImageRemoteDisplayPolicy.eager,
    retryToken: retryToken,
  );

  String _cacheOwnerId() {
    final owner = imageCacheOwnerId?.trim();
    if (owner != null && owner.isNotEmpty) return owner;
    final tid = threadId.trim();
    return tid.isEmpty ? 'unknown' : tid;
  }
}

final class _CacheImageWorkScope implements ForumImageWorkScope {
  const _CacheImageWorkScope(this.scope);

  final ForumHtmlImageWorkScope scope;

  @override
  bool get isActive => scope.isActive;
}

class _ForumHtmlImageErrorPlaceholder extends StatelessWidget {
  const _ForumHtmlImageErrorPlaceholder({
    required this.cacheKey,
    required this.onRetry,
  });

  final String cacheKey;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    color: Theme.of(
      context,
    ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
    child: ImageRetryPlaceholder(
      onRetry: onRetry,
      retryButtonKey: ValueKey<String>('thread-post-image-retry-$cacheKey'),
    ),
  );
}
