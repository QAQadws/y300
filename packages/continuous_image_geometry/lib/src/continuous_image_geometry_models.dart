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

class ContinuousImageLayoutHint {
  const ContinuousImageLayoutHint({
    required this.aspectRatio,
    required this.source,
  }) : assert(aspectRatio > 0);

  final double aspectRatio;
  final ContinuousImageDimensionSource source;
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

/// Read-only layout input. Implement this on a host model to avoid copying lists.
///
/// Items are ordered by list position; [index] is the logical image index returned
/// by viewport queries. Item IDs must be unique within an active layout.
abstract interface class ContinuousImageLayoutItem {
  String get id;
  int get index;
  ContinuousImageDimensions? get knownDimensions;
  ContinuousImageDimensionSource get effectiveKnownDimensionSource;
  double get fallbackAspectRatio;
  double get spacingAfter;
}
