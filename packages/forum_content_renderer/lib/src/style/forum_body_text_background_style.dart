import 'package:flutter/widgets.dart';

/// Paint overrides for existing solid paragraph and ruby container backgrounds.
final class ForumBodyTextBackgroundStyle extends InheritedWidget {
  const ForumBodyTextBackgroundStyle({
    super.key,
    this.color,
    this.borderRadius = 0,
    required super.child,
  }) : assert(borderRadius >= 0 && borderRadius < double.infinity);

  /// Omit to keep the authored color. A color never creates a background.
  final Color? color;

  /// Logical pixels, limited by the actual contour at each convex corner.
  final double borderRadius;

  @override
  bool updateShouldNotify(ForumBodyTextBackgroundStyle oldWidget) =>
      color != oldWidget.color || borderRadius != oldWidget.borderRadius;
}
