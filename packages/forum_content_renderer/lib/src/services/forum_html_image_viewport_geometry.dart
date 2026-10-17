import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Finds the viewport owned by [position], past any nested table scroll views.
RenderAbstractViewport? forumHtmlImageViewportFor(
  RenderObject target,
  ScrollPosition position,
) {
  final boundary = position.context.notificationContext?.findRenderObject();
  if (!target.attached || boundary == null || !boundary.attached) return null;

  RenderAbstractViewport? viewport;
  RenderObject? ancestor = target;
  while (ancestor != null && !identical(ancestor, boundary)) {
    if (ancestor is RenderAbstractViewport) viewport = ancestor;
    ancestor = ancestor.parent;
  }
  return identical(ancestor, boundary) ? viewport : null;
}
