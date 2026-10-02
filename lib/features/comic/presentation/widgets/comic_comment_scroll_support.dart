import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Triggers from actual viewport intersection, never from list cache builds.
class ComicCommentLoadMoreTrigger extends SingleChildRenderObjectWidget {
  const ComicCommentLoadMoreTrigger({
    super.key,
    required this.identity,
    required this.onVisible,
    required super.child,
  });
  final Object identity;
  final VoidCallback onVisible;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _LoadMoreBox(identity, onVisible);
  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _LoadMoreBox).update(identity, onVisible);
  }
}

class _LoadMoreBox extends RenderProxyBox {
  _LoadMoreBox(this.identity, this.onVisible);
  Object identity;
  VoidCallback onVisible;
  bool _reported = false;
  bool _scheduled = false;
  void update(Object next, VoidCallback callback) {
    if (next != identity) _reported = false;
    identity = next;
    onVisible = callback;
    markNeedsPaint();
  }

  bool get visible {
    if (!attached || !hasSize) return false;
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport == null) return false;
    final rect = MatrixUtils.transformRect(
      getTransformTo(viewport),
      Offset.zero & size,
    );
    return rect.overlaps(viewport.paintBounds);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_reported || _scheduled || !visible) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_reported || !visible) return;
      _reported = true;
      onVisible();
    });
  }
}

/// Preserves the floor crossing the viewport's leading edge when a refresh
/// replaces heights above it. Works with both the reader and standalone list.
class ComicCommentScrollAnchor extends StatefulWidget {
  const ComicCommentScrollAnchor({
    super.key,
    required this.owner,
    required this.contentRevision,
    required this.child,
  });
  final Object owner;
  final Object contentRevision;
  final Widget child;
  @override
  State<ComicCommentScrollAnchor> createState() =>
      _ComicCommentScrollAnchorState();
}

class _ComicCommentScrollAnchorState extends State<ComicCommentScrollAnchor> {
  // Consume a revision before scheduling: rebuilding after correction must
  // not hand the same revision to a different floor in this ScrollPosition.
  static final _attempts = Expando<(Object, Object)>(
    'comment anchor revisions',
  );
  int _generation = 0;
  @override
  void didUpdateWidget(covariant ComicCommentScrollAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.owner == widget.owner &&
        oldWidget.contentRevision == widget.contentRevision) {
      return;
    }
    final generation = ++_generation;
    if (oldWidget.owner != widget.owner) return;
    final box = context.findRenderObject();
    final position = Scrollable.maybeOf(context)?.position;
    if (box is! RenderBox ||
        !box.attached ||
        !box.hasSize ||
        position == null ||
        !_canCompensate(position) ||
        position.pixels <= position.minScrollExtent) {
      return;
    }
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final before = MatrixUtils.transformRect(
      box.getTransformTo(viewport),
      Offset.zero & box.size,
    );
    final edge = viewport.paintBounds.top;
    if (before.top > edge || before.bottom <= edge) return;
    final identity = (widget.owner, widget.contentRevision);
    if (_attempts[position] == identity) return;
    _attempts[position] = identity;
    final pixels = position.pixels;
    var interrupted = false;
    void onActivity() {
      if (position.isScrollingNotifier.value) interrupted = true;
    }

    position.isScrollingNotifier.addListener(onActivity);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      position.isScrollingNotifier.removeListener(onActivity);
      if (!mounted ||
          interrupted ||
          generation != _generation ||
          !box.attached ||
          !_canCompensate(position) ||
          !identical(Scrollable.maybeOf(context)?.position, position) ||
          (position.pixels - pixels).abs() > 0.5) {
        return;
      }
      final after = MatrixUtils.transformRect(
        box.getTransformTo(viewport),
        Offset.zero & box.size,
      );
      final delta = after.top - before.top;
      final target = (pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (target.isFinite && (target - pixels).abs() > 0.5) {
        position.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;

  bool _canCompensate(ScrollPosition position) =>
      position.hasContentDimensions &&
      !position.outOfRange &&
      !position.isScrollingNotifier.value &&
      position.userScrollDirection == ScrollDirection.idle;
}
