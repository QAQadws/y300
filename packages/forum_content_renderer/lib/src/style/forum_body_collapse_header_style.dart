import 'package:flutter/material.dart';

/// Paint overrides for native collapse headers in this subtree.
///
/// Omitted properties use the renderer's defaults. The decoration consumes
/// this scope after pagination, so changing it keeps the current layout.
final class ForumBodyCollapseHeaderStyle extends InheritedWidget {
  const ForumBodyCollapseHeaderStyle({
    super.key,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
    required super.child,
  });

  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadiusGeometry? borderRadius;

  @override
  bool updateShouldNotify(ForumBodyCollapseHeaderStyle oldWidget) =>
      backgroundColor != oldWidget.backgroundColor ||
      borderColor != oldWidget.borderColor ||
      borderRadius != oldWidget.borderRadius;
}
