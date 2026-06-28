import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

enum ContinuousImageViewportPlacement { above, within, below, unknown }

class ContinuousImageViewportResolver {
  const ContinuousImageViewportResolver();

  ContinuousImageViewportPlacement placementOf(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject == null) {
      return ContinuousImageViewportPlacement.unknown;
    }
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    final scrollable = Scrollable.maybeOf(context);
    if (viewport == null ||
        scrollable == null ||
        !scrollable.position.hasPixels ||
        !scrollable.position.hasViewportDimension) {
      return ContinuousImageViewportPlacement.unknown;
    }
    final topOffset = viewport.getOffsetToReveal(renderObject, 0).offset;
    final bottomOffset = viewport.getOffsetToReveal(renderObject, 1).offset;
    final pixels = scrollable.position.pixels;
    final viewportEnd = pixels + scrollable.position.viewportDimension;
    if (bottomOffset < pixels) {
      return ContinuousImageViewportPlacement.above;
    }
    if (topOffset > viewportEnd) {
      return ContinuousImageViewportPlacement.below;
    }
    return ContinuousImageViewportPlacement.within;
  }

  bool isAboveViewport(BuildContext context) {
    return placementOf(context) == ContinuousImageViewportPlacement.above;
  }
}
