import 'package:continuous_image_geometry/continuous_image_geometry.dart';

import 'tall_image/tall_image_policy.dart';

enum ContinuousImageSourceKind {
  comicPage,
  threadPostImage,
  threadImageReader,
  genericImageReader,
}

class ContinuousImageItem implements ContinuousImageLayoutItem {
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
  @override
  final String id;
  final String url;
  final String cacheKey;
  @override
  final int index;
  final ContinuousImageSourceKind sourceKind;
  final Uri? referer;
  final int? knownWidth;
  final int? knownHeight;
  final ContinuousImageDimensionSource? knownDimensionSource;
  @override
  final double fallbackAspectRatio;
  @override
  final double spacingAfter;
  final Map<String, Object?> extra;

  @override
  ContinuousImageDimensions? get knownDimensions {
    final width = knownWidth;
    final height = knownHeight;
    if (width == null || height == null) {
      return null;
    }
    final dimensions = ContinuousImageDimensions(width: width, height: height);
    return dimensions.isValid ? dimensions : null;
  }

  @override
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
    // 配合全局解码预算（Phase 0）与降采样，扩大上下缓冲到约 1.5 屏，使来回滚动
    // 时缓冲区内的已解码图片常驻、不重解码。单图已降采样，内存代价可控。
    viewportCacheExtentFactor: 1.5,
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

abstract interface class ContinuousImageDimensionSink {
  Future<void> recordDecodedDimensions({
    required ContinuousImageItem item,
    required int width,
    required int height,
  });
}
