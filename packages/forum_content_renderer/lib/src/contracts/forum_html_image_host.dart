import 'package:flutter/widgets.dart';
import 'forum_html_display_image.dart';

/// The renderer schedules images; the Host owns cache lookup and display.
abstract interface class ForumHtmlImageHost {
  ForumHtmlDisplayImage? resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  });

  Future<({Size size, ForumHtmlImageLayout layout})?> loadDimensions(
    ForumHtmlDisplayImage image,
  );

  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size);

  Future<void> prefetchDisk(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageWorkScope scope,
  });

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
  });
}

enum ForumHtmlImageDimensionPriority { background, nearby, visible }

/// Optional metadata scheduling. Hosts without this capability keep their
/// initial lookup and are not asked to perform viewport-driven retries.
abstract interface class ForumHtmlImageDimensionPriorityHost {
  /// Joins/promotes an existing lookup for this image instead of starting a
  /// duplicate. A completed miss may be retried; active I/O must not be retired.
  Future<({Size size, ForumHtmlImageLayout layout})?>
  loadDimensionsWithPriority(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageDimensionPriority priority,
  });
}
