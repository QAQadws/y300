import 'dart:async';

import 'package:flutter/material.dart';
import 'package:y300/features/content_rendering_shared/content_rendering.dart';

final class NativeImageTestCallbacks {
  const NativeImageTestCallbacks(
    this.index,
    this.resolved,
    this.frame,
    this.failed,
  );
  final int? index;
  final ValueChanged<Size>? resolved;
  final VoidCallback? frame, failed;
}

/// Test-only protocol Host: dimensions and frame delivery are independently
/// controlled, so painting a placeholder cannot accidentally count as reading.
final class NativeReaderImageTestHost
    implements ForumHtmlImageHost, ForumHtmlPreparationImagePolicy {
  NativeReaderImageTestHost({this.aspectRatio = 1});
  final double aspectRatio;
  final callbacks = <NativeImageTestCallbacks>[];
  final dimensions = <Completer<({Size size, ForumHtmlImageLayout layout})?>>[];
  final resolvedSizes = <Size>[];
  NativeImageTestCallbacks callback(int? index) =>
      callbacks.lastWhere((c) => c.index == index);
  void completeDimensions() {
    for (final pending in dimensions) {
      if (!pending.isCompleted) pending.complete(null);
    }
  }

  @override
  ForumHtmlPreparedImageResource? prepareInline({
    required Uri url,
    required String? threadId,
    required String? imageCacheOwnerId,
    required int imageIndex,
    double? htmlWidth,
    double? htmlHeight,
    String? alt,
    String? title,
  }) => _Resource('image:$imageIndex');
  @override
  ForumHtmlDisplayImage? resolveImage({
    required Uri url,
    required int? imageIndex,
    required bool isSticker,
    Size? htmlSize,
  }) => _Display(
    url.toString(),
    isSticker ? 'sticker:$url' : 'image:$imageIndex',
    aspectRatio,
    htmlSize,
    isSticker,
  );
  @override
  Future<({Size size, ForumHtmlImageLayout layout})?> loadDimensions(
    ForumHtmlDisplayImage image,
  ) {
    final pending = Completer<({Size size, ForumHtmlImageLayout layout})?>();
    dimensions.add(pending);
    return pending.future;
  }

  @override
  void onBlockImageResolved(ForumHtmlDisplayImage image, Size size) =>
      resolvedSizes.add(size);
  @override
  Future<void> prefetchDisk(
    ForumHtmlDisplayImage image, {
    required ForumHtmlImageWorkScope scope,
  }) async {}
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
  }) {
    final index = image.isSticker
        ? null
        : int.parse(image.cacheKey.substring(6));
    callbacks.add(
      NativeImageTestCallbacks(
        index,
        onImageResolved,
        onFirstFrameRendered,
        onImageFailed,
      ),
    );
    return ColoredBox(
      key: ValueKey('native-test-image-$index'),
      color: Colors.blue,
    );
  }
}

final class _Resource implements ForumHtmlPreparedImageResource {
  const _Resource(this.cacheKey);
  @override
  final String cacheKey;
}

final class _Display implements ForumHtmlDisplayImage {
  const _Display(
    this.sourceUrl,
    this.cacheKey,
    this.ratio,
    this.htmlSize,
    this.isSticker,
  );
  @override
  final String sourceUrl, cacheKey;
  final double ratio;
  @override
  final Size? htmlSize;
  @override
  Object get identity => (sourceUrl, cacheKey);
  @override
  final bool isSticker;
  @override
  ForumHtmlImageLayout get initialLayout => isSticker
      ? ForumHtmlImageLayout(displaySize: htmlSize)
      : ForumHtmlImageLayout(aspectRatio: ratio, isFallback: true);
}
