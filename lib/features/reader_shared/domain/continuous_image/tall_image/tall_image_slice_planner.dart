import 'tall_image_policy.dart';
import 'tall_image_slice_manifest.dart';

class TallImageSlicePlanner {
  const TallImageSlicePlanner();

  TallImageSliceManifest? plan({
    required String originalItemId,
    required String originalCacheKey,
    required int imageWidth,
    required int imageHeight,
    required double viewportMainAxisExtent,
    required TallImagePolicy policy,
  }) {
    if (!policy.shouldSplit(
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      viewportMainAxisExtent: viewportMainAxisExtent,
    )) {
      return null;
    }
    final targetSliceHeight = policy.optimalImageHeightForViewport(
      viewportMainAxisExtent,
    );
    final slices = <TallImageSlice>[];
    var top = 0;
    while (top < imageHeight) {
      final remaining = imageHeight - top;
      final height = remaining < targetSliceHeight
          ? remaining
          : targetSliceHeight;
      slices.add(
        TallImageSlice(
          index: slices.length,
          cacheKey: '$originalCacheKey#slice-${slices.length}',
          top: top,
          height: height,
          width: imageWidth,
        ),
      );
      top += height;
    }
    return TallImageSliceManifest(
      originalItemId: originalItemId,
      originalCacheKey: originalCacheKey,
      originalWidth: imageWidth,
      originalHeight: imageHeight,
      targetSliceHeight: targetSliceHeight,
      slices: List<TallImageSlice>.unmodifiable(slices),
    );
  }
}
