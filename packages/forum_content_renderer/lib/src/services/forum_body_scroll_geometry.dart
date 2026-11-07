import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Finds the viewport owned by [position], past any nested table scroll views.
RenderAbstractViewport? forumBodyViewportForPosition(
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

/// Physical intersection in the mounted box's coordinates. A cached list
/// child outside the viewport has no visible range even if still attached.
Rect? forumBodyVisibleBoxClip(RenderBox box, ScrollPosition? position) {
  final viewport = forumBodyBoxViewportBounds(box, position);
  if (viewport == null) return null;
  final clip = viewport.intersect(Offset.zero & box.size);
  return clip.isFinite && !clip.isEmpty ? clip : Rect.zero;
}

/// Unclipped viewport coordinates also locate a mounted list child just outside
/// the screen. Callers explicitly bound any optional preparation around it.
Rect? forumBodyBoxViewportBounds(RenderBox box, ScrollPosition? position) {
  if (!box.attached || !box.hasSize) return null;
  RenderObject? viewport;
  if (position == null) {
    viewport = box;
    while (viewport?.parent != null) {
      viewport = viewport!.parent;
    }
  } else {
    viewport = forumBodyViewportForPosition(box, position);
  }
  if (viewport == null || !viewport.attached) return null;
  final outerClip = MatrixUtils.transformRect(
    viewport.getTransformTo(box),
    viewport.paintBounds,
  );
  return outerClip.isFinite ? outerClip : null;
}

/// Observes position changes through a retained composited layer.
final class ForumBodyCompositionObserver extends SingleChildRenderObjectWidget {
  const ForumBodyCompositionObserver({
    super.key,
    required this.onComposited,
    required super.child,
  });

  final VoidCallback onComposited;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderForumBodyCompositionObserver(onComposited);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderForumBodyCompositionObserver).onComposited =
          onComposited;
}

final class _RenderForumBodyCompositionObserver extends RenderProxyBox {
  _RenderForumBodyCompositionObserver(this.onComposited);

  VoidCallback onComposited;
  VoidCallback? _removeCallback;

  @override
  void paint(PaintingContext context, Offset offset) {
    _removeCallback?.call();
    _removeCallback = context.addCompositionCallback((_) => onComposited());
    super.paint(context, offset);
  }

  @override
  void detach() {
    _removeCallback?.call();
    _removeCallback = null;
    super.detach();
  }
}
