import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

import 'continuous_image_viewport_resolver.dart';

class ContinuousImageViewportTracker {
  const ContinuousImageViewportTracker({
    this.layoutResolver = const ContinuousImageLayoutResolver(),
  });

  final ContinuousImageLayoutResolver layoutResolver;

  ContinuousImageViewportState resolve({
    required List<ContinuousImageItem> items,
    required ContinuousImageExtentRegistry extentRegistry,
    required double scrollOffset,
    required double viewportExtent,
    required double crossAxisExtent,
    required ContinuousImageScrollDirection userScrollDirection,
  }) {
    return ContinuousImageLayoutIndex(
      items: items,
      extentRegistry: extentRegistry,
      crossAxisExtent: crossAxisExtent,
      resolver: layoutResolver,
    ).resolve(
      scrollOffset: scrollOffset,
      viewportExtent: viewportExtent,
      userScrollDirection: userScrollDirection,
    );
  }

  ContinuousImageViewportPlacement placementOf({
    required String itemId,
    required List<ContinuousImageItem> items,
    required ContinuousImageExtentRegistry extentRegistry,
    required double scrollOffset,
    required double viewportExtent,
    required double crossAxisExtent,
  }) {
    if (items.isEmpty || viewportExtent <= 0 || crossAxisExtent <= 0) {
      return ContinuousImageViewportPlacement.unknown;
    }
    final viewportStart = scrollOffset.clamp(0, double.infinity).toDouble();
    final viewportEnd = viewportStart + viewportExtent;
    var cursor = 0.0;
    for (final item in items) {
      final mainAxisExtent =
          extentRegistry.extentOf(item.id)?.mainAxisExtent ??
          _estimatedMainAxisExtent(item, crossAxisExtent);
      final itemStart = cursor;
      final itemEnd = itemStart + mainAxisExtent;
      if (item.id == itemId) {
        if (itemEnd < viewportStart) {
          return ContinuousImageViewportPlacement.above;
        }
        if (itemStart > viewportEnd) {
          return ContinuousImageViewportPlacement.below;
        }
        return ContinuousImageViewportPlacement.within;
      }
      cursor = itemEnd + item.spacingAfter;
    }
    return ContinuousImageViewportPlacement.unknown;
  }

  bool isAboveViewport({
    required String itemId,
    required List<ContinuousImageItem> items,
    required ContinuousImageExtentRegistry extentRegistry,
    required double scrollOffset,
    required double viewportExtent,
    required double crossAxisExtent,
  }) {
    return placementOf(
          itemId: itemId,
          items: items,
          extentRegistry: extentRegistry,
          scrollOffset: scrollOffset,
          viewportExtent: viewportExtent,
          crossAxisExtent: crossAxisExtent,
        ) ==
        ContinuousImageViewportPlacement.above;
  }

  bool isWithinViewport({
    required String itemId,
    required List<ContinuousImageItem> items,
    required ContinuousImageExtentRegistry extentRegistry,
    required double scrollOffset,
    required double viewportExtent,
    required double crossAxisExtent,
  }) {
    return placementOf(
          itemId: itemId,
          items: items,
          extentRegistry: extentRegistry,
          scrollOffset: scrollOffset,
          viewportExtent: viewportExtent,
          crossAxisExtent: crossAxisExtent,
        ) ==
        ContinuousImageViewportPlacement.within;
  }

  bool isBelowViewport({
    required String itemId,
    required List<ContinuousImageItem> items,
    required ContinuousImageExtentRegistry extentRegistry,
    required double scrollOffset,
    required double viewportExtent,
    required double crossAxisExtent,
  }) {
    return placementOf(
          itemId: itemId,
          items: items,
          extentRegistry: extentRegistry,
          scrollOffset: scrollOffset,
          viewportExtent: viewportExtent,
          crossAxisExtent: crossAxisExtent,
        ) ==
        ContinuousImageViewportPlacement.below;
  }

  ContinuousImageScrollDirection directionFromPosition(
    ScrollPosition position,
  ) {
    return directionFromFlutter(position.userScrollDirection);
  }

  ContinuousImageScrollDirection directionFromFlutter(
    ScrollDirection direction,
  ) {
    switch (direction) {
      case ScrollDirection.forward:
        return ContinuousImageScrollDirection.reverse;
      case ScrollDirection.reverse:
        return ContinuousImageScrollDirection.forward;
      case ScrollDirection.idle:
        return ContinuousImageScrollDirection.idle;
    }
  }

  double _estimatedMainAxisExtent(
    ContinuousImageItem item,
    double crossAxisExtent,
  ) {
    final hint = layoutResolver.resolveInitialHint(item: item);
    return crossAxisExtent / hint.aspectRatio;
  }
}
