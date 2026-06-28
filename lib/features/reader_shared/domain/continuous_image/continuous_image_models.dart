import 'tall_image/tall_image_policy.dart';

enum ContinuousImageSourceKind { comicPage, threadPostImage, threadImageReader }

enum ContinuousImageDimensionSource {
  html,
  persistedCache,
  decodedImage,
  probedHeader,
  fallback,
}

enum ContinuousImageScrollDirection { idle, forward, reverse }

class ContinuousImageDimensions {
  const ContinuousImageDimensions({required this.width, required this.height});

  final int width;
  final int height;

  bool get isValid => width > 0 && height > 0;

  double? get aspectRatioOrNull {
    if (!isValid) {
      return null;
    }
    return width / height;
  }
}

class ContinuousImageItem {
  const ContinuousImageItem({
    required this.ownerId,
    required this.id,
    required this.url,
    required this.cacheKey,
    required this.index,
    required this.sourceKind,
    this.referer,
    this.knownWidth,
    this.knownHeight,
    this.knownDimensionSource,
    this.fallbackAspectRatio = 0.7,
    this.spacingAfter = 0,
    this.extra = const <String, Object?>{},
  }) : assert(index >= 0),
       assert(fallbackAspectRatio > 0),
       assert(spacingAfter >= 0);

  final String ownerId;
  final String id;
  final String url;
  final String cacheKey;
  final int index;
  final ContinuousImageSourceKind sourceKind;
  final Uri? referer;
  final int? knownWidth;
  final int? knownHeight;
  final ContinuousImageDimensionSource? knownDimensionSource;
  final double fallbackAspectRatio;
  final double spacingAfter;
  final Map<String, Object?> extra;

  ContinuousImageDimensions? get knownDimensions {
    final width = knownWidth;
    final height = knownHeight;
    if (width == null || height == null) {
      return null;
    }
    final dimensions = ContinuousImageDimensions(width: width, height: height);
    return dimensions.isValid ? dimensions : null;
  }

  ContinuousImageDimensionSource get effectiveKnownDimensionSource {
    return knownDimensionSource ??
        ContinuousImageDimensionSource.persistedCache;
  }

  ContinuousImageItem copyWith({
    String? ownerId,
    String? id,
    String? url,
    String? cacheKey,
    int? index,
    ContinuousImageSourceKind? sourceKind,
    Uri? referer,
    int? knownWidth,
    int? knownHeight,
    ContinuousImageDimensionSource? knownDimensionSource,
    double? fallbackAspectRatio,
    double? spacingAfter,
    Map<String, Object?>? extra,
  }) {
    return ContinuousImageItem(
      ownerId: ownerId ?? this.ownerId,
      id: id ?? this.id,
      url: url ?? this.url,
      cacheKey: cacheKey ?? this.cacheKey,
      index: index ?? this.index,
      sourceKind: sourceKind ?? this.sourceKind,
      referer: referer ?? this.referer,
      knownWidth: knownWidth ?? this.knownWidth,
      knownHeight: knownHeight ?? this.knownHeight,
      knownDimensionSource: knownDimensionSource ?? this.knownDimensionSource,
      fallbackAspectRatio: fallbackAspectRatio ?? this.fallbackAspectRatio,
      spacingAfter: spacingAfter ?? this.spacingAfter,
      extra: extra ?? this.extra,
    );
  }
}

class ContinuousImageLayoutHint {
  const ContinuousImageLayoutHint({
    required this.aspectRatio,
    required this.source,
  }) : assert(aspectRatio > 0);

  final double aspectRatio;
  final ContinuousImageDimensionSource source;
}

class ContinuousImageFlowPolicy {
  const ContinuousImageFlowPolicy({
    this.fitWidth = true,
    this.updateVisibleItemAspectRatio = true,
    this.deferAboveViewportAspectRatioUpdate = false,
    this.allowScrollOffsetCompensation = false,
    this.viewportCacheExtentFactor = 0,
    this.prefetchWindowBefore = 0,
    this.prefetchWindowAfter = 0,
    this.tallImagePolicy = TallImagePolicy.disabled,
  }) : assert(viewportCacheExtentFactor >= 0),
       assert(prefetchWindowBefore >= 0),
       assert(prefetchWindowAfter >= 0);

  static const threadPostReading = ContinuousImageFlowPolicy(
    fitWidth: true,
    updateVisibleItemAspectRatio: true,
    deferAboveViewportAspectRatioUpdate: true,
  );

  static const comicVerticalReading = ContinuousImageFlowPolicy(
    fitWidth: true,
    updateVisibleItemAspectRatio: true,
    deferAboveViewportAspectRatioUpdate: true,
    allowScrollOffsetCompensation: true,
    viewportCacheExtentFactor: 0.75,
    prefetchWindowBefore: 1,
    prefetchWindowAfter: 3,
    tallImagePolicy: TallImagePolicy.mihonLike,
  );

  final bool fitWidth;
  final bool updateVisibleItemAspectRatio;
  final bool deferAboveViewportAspectRatioUpdate;
  final bool allowScrollOffsetCompensation;
  final double viewportCacheExtentFactor;
  final int prefetchWindowBefore;
  final int prefetchWindowAfter;
  final TallImagePolicy tallImagePolicy;
}

class ContinuousImageViewportState {
  const ContinuousImageViewportState({
    required this.firstVisibleIndex,
    required this.lastVisibleIndex,
    required this.lastEndVisibleIndex,
    required this.scrollOffset,
    required this.viewportExtent,
    required this.userScrollDirection,
  }) : assert(scrollOffset >= 0),
       assert(viewportExtent >= 0);

  final int? firstVisibleIndex;
  final int? lastVisibleIndex;
  final int? lastEndVisibleIndex;
  final double scrollOffset;
  final double viewportExtent;
  final ContinuousImageScrollDirection userScrollDirection;
}

class ContinuousImageExtent {
  const ContinuousImageExtent({
    required this.ownerId,
    required this.itemId,
    required this.index,
    required this.crossAxisExtent,
    required this.mainAxisExtent,
    required this.aspectRatio,
    required this.dimensionSource,
    required this.measuredAt,
  }) : assert(index >= 0),
       assert(crossAxisExtent > 0),
       assert(mainAxisExtent >= 0),
       assert(aspectRatio > 0);

  final String ownerId;
  final String itemId;
  final int index;
  final double crossAxisExtent;
  final double mainAxisExtent;
  final double aspectRatio;
  final ContinuousImageDimensionSource dimensionSource;
  final DateTime measuredAt;
}

abstract interface class ContinuousImageDimensionSink {
  Future<void> recordDecodedDimensions({
    required ContinuousImageItem item,
    required int width,
    required int height,
  });
}
