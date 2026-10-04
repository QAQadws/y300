import 'package:flutter/widgets.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';
import 'package:y300/features/cache/presentation/widgets/cached_library_image.dart';
import 'package:y300/features/content_rendering_shared/presentation/contracts/forum_html_image_host.dart';

final class CacheForumHtmlImageHost implements ForumHtmlImageHost {
  const CacheForumHtmlImageHost({required this.dimensionIndex});

  @override
  final ForumImageDimensionIndex dimensionIndex;

  @override
  Widget buildCachedImage({
    required ImageCacheRequest request,
    required BoxFit fit,
    required Widget placeholder,
    double? width,
    double? height,
    Widget? errorPlaceholder,
    String? referer,
    ValueChanged<Size>? onImageResolved,
    VoidCallback? onImageFailed,
    VoidCallback? onFirstFrameRendered,
    bool showDelayedLoadingIndicator = false,
    bool waitForCacheWrite = false,
    int retryToken = 0,
  }) => CachedLibraryImage(
    request: request,
    fit: fit,
    placeholder: placeholder,
    width: width,
    height: height,
    errorPlaceholder: errorPlaceholder,
    referer: referer,
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
}
