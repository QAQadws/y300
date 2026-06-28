class TallImageSliceManifest {
  const TallImageSliceManifest({
    required this.originalItemId,
    required this.originalCacheKey,
    required this.originalWidth,
    required this.originalHeight,
    required this.targetSliceHeight,
    required this.slices,
  }) : assert(originalWidth > 0),
       assert(originalHeight > 0),
       assert(targetSliceHeight > 0);

  final String originalItemId;
  final String originalCacheKey;
  final int originalWidth;
  final int originalHeight;
  final int targetSliceHeight;
  final List<TallImageSlice> slices;

  int get partCount => slices.length;

  double get originalAspectRatio => originalWidth / originalHeight;
}

class TallImageSlice {
  const TallImageSlice({
    required this.index,
    required this.cacheKey,
    required this.top,
    required this.height,
    required this.width,
  }) : assert(index >= 0),
       assert(top >= 0),
       assert(height > 0),
       assert(width > 0);

  final int index;
  final String cacheKey;
  final int top;
  final int height;
  final int width;

  double get aspectRatio => width / height;
}
