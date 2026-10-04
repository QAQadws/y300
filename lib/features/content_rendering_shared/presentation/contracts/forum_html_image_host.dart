import 'package:flutter/widgets.dart';
import 'package:y300/features/cache/domain/models/image_cache_models.dart';
import 'package:y300/features/cache/domain/services/forum_image_dimension_index.dart';

/// The renderer schedules images; the Host owns cache lookup and display.
abstract interface class ForumHtmlImageHost {
  ForumImageDimensionIndex get dimensionIndex;

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
  });
}
