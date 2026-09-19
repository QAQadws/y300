import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:y300/features/thread/domain/models/thread_quick_scroll_dock_side.dart';

/// Physical left/right anchors, sharing Scaffold's floating vertical geometry.
final class ThreadQuickScrollDockLocation extends StandardFabLocation
    with FabFloatOffsetY {
  const ThreadQuickScrollDockLocation(this.side);

  final ThreadQuickScrollDockSide side;

  @override
  double getOffsetX(
    ScaffoldPrelayoutGeometry scaffoldGeometry,
    double adjustment,
  ) {
    final margin =
        kFloatingActionButtonMargin +
        math.max(
          scaffoldGeometry.minInsets.left,
          scaffoldGeometry.minInsets.right,
        );
    return switch (side) {
      ThreadQuickScrollDockSide.left => margin,
      ThreadQuickScrollDockSide.right =>
        scaffoldGeometry.scaffoldSize.width -
            margin -
            scaffoldGeometry.floatingActionButtonSize.width,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ThreadQuickScrollDockLocation && other.side == side;

  @override
  int get hashCode => side.hashCode;
}
