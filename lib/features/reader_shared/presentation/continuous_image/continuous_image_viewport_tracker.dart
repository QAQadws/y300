import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:y300/features/reader_shared/domain/continuous_image/continuous_image.dart';

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
    if (items.isEmpty || viewportExtent <= 0 || crossAxisExtent <= 0) {
      return ContinuousImageViewportState(
        firstVisibleIndex: null,
        lastVisibleIndex: null,
        lastEndVisibleIndex: null,
        scrollOffset: scrollOffset.clamp(0, double.infinity).toDouble(),
        viewportExtent: viewportExtent.clamp(0, double.infinity).toDouble(),
        userScrollDirection: userScrollDirection,
      );
    }

    final viewportStart = scrollOffset.clamp(0, double.infinity).toDouble();
    final viewportEnd = viewportStart + viewportExtent;
    int? firstVisibleIndex;
    int? lastVisibleIndex;
    int? lastEndVisibleIndex;
    var cursor = 0.0;

    for (final item in items) {
      final mainAxisExtent =
          extentRegistry.extentOf(item.id)?.mainAxisExtent ??
          _estimatedMainAxisExtent(item, crossAxisExtent);
      final itemStart = cursor;
      final itemEnd = itemStart + mainAxisExtent;
      final isVisible = itemEnd >= viewportStart && itemStart <= viewportEnd;
      if (isVisible) {
        firstVisibleIndex ??= item.index;
        lastVisibleIndex = item.index;
      }
      if (itemEnd >= viewportStart && itemEnd <= viewportEnd) {
        lastEndVisibleIndex = item.index;
      }
      cursor = itemEnd + item.spacingAfter;
    }

    return ContinuousImageViewportState(
      firstVisibleIndex: firstVisibleIndex,
      lastVisibleIndex: lastVisibleIndex,
      lastEndVisibleIndex: lastEndVisibleIndex,
      scrollOffset: viewportStart,
      viewportExtent: viewportExtent,
      userScrollDirection: userScrollDirection,
    );
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
