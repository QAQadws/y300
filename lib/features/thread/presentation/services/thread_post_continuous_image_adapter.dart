import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';
import 'package:y300/features/thread/domain/models/thread_post_body_document.dart';
import 'package:y300/features/thread/domain/models/thread_post_resource_layout_hints.dart';

class ThreadPostContinuousImageAdapter {
  const ThreadPostContinuousImageAdapter();

  ContinuousImageItem mapBlockImage({
    required String ownerId,
    required ThreadPostImageBlock image,
    required double fallbackAspectRatio,
    required double spacingAfter,
    ThreadPostBlockImageLayoutHint? layoutHint,
    String? cacheKey,
    bool includeContentDefaultHint = false,
  }) {
    final effectiveCacheKey = _effectiveCacheKey(
      image: image,
      cacheKey: cacheKey,
    );
    final dimensions = _dimensionsFor(
      image: image,
      layoutHint: layoutHint,
      includeContentDefaultHint: includeContentDefaultHint,
    );
    return ContinuousImageItem(
      ownerId: ownerId,
      id: '$ownerId:${image.index}:$effectiveCacheKey',
      url: image.url,
      cacheKey: effectiveCacheKey,
      index: image.index,
      sourceKind: ContinuousImageSourceKind.threadPostImage,
      knownWidth: dimensions?.width,
      knownHeight: dimensions?.height,
      knownDimensionSource: dimensions?.source,
      fallbackAspectRatio: fallbackAspectRatio,
      spacingAfter: spacingAfter,
      extra: <String, Object?>{
        if (image.anchorId.trim().isNotEmpty) 'anchorId': image.anchorId,
        if (image.aid != null) 'aid': image.aid,
      },
    );
  }

  _ThreadImageDimensions? _dimensionsFor({
    required ThreadPostImageBlock image,
    required ThreadPostBlockImageLayoutHint? layoutHint,
    required bool includeContentDefaultHint,
  }) {
    final width = image.originalWidth;
    final height = image.originalHeight;
    if (width != null &&
        height != null &&
        width.isFinite &&
        height.isFinite &&
        width > 0 &&
        height > 0) {
      return _ThreadImageDimensions(
        width: width.round(),
        height: height.round(),
        source: ContinuousImageDimensionSource.html,
      );
    }
    final hint = layoutHint;
    if (hint == null ||
        hint.aspectRatio <= 0 ||
        !hint.aspectRatio.isFinite ||
        (!includeContentDefaultHint &&
            hint.source == ThreadPostResourceLayoutHintSource.contentDefault)) {
      return null;
    }
    // Layout hints may come from cached dimensions where only the ratio is
    // available to this widget.  A ratio-preserving synthetic dimension keeps
    // the shared resolver source-aware without pretending to know real pixels.
    const syntheticHeight = 1000;
    return _ThreadImageDimensions(
      width: (hint.aspectRatio * syntheticHeight).round(),
      height: syntheticHeight,
      source: _mapHintSource(hint.source),
    );
  }

  ContinuousImageDimensionSource _mapHintSource(
    ThreadPostResourceLayoutHintSource source,
  ) {
    switch (source) {
      case ThreadPostResourceLayoutHintSource.htmlAttribute:
        return ContinuousImageDimensionSource.html;
      case ThreadPostResourceLayoutHintSource.cachedDimension:
        return ContinuousImageDimensionSource.persistedCache;
      case ThreadPostResourceLayoutHintSource.contentDefault:
        return ContinuousImageDimensionSource.fallback;
    }
  }

  String _effectiveCacheKey({
    required ThreadPostImageBlock image,
    required String? cacheKey,
  }) {
    final explicit = cacheKey?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final raw = image.rawUrl.trim();
    return raw.isEmpty ? image.url : raw;
  }
}

class _ThreadImageDimensions {
  const _ThreadImageDimensions({
    required this.width,
    required this.height,
    required this.source,
  });

  final int width;
  final int height;
  final ContinuousImageDimensionSource source;
}
