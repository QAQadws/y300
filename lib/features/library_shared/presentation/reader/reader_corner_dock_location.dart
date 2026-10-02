import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:y300/features/library_shared/domain/models/reader_corner_dock_side.dart';

/// Physical left/right FAB placement, independent of reading direction.
final class ReaderCornerDockLocation extends StandardFabLocation
    with FabFloatOffsetY {
  const ReaderCornerDockLocation(this.side);

  final ReaderCornerDockSide side;

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
    return side == ReaderCornerDockSide.left
        ? margin
        : scaffoldGeometry.scaffoldSize.width -
              margin -
              scaffoldGeometry.floatingActionButtonSize.width;
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderCornerDockLocation && other.side == side;

  @override
  int get hashCode => side.hashCode;
}
