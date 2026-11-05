import 'dart:math' as math;
import 'dart:ui';

/// Compute the content size before fitting the replaced element to the
/// available rectangle. Explicit dimensions may set a different aspect ratio.
Size fitForumBodyReplacedImage({
  required double intrinsicWidth,
  required double aspectRatio,
  required double? width,
  required double? height,
  required double minWidth,
  required double? maxWidth,
  required double availableWidth,
  required double availableHeight,
}) {
  final naturalWidth =
      width ?? (height == null ? intrinsicWidth : height * aspectRatio);
  final usedWidth = math.max(
    minWidth,
    math.min(naturalWidth, maxWidth ?? double.infinity),
  );
  final usedHeight = height ?? usedWidth / aspectRatio;
  final scale = math.min(
    1.0,
    math.min(availableWidth / usedWidth, availableHeight / usedHeight),
  );
  return Size(usedWidth * scale, usedHeight * scale);
}
